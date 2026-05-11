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
        settingsStore.load()
        applyInterfaceSettings()
        statusBarController.delegate = self
        statusBarController.reload()
        requestAccessibilityTrustIfNeeded()
        gestureController.start()
        observeSettingsChanges()
        observeWake()
        preferencesWindowController.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
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

    private func requestAccessibilityTrustIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func applyInterfaceSettings() {
        AppLocalization.currentLanguage = settingsStore.settings.appLanguage
        NSApp.appearance = settingsStore.settings.themeMode.nsAppearance
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
        LaunchAgentManager.unload()
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
