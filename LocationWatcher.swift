import Combine
import Foundation
import SystemConfiguration

/// SCDynamicStore로 기본 라우트 변경 이벤트를 감지하고, 게이트웨이 MAC이 바뀌면 currentGatewayMAC을 publish한다.
@MainActor
class LocationWatcher: ObservableObject {
    @Published private(set) var currentGatewayMAC: String?
    private var store: SCDynamicStore?
    private var storeSource: CFRunLoopSource?
    private var pendingCheck: Task<Void, Never>?

    func start() {
        setupDynamicStore()
        scheduleCheck()  // 1.5초 후 체크 (ARP 캐시 안정화 대기)
    }

    func stop() {
        pendingCheck?.cancel()
        pendingCheck = nil
        if let source = storeSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        storeSource = nil
        store = nil
    }

    /// 현재 게이트웨이 MAC을 즉시 반환한다 (UI 자동 채우기용).
    func currentNetworkID() -> String? {
        guard let ip = fetchGatewayIPFromStore() else { return nil }
        return fetchGatewayMAC(gatewayIP: ip)
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
                Task { @MainActor in watcher.scheduleCheck() }
            },
            &ctx
        ) else {
            print("[LocationWatcher] ❌ SCDynamicStore 생성 실패")
            return
        }

        // 기본 라우트가 바뀔 때만 알림 (Wi-Fi 전환 = 기본 라우트 변경)
        let keys = ["State:/Network/Global/IPv4"] as CFArray
        SCDynamicStoreSetNotificationKeys(store, keys, nil)

        let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0)!
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        self.store = store
        self.storeSource = source
    }

    /// 이벤트가 연속으로 발생할 때 마지막 이벤트 후 1.5초 뒤에만 실제 체크한다.
    private func scheduleCheck() {
        pendingCheck?.cancel()
        pendingCheck = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
            self?.checkNetwork()
        }
    }

    private func checkNetwork() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            guard let ip = await self.fetchGatewayIPFromStore() else {
                await MainActor.run { [weak self] in
                    if self?.currentGatewayMAC != nil {
                        print("[LocationWatcher] 게이트웨이 없음 → nil")
                        self?.currentGatewayMAC = nil
                    }
                }
                return
            }
            let mac = self.fetchGatewayMAC(gatewayIP: ip)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if mac != self.currentGatewayMAC {
                    self.currentGatewayMAC = mac
                }
            }
        }
    }

    /// SCDynamicStore에서 기본 게이트웨이 IP를 직접 읽는다 (서브프로세스 불필요).
    private func fetchGatewayIPFromStore() -> String? {
        guard let store else { return nil }
        guard let globalInfo = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let primaryService = globalInfo["PrimaryService"] as? String else {
            print("[LocationWatcher] ❌ 기본 네트워크 서비스 없음")
            return nil
        }
        let serviceKey = "State:/Network/Service/\(primaryService)/IPv4" as CFString
        guard let serviceInfo = SCDynamicStoreCopyValue(store, serviceKey) as? [String: Any],
              let router = serviceInfo["Router"] as? String else {
            print("[LocationWatcher] ❌ 라우터 IP 없음")
            return nil
        }
        print("[LocationWatcher] 게이트웨이 IP: \(router)")
        return router
    }

    /// 게이트웨이 IP의 MAC 주소를 arp로 조회한다.
    private nonisolated func fetchGatewayMAC(gatewayIP: String) -> String? {
        // ARP 캐시가 비어있을 수 있으므로 ping으로 강제 채운다
        let ping = Process()
        ping.launchPath = "/sbin/ping"
        ping.arguments = ["-c", "1", "-W", "1000", gatewayIP]
        ping.standardOutput = Pipe()
        ping.standardError = Pipe()
        try? ping.run()
        ping.waitUntilExit()

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
}
