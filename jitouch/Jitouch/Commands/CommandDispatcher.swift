import AppKit
import ApplicationServices

final class CommandDispatcher {
    private let settingsStore: SettingsStore
    private let windowService = AccessibilityWindowService()

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func dispatch(_ gesture: String, device: GestureDevice) {
        DispatchQueue.global(qos: .userInteractive).async {
            let application = device == .characterRecognition ? NSWorkspace.shared.frontmostApplication?.localizedName : self.windowService.applicationUnderPointer()
            guard let command = self.settingsStore.command(for: gesture, device: device, application: application) else {
                NSLog("Jitouch: no enabled command for \(device.rawValue) gesture \(gesture), application \(application ?? "unknown")")
                return
            }
            NSLog("Jitouch: dispatch \(device.rawValue) gesture \(gesture) -> \(command.command), application \(application ?? "unknown")")
            self.execute(command, device: device, application: application)
        }
    }

    func hasEnabledCommand(for gesture: String, device: GestureDevice) -> Bool {
        let application = device == .characterRecognition ? NSWorkspace.shared.frontmostApplication?.localizedName : windowService.applicationUnderPointer()
        return settingsStore.command(for: gesture, device: device, application: application) != nil
    }

    private func execute(_ command: GestureCommand, device: GestureDevice, application: String?) {
        if !command.isAction {
            KeySimulator.press(keyCode: CGKeyCode(command.keyCode), modifiers: CGEventFlags(rawValue: command.modifierFlags))
            return
        }

        switch command.command {
        case "-":
            return
        case "Next Tab":
            KeySimulator.press("Tab", modifiers: [.maskControl])
        case "Previous Tab":
            KeySimulator.press("Tab", modifiers: [.maskControl, .maskShift])
        case "Close / Close Tab":
            activateWindowIfNeeded(device)
            KeySimulator.press("W", modifiers: [.maskCommand])
        case "Quit":
            activateWindowIfNeeded(device)
            KeySimulator.press("Q", modifiers: [.maskCommand])
        case "Hide":
            activateWindowIfNeeded(device)
            KeySimulator.press("H", modifiers: [.maskCommand])
        case "Minimize":
            activateWindowIfNeeded(device)
            windowService.minimizeFocusedWindow()
        case "Zoom":
            activateWindowIfNeeded(device)
            windowService.zoomFocusedWindow()
        case "Maximize":
            windowService.tileFocusedWindow(.full)
        case "Maximize Left":
            windowService.tileFocusedWindow(.left)
        case "Maximize Right":
            windowService.tileFocusedWindow(.right)
        case "Un-Maximize":
            windowService.tileFocusedWindow(.restore)
        case "Copy":
            KeySimulator.press("C", modifiers: [.maskCommand])
        case "Paste":
            KeySimulator.press("V", modifiers: [.maskCommand])
        case "New":
            KeySimulator.press("N", modifiers: [.maskCommand])
        case "New Tab":
            KeySimulator.press("T", modifiers: [.maskCommand])
        case "Open":
            KeySimulator.press("O", modifiers: [.maskCommand])
        case "Save":
            KeySimulator.press("S", modifiers: [.maskCommand])
        case "Refresh":
            activateWindowIfNeeded(device)
            KeySimulator.press("R", modifiers: [.maskCommand])
        case "Full Screen":
            activateWindowIfNeeded(device)
            KeySimulator.press("F", modifiers: [.maskControl, .maskCommand])
        case "Open Recently Closed Tab":
            KeySimulator.press("T", modifiers: [.maskShift, .maskCommand])
        case "Middle Click":
            KeySimulator.click(button: .center, typeDown: .otherMouseDown, typeUp: .otherMouseUp)
        case "Left Click":
            KeySimulator.click(button: .left, typeDown: .leftMouseDown, typeUp: .leftMouseUp)
        case "Right Click":
            KeySimulator.click(button: .right, typeDown: .rightMouseDown, typeUp: .rightMouseUp)
        case "Launch Finder":
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"), configuration: NSWorkspace.OpenConfiguration())
        case "Launch Browser":
            openDefaultBrowser()
        case "Show Desktop":
            KeySimulator.press("F", modifiers: [.maskCommand])
        case "Mission Control":
            KeySimulator.press("Up", modifiers: [.maskControl])
        case "Application Windows":
            KeySimulator.press("Down", modifiers: [.maskControl])
        case "Launchpad":
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Launchpad.app"))
        case "Scroll to Top":
            KeySimulator.press("Home")
        case "Scroll to Bottom":
            KeySimulator.press("End")
        case "Play / Pause":
            KeySimulator.mediaKey(NX_KEYTYPE_PLAY)
        case "Next":
            KeySimulator.mediaKey(NX_KEYTYPE_NEXT)
        case "Previous":
            KeySimulator.mediaKey(NX_KEYTYPE_PREVIOUS)
        case "Volume Up":
            KeySimulator.mediaKey(NX_KEYTYPE_SOUND_UP)
        case "Volume Down":
            KeySimulator.mediaKey(NX_KEYTYPE_SOUND_DOWN)
        case "Brightness Up":
            KeySimulator.mediaKey(NX_KEYTYPE_BRIGHTNESS_UP)
        case "Brightness Down":
            KeySimulator.mediaKey(NX_KEYTYPE_BRIGHTNESS_DOWN)
        default:
            openCustomTarget(command)
        }
    }

    private func activateWindowIfNeeded(_ device: GestureDevice) {
        if device != .characterRecognition {
            _ = windowService.activateWindowUnderPointer()
        }
    }

    private func openDefaultBrowser() {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://www.apple.com")!) else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Safari.app"))
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func openCustomTarget(_ command: GestureCommand) {
        if let path = command.openFilePath {
            NSWorkspace.shared.open(URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        } else if let urlString = command.openURL, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
