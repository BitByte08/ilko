import Combine
import Foundation

/// 30초 폴링으로 게이트웨이 MAC을 감지하고, 변경 시 currentGatewayMAC을 publish한다.
@MainActor
class LocationWatcher: ObservableObject {
    @Published private(set) var currentGatewayMAC: String?
    private var timer: Timer?

    func start() {
        pollNetwork()  // 즉시 1회 체크
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollNetwork() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 현재 게이트웨이 MAC을 즉시 반환한다 (UI 자동 채우기용).
    func currentNetworkID() -> String? {
        fetchGatewayMAC()
    }

    private func pollNetwork() {
        let mac = fetchGatewayMAC()
        if mac != currentGatewayMAC {
            currentGatewayMAC = mac
        }
    }

    /// 기본 게이트웨이의 MAC 주소를 반환한다. 권한 불필요.
    private func fetchGatewayMAC() -> String? {
        guard let gatewayIP = fetchGatewayIP() else {
            print("[LocationWatcher] ❌ 게이트웨이 IP를 찾을 수 없음")
            return nil
        }
        print("[LocationWatcher] 게이트웨이 IP: \(gatewayIP)")

        let task = Process()
        task.launchPath = "/usr/sbin/arp"
        task.arguments = ["-n", gatewayIP]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do { try task.run() } catch {
            print("[LocationWatcher] ❌ arp 실행 실패: \(error)")
            return nil
        }
        task.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        print("[LocationWatcher] arp 출력: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")

        // "? (192.168.0.1) at a4:b1:c2:d3:e4:f5 on en0 ..."
        let parts = output.components(separatedBy: " at ")
        guard parts.count >= 2 else {
            print("[LocationWatcher] ❌ arp 파싱 실패")
            return nil
        }
        let mac = parts[1].components(separatedBy: " ").first ?? ""
        let result = mac.isEmpty || mac == "(incomplete)" ? nil : mac
        print("[LocationWatcher] MAC: \(result ?? "nil")")
        return result
    }

    private func fetchGatewayIP() -> String? {
        // VPN 환경에서도 동작하도록 en0(Wi-Fi)의 DHCP 라우터 IP를 직접 읽는다
        let task = Process()
        task.launchPath = "/usr/sbin/ipconfig"
        task.arguments = ["getoption", "en0", "router"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do { try task.run() } catch {
            print("[LocationWatcher] ❌ ipconfig 실행 실패: \(error)")
            return nil
        }
        task.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        print("[LocationWatcher] ipconfig router: \(output)")
        return output.isEmpty ? nil : output
    }
}
