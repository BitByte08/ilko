import Combine
import Foundation
import SystemConfiguration

/// SCDynamicStore로 네트워크 변경 이벤트를 실시간 감지하고, 게이트웨이 MAC이 바뀌면 currentGatewayMAC을 publish한다.
@MainActor
class LocationWatcher: ObservableObject {
    @Published private(set) var currentGatewayMAC: String?
    private var store: SCDynamicStore?
    private var storeSource: CFRunLoopSource?

    func start() {
        setupDynamicStore()
        pollNetwork()  // 즉시 1회 체크
    }

    func stop() {
        if let source = storeSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        storeSource = nil
        store = nil
    }

    /// 현재 게이트웨이 MAC을 즉시 반환한다 (UI 자동 채우기용).
    func currentNetworkID() -> String? {
        fetchGatewayMAC()
    }

    private func setupDynamicStore() {
        var ctx = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        guard let store = SCDynamicStoreCreate(
            nil,
            "ilko.LocationWatcher" as CFString,
            { _, _, info in
                guard let info else { return }
                let watcher = Unmanaged<LocationWatcher>.fromOpaque(info).takeUnretainedValue()
                Task { @MainActor in watcher.pollNetwork() }
            },
            &ctx
        ) else {
            print("[LocationWatcher] ❌ SCDynamicStore 생성 실패")
            return
        }

        // en0의 IPv4 설정(게이트웨이 포함)이 바뀔 때 알림
        let keys = ["State:/Network/Interface/en0/IPv4"] as CFArray
        SCDynamicStoreSetNotificationKeys(store, keys, nil)

        let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0)!
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        self.store = store
        self.storeSource = source
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
