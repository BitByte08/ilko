import AppKit
import Combine
import SwiftUI

// MARK: - Video Item
struct VideoItem: Identifiable {
    let id = UUID()
    let filename: String
    let path: String
    let thumbnailPath: String
    var quality: String?

    func loadThumbnail() -> NSImage? {
        return ThumbnailCache.shared.image(for: thumbnailPath)
    }
}

// WallpaperEngine은 upstream ObjC 클래스이므로 Swift에서 Sendable 선언을 추가합니다.
// 실제 스레드 안전성은 WallpaperEngine 내부 구현(dispatch queue)이 보장합니다.
extension WallpaperEngine: @unchecked Sendable {}

/// continuation을 정확히 한 번만 resume 하도록 보장하는 스레드 세이프 가드.
/// ObjC 콜백이 끝내 오지 않아도 timeout 경로에서 안전하게 nil로 resume 할 수 있게 한다.
nonisolated private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

// MARK: - Wallpaper View Model
// @MainActor 격리가 모든 접근을 메인 스레드로 직렬화하므로 @unchecked Sendable이 안전합니다.
@MainActor
class WallpaperViewModel: ObservableObject, @unchecked Sendable {

    @Published var videos: [VideoItem] = []
    @Published var folderPath: String = ""
    @Published var scaleMode: String = "fill"
    @Published var randomOnStartup: Bool = false
    @Published var pauseOnAppFocus: Bool = true
    @Published var volume: Double = 50.0
    @Published var vinttageBar: Bool = true

    private var reloadTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard
    let engine: WallpaperEngine

    /// `engine`을 명시적으로 전달하는 것이 권장됩니다.
    /// ContentView의 @StateObject 생성자에서는 모듈 수준 sharedEngine을 사용합니다.
    init(engine: WallpaperEngine = sharedEngine ?? WallpaperEngine.shared()) {
        self.engine = engine
        loadSettings()
        self.engine.setupNotifications()
    }

    func invalidate() {
        reloadTask?.cancel()
        engine.removeNotifications()
    }

    func loadSettings() {
        folderPath = engine.getFolderPath()
        scaleMode = defaults.string(forKey: UserDefaultsKeys.scaleMode) ?? "fill"
        randomOnStartup = defaults.bool(forKey: UserDefaultsKeys.randomOnStartup)
        pauseOnAppFocus = defaults.bool(forKey: UserDefaultsKeys.pauseOnAppFocus)
        volume = Double(defaults.float(forKey: UserDefaultsKeys.volumePercentage))
        vinttageBar = defaults.bool(forKey: UserDefaultsKeys.vignetteBar)
    }

    func reloadContent() {
        engine.checkFolderPath()
        ThumbnailCache.shared.clearCache()

        guard let files = try? FileManager.default.contentsOfDirectory(atPath: folderPath) else {
            return
        }

        let videoFiles = files.filter { f in
            let e = (f as NSString).pathExtension.lowercased()
            return e == "mp4" || e == "mov"
        }

        let folderSnapshot = folderPath
        let engine = self.engine

        // 1) 화질 배지 로딩을 기다리지 않고 목록을 즉시 구성하고 썸네일 생성을 바로 시작한다.
        //    한 영상의 videoQualityBadge(AVAsset 로딩)가 지연/멈춰도 썸네일 생성이
        //    막히지 않도록 배지 로딩과 썸네일 생성을 분리한다.
        let items: [VideoItem] = videoFiles.map { f in
            let full = (folderSnapshot as NSString).appendingPathComponent(f)
            let base = (f as NSString).deletingPathExtension
            let thumbPath =
                (engine.thumbnailCachePath() as NSString?)?.appendingPathComponent("\(base).png") ?? ""
            return VideoItem(filename: f, path: full, thumbnailPath: thumbPath, quality: nil)
        }
        self.videos = items
        let missingCount = items.filter { $0.loadThumbnail() == nil }.count
        if missingCount > 0 {
            NSLog("Found \(missingCount) videos without thumbnails, generating...")
            engine.generateThumbnails()
        }

        // 2) 화질 배지는 백그라운드에서 개별 타임아웃과 함께 점진적으로 채운다.
        //    한 영상의 로딩이 멈춰도 다른 영상/썸네일에는 영향이 없다.
        reloadTask?.cancel()
        reloadTask = Task.detached(priority: .utility) { [weak self] in
            for item in items {
                guard !Task.isCancelled else { return }
                let badge = await WallpaperViewModel.loadQualityBadge(
                    engine: engine, path: item.path, timeout: 4.0)
                guard let badge, !badge.isEmpty else { continue }
                await MainActor.run { [weak self] in
                    guard let self,
                        let idx = self.videos.firstIndex(where: { $0.id == item.id })
                    else { return }
                    self.videos[idx].quality = badge
                }
            }
        }
    }

    /// videoQualityBadge(ObjC 콜백)를 async로 감싸되, 콜백이 끝내 오지 않아도 timeout 후
    /// nil로 resume 되도록 보장한다 — 멈춘 AVAsset 로딩이 목록 구성 전체를 막지 못하게 한다.
    nonisolated private static func loadQualityBadge(
        engine: WallpaperEngine, path: String, timeout: TimeInterval
    ) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            let guardOnce = ResumeOnce()
            engine.videoQualityBadge(for: URL(fileURLWithPath: path)) { badge in
                if guardOnce.claim() { cont.resume(returning: badge) }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if guardOnce.claim() { cont.resume(returning: nil) }
            }
        }
    }

    /// 썸네일 생성 실패(무한 스피너) 타일의 재시도 진입점.
    /// 지정한 경로가 있으면 해당 썸네일 캐시 항목을 무효화한 뒤 엔진에 재생성을 요청한다.
    func regenerateThumbnails(for path: String? = nil) {
        if let path {
            ThumbnailCache.shared.forceRefresh(path: path)
        }
        engine.generateThumbnails()
    }

    func startWallpaper(video: VideoItem) {
        let displays = NSScreen.screens.compactMap {
            $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        }
        engine.startWallpaper(withPath: video.path, onDisplays: displays)
    }

    func clearCache() {
        engine.clearCache()
        ThumbnailCache.shared.clearCache()
        reloadContent()
    }

    func resetUserData() {
        engine.resetUserData()
        loadSettings()
        reloadContent()
    }

    func optimizeVideos() {
        engine.generateStaticWallpapers(forFolder: folderPath) {}
    }

    private func getDisplayName(for id: CGDirectDisplayID) -> String {
        for s in NSScreen.screens {
            if let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                n.uint32Value == id
            {
                return s.localizedName
            }
        }
        return "Display \(id)"
    }
}
