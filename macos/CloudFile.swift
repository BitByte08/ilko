import Foundation

/// 클라우드/온라인 전용(dataless) 파일 감지 및 임시 로컬 머티리얼라이즈 유틸.
///
/// Google Drive(File Provider) 등 가상 파일시스템의 영상은 "온라인 전용"일 수 있어
/// AVAsset이 직접 읽으면 다운로드 대기에서 멈춘다. 여기서는 파일을 감지하고,
/// 필요 시 NSFileCoordinator coordinated read로 강제 다운로드해 임시 로컬 파일로 복사한다.
/// 임시본은 썸네일 추출 후 호출부가 삭제한다(영구 로컬 저장은 PNG뿐).
///
/// 이 툴체인은 Xcode 26 기본 MainActor 격리를 사용하므로, 백그라운드에서 도는
/// 블로킹 작업은 반드시 `nonisolated`로 선언해 메인 액터에 묶이지 않게 한다.
nonisolated enum CloudFile {

    /// 임시 머티리얼라이즈 소스 파일을 모아두는 전용 디렉터리.
    private static var tempDirURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ilko-thumb-src", isDirectory: true)
    }

    /// 온라인 전용(미다운로드) 또는 File Provider(클라우드) 항목인지 판별한다.
    /// ubiquitous & 다운로드 상태가 .current가 아니면 true, 혹은 경로가 CloudStorage면 true.
    static func needsMaterialization(_ url: URL) -> Bool {
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
        ]
        if let v = try? url.resourceValues(forKeys: keys) {
            if v.isUbiquitousItem == true {
                if let s = v.ubiquitousItemDownloadingStatus { return s != .current }
                return true
            }
        }
        return url.path.contains("/Library/CloudStorage/")
    }

    /// NSFileCoordinator coordinated read로 파일을 로컬화한 뒤 임시 파일로 복사한다.
    /// 반환: 임시 URL(성공) 또는 nil(실패/타임아웃). 블로킹 읽기는 메인 액터 밖에서 수행하고,
    /// `timeout`(넉넉히, 예: 120s)을 넘기면 nil로 resume해 멈춘 다운로드가 영원히 대기하지 않게 한다.
    static func materializeToTemp(_ url: URL, timeout: TimeInterval) async -> URL? {
        await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            let guardOnce = ResumeOnce()

            // 블로킹 coordinated read를 백그라운드 큐에서 실행한다.
            DispatchQueue.global(qos: .utility).async {
                let result = coordinatedCopyToTemp(url)
                if guardOnce.claim() { cont.resume(returning: result) }
            }

            // 타임아웃 레이스: 스턱된 다운로드가 무한 대기하지 않도록.
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if guardOnce.claim() { cont.resume(returning: nil) }
            }
        }
    }

    /// coordinated read 스코프 안에서 파일을 임시 디렉터리로 복사한다(블로킹).
    private static func coordinatedCopyToTemp(_ url: URL) -> URL? {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: tempDirURL, withIntermediateDirectories: true)
        } catch {
            NSLog("CloudFile: failed to create temp dir: \(error)")
            return nil
        }

        let ext = url.pathExtension
        var destURL = tempDirURL.appendingPathComponent(UUID().uuidString)
        if !ext.isEmpty { destURL.appendPathExtension(ext) }

        var copyError: Error?
        var coordError: NSError?
        let coordinator = NSFileCoordinator()
        // reading으로 접근하면 File Provider가 파일을 로컬로 머티리얼라이즈한다.
        coordinator.coordinate(
            readingItemAt: url, options: [], error: &coordError
        ) { (readURL: URL) in
            do {
                if fm.fileExists(atPath: destURL.path) {
                    try fm.removeItem(at: destURL)
                }
                try fm.copyItem(at: readURL, to: destURL)
            } catch {
                copyError = error
            }
        }

        if let coordError {
            NSLog("CloudFile: coordinated read failed for \(url.path): \(coordError)")
            return nil
        }
        if let copyError {
            NSLog("CloudFile: copy to temp failed for \(url.path): \(copyError)")
            try? fm.removeItem(at: destURL)
            return nil
        }
        return destURL
    }

    /// 임시 디렉터리 전체를 삭제한다(앱 시작 시 호출해 크래시로 남은 임시본 정리).
    static func cleanupTempDir() {
        try? FileManager.default.removeItem(at: tempDirURL)
    }
}
