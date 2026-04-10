import Combine
import CoreWLAN
import Foundation

/// 30초 폴링으로 Wi-Fi SSID를 감지하고, 변경 시 currentSSID를 publish한다.
@MainActor
class LocationWatcher: ObservableObject {
    @Published private(set) var currentSSID: String?
    private var timer: Timer?

    func start() {
        pollSSID()  // 즉시 1회 체크
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollSSID() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 현재 연결된 Wi-Fi SSID를 즉시 반환한다 (UI에서 1클릭 등록용).
    func currentWiFiSSID() -> String? {
        CWWiFiClient.shared().interface()?.ssid()
    }

    private func pollSSID() {
        let ssid = CWWiFiClient.shared().interface()?.ssid()
        if ssid != currentSSID {
            currentSSID = ssid
        }
    }
}
