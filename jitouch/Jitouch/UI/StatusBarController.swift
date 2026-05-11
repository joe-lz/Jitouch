import AppKit

protocol StatusBarControllerDelegate: AnyObject {
    func statusBarControllerDidToggleEnabled(_ controller: StatusBarController)
    func statusBarControllerDidOpenPreferences(_ controller: StatusBarController)
    func statusBarControllerDidQuit(_ controller: StatusBarController)
}

final class StatusBarController: NSObject {
    weak var delegate: StatusBarControllerDelegate?

    private let settingsStore: SettingsStore
    private var item: NSStatusItem?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func reload() {
        guard settingsStore.settings.showsMenuBarIcon else {
            if let item {
                NSStatusBar.system.removeStatusItem(item)
                self.item = nil
            }
            return
        }

        if item == nil {
            item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }

        item?.button?.image = NSImage(named: settingsStore.settings.isEnabled ? "logosmall" : "logosmalloff")
        item?.button?.image?.isTemplate = true
        item?.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Jitouch")
        let toggleTitle = settingsStore.settings.isEnabled ? "Turn Jitouch Off" : "Turn Jitouch On"
        menu.addItem(NSMenuItem(title: toggleTitle, action: #selector(toggleEnabled), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Preferences...", action: #selector(openPreferences), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Jitouch", action: #selector(quit), keyEquivalent: ""))

        for item in menu.items {
            item.target = self
        }
        return menu
    }

    @objc private func toggleEnabled() {
        delegate?.statusBarControllerDidToggleEnabled(self)
    }

    @objc private func openPreferences() {
        delegate?.statusBarControllerDidOpenPreferences(self)
    }

    @objc private func quit() {
        delegate?.statusBarControllerDidQuit(self)
    }
}
