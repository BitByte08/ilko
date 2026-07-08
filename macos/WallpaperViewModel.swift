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
nonisolated final class ResumeOnce: @unchecked Sendable {
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

    /// 동일 thumbnailPath에 대한 중복 in-flight 생성을 막는 가드(MainActor 격리).
    private var inFlightThumbnails: Set<String> = []

    /// `engine`을 명시적으로 전달하는 것이 권장됩니다.
    /// ContentView의 @StateObject 생성자에서는 모듈 수준 sharedEngine을 사용합니다.
    init(engine: WallpaperEngine = sharedEngine ?? WallpaperEngine.shared()) {
        self.engine = engine
        loadSettings()
        self.engine.setupNotifications()
        // 크래시 등으로 남은 임시 머티리얼라이즈 파일을 앱 시작 시 정리한다.
        CloudFile.cleanupTempDir()
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

        // 1) 화질 배지 로딩을 기다리지 않고 목록을 즉시 구성한다.
        //    썸네일은 폴더 전체를 eager 생성하지 않고, 타일이 실제로 보일 때
        //    ensureThumbnail(for:)로 레이지 생성한다(클라우드 폴더 stall 방지).
        let items: [VideoItem] = videoFiles.map { f in
            let full = (folderSnapshot as NSString).appendingPathComponent(f)
            let base = (f as NSString).deletingPathExtension
            let thumbPath =
                (engine.thumbnailCachePath() as NSString?)?.appendingPathComponent("\(base).png") ?? ""
            return VideoItem(filename: f, path: full, thumbnailPath: thumbPath, quality: nil)
        }
        self.videos = items

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

    /// 타일이 화면에 보일 때 해당 영상 1개의 썸네일을 레이지 생성한다(MainActor).
    /// 이미 로컬 PNG가 있으면 즉시 반환. 클라우드/dataless 소스는 임시 로컬로 머티리얼라이즈해
    /// 그 임시 경로를 readPath로 사용하고, 추출 후 임시본을 삭제한다(영구 로컬 저장은 PNG뿐).
    func ensureThumbnail(for video: VideoItem) {
        guard video.loadThumbnail() == nil else { return }
        let thumbPath = video.thumbnailPath
        guard !thumbPath.isEmpty else { return }
        // 동일 thumbnailPath에 대한 중복 생성 방지.
        guard !inFlightThumbnails.contains(thumbPath) else { return }
        inFlightThumbnails.insert(thumbPath)

        let engine = self.engine
        let sourcePath = video.path

        Task { [weak self] in
            let sourceURL = URL(fileURLWithPath: sourcePath)
            var readPath = sourcePath
            var tempURL: URL?

            if CloudFile.needsMaterialization(sourceURL) {
                if let temp = await CloudFile.materializeToTemp(sourceURL, timeout: 120) {
                    tempURL = temp
                    readPath = temp.path
                } else {
                    // 머티리얼라이즈 실패/타임아웃: placeholder를 남기지 않고 종료(재시도 가능).
                    NSLog("ensureThumbnail: materialize failed for \(sourcePath)")
                    await self?.finishThumbnail(thumbPath)
                    return
                }
            }

            // ObjC 파일 단위 생성 API를 async로 브릿지한다.
            let ok = await WallpaperViewModel.generateThumbnail(
                engine: engine, readPath: readPath, thumbnailFilePath: thumbPath)
            if !ok {
                NSLog("ensureThumbnail: generation failed for \(sourcePath)")
            }

            // 임시본 삭제 — 영구 로컬 저장은 PNG뿐.
            if let tempURL { try? FileManager.default.removeItem(at: tempURL) }

            await self?.finishThumbnail(thumbPath)
        }
    }

    private func finishThumbnail(_ thumbPath: String) {
        inFlightThumbnails.remove(thumbPath)
    }

    /// generateThumbnailForVideoPath(ObjC 콜백)를 async로 감싼다.
    /// 엔진 계약상 completion은 메인 큐에서 정확히 한 번 호출되지만, ResumeOnce로 방어한다.
    nonisolated private static func generateThumbnail(
        engine: WallpaperEngine, readPath: String, thumbnailFilePath: String
    ) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let guardOnce = ResumeOnce()
            engine.generateThumbnail(
                forVideoPath: readPath, thumbnailFilePath: thumbnailFilePath
            ) { ok in
                if guardOnce.claim() { cont.resume(returning: ok) }
            }
        }
    }

    /// 썸네일 생성 실패(무한 스피너) 타일의 재시도 진입점.
    /// 지정 경로의 인메모리 캐시 + 디스크 PNG(실패/placeholder 포함)를 삭제한 뒤
    /// 해당 영상에 대해 레이지 재생성을 재요청한다.
    func regenerateThumbnails(for path: String? = nil) {
        guard let path else { return }
        ThumbnailCache.shared.forceRefresh(path: path)
        if let video = videos.first(where: { $0.thumbnailPath == path }) {
            ensureThumbnail(for: video)
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
