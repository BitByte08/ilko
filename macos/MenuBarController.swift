import AppKit
import Combine

/// 메뉴바 아이콘, 현재 프로필 표시, 수동 전환을 담당한다.
@MainActor
class MenuBarController {
    private let statusItem: NSStatusItem
    private let profileManager: ProfileManager
    private let switchController: SwitchController
    private let engine: WallpaperEngine
    private let showWindowCallback: () -> Void
    private var cancellables = Set<AnyCancellable>()

    init(
        profileManager: ProfileManager,
        switchController: SwitchController,
        engine: WallpaperEngine,
        showWindow: @escaping () -> Void
    ) {
        self.profileManager = profileManager
        self.switchController = switchController
        self.engine = engine
        self.showWindowCallback = showWindow
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "play.desktopcomputer",
                accessibilityDescription: "ILKO"
            )
        }

        rebuildMenu()

        // 프로필 목록 또는 활성 프로필 변경 시 메뉴 갱신
        profileManager.$profiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)

        switchController.$activeProfile
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        // 현재 활성 프로필명 (비활성 헤더)
        let header = NSMenuItem(
            title: switchController.activeProfile?.name ?? "프로필 없음",
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // 프로필 목록 — 클릭 시 수동 전환
        for profile in profileManager.profiles {
            let item = NSMenuItem(
                title: profile.name,
                action: #selector(selectProfile(_:)),
                keyEquivalent: ""
            )
            item.representedObject = profile.id.uuidString
            item.target = self
            item.state = (profile.id == switchController.activeProfile?.id) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "프로필 설정...",
            action: #selector(showSettingsWindow),
            keyEquivalent: "s"
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(
            title: "종료",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard
            let idStr = sender.representedObject as? String,
            let id = UUID(uuidString: idStr),
            let profile = profileManager.profiles.first(where: { $0.id == id })
        else { return }
        switchController.apply(profile)
    }

    @objc private func showSettingsWindow() {
        showWindowCallback()
    }

    @objc private func quitApp() {
        engine.terminateApplication()
        NSApp.terminate(nil)
    }
}
