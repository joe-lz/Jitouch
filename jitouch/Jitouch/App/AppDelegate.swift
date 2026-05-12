import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private lazy var commandDispatcher = CommandDispatcher(settingsStore: settingsStore)
    private lazy var gestureController = GestureController(settingsStore: settingsStore, commandDispatcher: commandDispatcher)
    private lazy var statusBarController = StatusBarController(settingsStore: settingsStore)
    private lazy var preferencesWindowController: PreferencesWindowController = {
        let controller = PreferencesWindowController(settingsStore: settingsStore)
        controller.delegate = self
        return controller
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        settingsStore.onExternalSettingsChanged = { [weak self] in
            self?.settingsStoreDidReceiveExternalSettings()
        }
        settingsStore.load()
        applyInterfaceSettings()
        installMainMenu()
        statusBarController.delegate = self
        statusBarController.reload()
        requestAccessibilityTrustIfNeeded()
        gestureController.start()
        observeSettingsChanges()
        observeWake()
        preferencesWindowController.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        LaunchAgentManager.unload()
        gestureController.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        preferencesWindowController.show()
        return true
    }

    private func observeSettingsChanges() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(settingsUpdated(_:)),
            name: .jitouchPreferencesDidChange,
            object: NotificationObject.preferences
        )
    }

    private func observeWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func settingsUpdated(_ notification: Notification) {
        settingsStore.load(from: notification.userInfo)
        applyInterfaceSettings()
        statusBarController.reload()
        gestureController.reload()
    }

    @objc private func systemDidWake() {
        gestureController.reload()
    }

    private func settingsStoreDidReceiveExternalSettings() {
        applyInterfaceSettings()
        statusBarController.reload()
        gestureController.reload()
        preferencesWindowController.reload()
    }

    private func requestAccessibilityTrustIfNeeded() {
        let trustedBeforePrompt = AXIsProcessTrusted()
        NSLog("Jitouch: accessibility trusted before prompt: \(trustedBeforePrompt)")
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        let trustedAfterPrompt = AXIsProcessTrustedWithOptions(options)
        NSLog("Jitouch: accessibility trusted after prompt: \(trustedAfterPrompt)")
    }

    private func applyInterfaceSettings() {
        AppLocalization.currentLanguage = settingsStore.settings.appLanguage
        NSApp.appearance = settingsStore.settings.themeMode.nsAppearance
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(
            NSMenuItem(
                title: String(format: L("Quit %@"), ProcessInfo.processInfo.processName),
                action: #selector(quitApplication),
                keyEquivalent: "q"
            )
        )
        appMenu.items.last?.target = self

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)

        let fileMenu = NSMenu(title: L("File"))
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(
            NSMenuItem(
                title: L("Close Window"),
                action: #selector(NSWindow.performClose(_:)),
                keyEquivalent: "w"
            )
        )

        NSApp.mainMenu = mainMenu
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: StatusBarControllerDelegate {
    func statusBarControllerDidToggleEnabled(_ controller: StatusBarController) {
        settingsStore.settings.isEnabled.toggle()
        settingsStore.saveRuntimeToggle()
        settingsStore.postRuntimeSettingsChanged()
        statusBarController.reload()

        if settingsStore.settings.isEnabled {
            gestureController.reload()
        } else {
            gestureController.stopRecognitionState()
        }
    }

    func statusBarControllerDidOpenPreferences(_ controller: StatusBarController) {
        preferencesWindowController.show()
    }

    func statusBarControllerDidQuit(_ controller: StatusBarController) {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: PreferencesWindowControllerDelegate {
    func preferencesWindowControllerDidChangeSettings(_ controller: PreferencesWindowController) {
        applyInterfaceSettings()
        statusBarController.reload()
        gestureController.reload()
    }
}
