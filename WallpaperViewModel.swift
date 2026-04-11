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

// MARK: - Wallpaper View Model
@MainActor
class WallpaperViewModel: ObservableObject {

    @Published var videos: [VideoItem] = []
    @Published var folderPath: String = ""
    @Published var scaleMode: String = "fill"
    @Published var randomOnStartup: Bool = false
    @Published var pauseOnAppFocus: Bool = true
    @Published var volume: Double = 50.0
    @Published var vinttageBar: Bool = true

    private var currentReloadID = UUID()
    private let reloadIDLock = NSLock()
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

        let reloadID = UUID()
        reloadIDLock.lock()
        currentReloadID = reloadID
        reloadIDLock.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let newVideos: [VideoItem] = videoFiles.map { f in
                let full = (self.folderPath as NSString).appendingPathComponent(f)
                let base = (f as NSString).deletingPathExtension
                let thumbPath =
                    (self.engine.thumbnailCachePath() as NSString?)?.appendingPathComponent(
                        "\(base).png") ?? ""

                var item = VideoItem(filename: f, path: full, thumbnailPath: thumbPath)
                self.engine.videoQualityBadge(for: URL(fileURLWithPath: full)) { badge in
                    item.quality = badge
                }
                return item
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                self.reloadIDLock.lock()
                let isValid = reloadID == self.currentReloadID
                self.reloadIDLock.unlock()

                if isValid {
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
