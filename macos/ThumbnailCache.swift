import AppKit
import Combine

// MARK: - Thumbnail Cache
class ThumbnailCache: ObservableObject {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()
    @Published var lastUpdate = Date()

    private init() {
        cache.countLimit = 100

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thumbnailSaved(_:)),
            name: NSNotification.Name("ThumbnailSaved"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thumbnailsGenerated),
            name: NSNotification.Name("ThumbnailsGenerated"),
            object: nil
        )
    }

    @objc private func thumbnailSaved(_ notification: Notification) {
        if let path = notification.userInfo?["path"] as? String {
            cache.removeObject(forKey: path as NSString)
        }
        DispatchQueue.main.async {
            self.lastUpdate = Date()
        }
    }

    @objc private func thumbnailsGenerated() {
        cache.removeAllObjects()
        DispatchQueue.main.async {
            self.lastUpdate = Date()
        }
    }

    func image(for path: String) -> NSImage? {
        if let cached = cache.object(forKey: path as NSString) {
            return cached
        }

        guard FileManager.default.fileExists(atPath: path),
            let img = NSImage(contentsOfFile: path)
        else {
            return nil
        }

        cache.setObject(img, forKey: path as NSString)
        return img
    }

    func clearCache() {
        cache.removeAllObjects()
        lastUpdate = Date()
    }

    /// 재시도 지원: 인메모리 캐시 + 디스크 PNG(실패/placeholder 포함)를 함께 제거해
    /// 재생성이 skip되지 않게 한 뒤 UI 재조회(lastUpdate)를 트리거한다.
    func forceRefresh(path: String) {
        cache.removeObject(forKey: path as NSString)
        try? FileManager.default.removeItem(atPath: path)
        lastUpdate = Date()
    }
}
