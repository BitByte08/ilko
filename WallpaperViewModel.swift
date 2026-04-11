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

        // @MainActor 격리 값을 detached task 진입 전에 스냅샷
        let folderSnapshot = folderPath
        let engine = self.engine

        // 진행 중인 이전 리로드 취소 후 새로 시작
        reloadTask?.cancel()
        reloadTask = Task.detached(priority: .userInitiated) { [weak self] in
            var newVideos: [VideoItem] = []
            for f in videoFiles {
                guard !Task.isCancelled else { return }
                let full = (folderSnapshot as NSString).appendingPathComponent(f)
                let base = (f as NSString).deletingPathExtension
                let thumbPath =
                    (engine.thumbnailCachePath() as NSString?)?.appendingPathComponent(
                        "\(base).png") ?? ""
                // ObjC 콜백 → async/await 변환: continuation만 캡처하므로 Sendable 안전
                let badge: String? = await withCheckedContinuation { continuation in
                    engine.videoQualityBadge(for: URL(fileURLWithPath: full)) { badge in
                        continuation.resume(returning: badge)
                    }
                }
                newVideos.append(VideoItem(filename: f, path: full, thumbnailPath: thumbPath, quality: badge))
            }

            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.videos = newVideos
                let missingThumbnails = newVideos.filter { $0.loadThumbnail() == nil }
                if !missingThumbnails.isEmpty {
                    NSLog(
                        "Found \(missingThumbnails.count) videos without thumbnails, generating..."
                    )
                    self.engine.generateThumbnails()
                }
            }
        }
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
