import AppKit
import Combine

/// SSID 변경을 구독하고, 매칭 프로필의 월페이퍼를 적용한다.
@MainActor
class SwitchController: ObservableObject {
    @Published private(set) var activeProfile: Profile?

    private let profileManager: ProfileManager
    private let locationWatcher: LocationWatcher
    private var cancellable: AnyCancellable?

    init(profileManager: ProfileManager, locationWatcher: LocationWatcher) {
        self.profileManager = profileManager
        self.locationWatcher = locationWatcher

        cancellable = locationWatcher.$currentSSID
            .sink { [weak self] ssid in
                self?.onSSIDChange(ssid)
            }
    }

    /// 메뉴바 등에서 수동으로 프로필을 전환할 때 사용한다.
    func apply(_ profile: Profile) {
        applyProfile(profile)
    }

    private func onSSIDChange(_ ssid: String?) {
        guard let profile = profileManager.profileFor(ssid: ssid) else { return }
        guard profile.id != activeProfile?.id else { return }
        applyProfile(profile)
    }

    private func applyProfile(_ profile: Profile) {
        activeProfile = profile
        profileManager.activeProfileID = profile.id
        let path = profile.wallpaperPath
        guard !path.isEmpty else { return }
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4", "mov":
            applyVideo(path)
        case "jpg", "jpeg", "png":
            applyImage(path)
        default:
            break
        }
    }

    /// mp4/mov: WallpaperEngine으로 모든 디스플레이에 루프 재생
    private func applyVideo(_ path: String) {
        guard let engine = sharedEngine else { return }
        let displayIDs = NSScreen.screens.compactMap {
            $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        }
        engine.startWallpaper(withPath: path, onDisplays: displayIDs)
    }

    /// jpg/png: NSWorkspace로 정적 배경 설정, 기존 라이브 데몬 종료
    private func applyImage(_ path: String) {
        let url = URL(fileURLWithPath: path)
        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
        sharedEngine?.killAllDaemons()
    }
}
