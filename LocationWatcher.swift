import Combine
import CoreWLAN
import Foundation
import SystemConfiguration

/// SCDynamicStore로 기본 라우트 변경 이벤트를 감지하고, 게이트웨이 MAC이 바뀌면 currentGatewayMAC을 publish한다.
@MainActor
class LocationWatcher: ObservableObject {
    @Published private(set) var currentGatewayMAC: String?
    private var store: SCDynamicStore?
    private var storeSource: CFRunLoopSource?
    private var pendingCheck: Task<Void, Never>?
    private var firstCheckDone = false

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

        // 기본 라우트 변경 + en0 링크 끊김 모두 감지
        let keys = [
            "State:/Network/Global/IPv4",       // Wi-Fi 전환 / 기본 라우트 변경
            "State:/Network/Interface/en0/Link" // en0 연결/해제 (Wi-Fi 완전 단절)
        ] as CFArray
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

    // @MainActor에서 호출됨 — 논블로킹 SSID만 여기서, 나머지 블로킹 작업은 백그라운드
    private func checkNetwork() {
        // 메인 액터에서 non-blocking SSID만 읽기
        let ssid = CWWiFiClient.shared().interface(withName: "en0")?.ssid()

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            var networkID: String? = nil

            // ipconfig getoption en0 router (블로킹 서브프로세스 → 백그라운드에서)
            if let ip = self.fetchGatewayIPFromStore() {
                networkID = self.fetchGatewayMAC(gatewayIP: ip)
            }

            // CoreWLAN (Location 권한 있으면 즉시 반환)
            if networkID == nil, let ssid {
                print("[LocationWatcher] ARP 실패, CoreWLAN SSID 사용: \(ssid)")
                networkID = ssid
            }

            // networksetup 서브프로세스 (권한 불필요, 최후 수단)
            if networkID == nil, let ssid = Self.fetchSSIDViaProcess() {
                print("[LocationWatcher] ARP 실패, networksetup SSID 사용: \(ssid)")
                networkID = ssid
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                if !self.firstCheckDone {
                    self.firstCheckDone = true
                    print("[LocationWatcher] 초기 네트워크 ID: \(networkID ?? "nil")")
                    self.currentGatewayMAC = networkID
                } else if networkID != self.currentGatewayMAC {
                    print("[LocationWatcher] 네트워크 변경: \(self.currentGatewayMAC ?? "nil") → \(networkID ?? "nil")")
                    self.currentGatewayMAC = networkID
                } else {
                    print("[LocationWatcher] 네트워크 동일: \(networkID ?? "nil")")
                }
            }
        }
    }

    /// en0의 DHCP 라우터 IP를 읽는다.
    /// SCDynamicStore의 PrimaryService 대신 en0를 직접 지정 — VPN 활성 시에도 실제 Wi-Fi 게이트웨이를 반환.
    private nonisolated func fetchGatewayIPFromStore() -> String? {
        let task = Process()
        task.launchPath = "/usr/sbin/ipconfig"
        task.arguments = ["getoption", "en0", "router"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return nil }
        task.waitUntilExit()
        let ip = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !ip.isEmpty else {
            print("[LocationWatcher] ❌ en0 라우터 IP 없음")
            return nil
        }
        print("[LocationWatcher] 게이트웨이 IP: \(ip)")
        return ip
    }

    /// networksetup으로 현재 Wi-Fi SSID를 읽는다 (Location 권한 불필요).
    private static nonisolated func fetchSSIDViaProcess() -> String? {
        let task = Process()
        task.launchPath = "/usr/sbin/networksetup"
        task.arguments = ["-getairportnetwork", "en0"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do { try task.run() } catch { return nil }
        task.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // "Current Wi-Fi Network: SSID_NAME"
        let prefix = "Current Wi-Fi Network: "
        guard output.hasPrefix(prefix) else { return nil }
        let ssid = String(output.dropFirst(prefix.count))
        return ssid.isEmpty ? nil : ssid
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

        // "no entry" or "(incomplete)" → 미등록/알 수 없는 네트워크, 에러 아님
        if output.contains("no entry") || output.contains("(incomplete)") {
            print("[LocationWatcher] 알 수 없는 네트워크 → nil")
            return nil
        }

        // "? (192.168.0.1) at a4:b1:c2:d3:e4:f5 on en0 ..."
        let parts = output.components(separatedBy: " at ")
        guard parts.count >= 2 else {
            print("[LocationWatcher] ❌ arp 파싱 실패: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            return nil
        }
        let mac = parts[1].components(separatedBy: " ").first ?? ""
        let result = mac.isEmpty ? nil : mac
        print("[LocationWatcher] MAC: \(result ?? "nil")")
        return result
    }
}
