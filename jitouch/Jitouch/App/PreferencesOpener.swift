import AppKit

enum PreferencesOpener {
    static func openPreferences() {
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/PreferencePanes/Jitouch.prefPane"),
            URL(fileURLWithPath: "/Library/PreferencePanes/Jitouch.prefPane")
        ]

        if let paneURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            NSWorkspace.shared.open(paneURL)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Can't find the Jitouch preference pane."
        alert.informativeText = "Please reinstall Jitouch."
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
