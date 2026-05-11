import Foundation

enum LaunchAgentManager {
    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.jitouch.Jitouch.plist")
    }

    static func unload() {
        runLaunchctl(arguments: ["unload", plistURL.path])
    }

    private static func runLaunchctl(arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("Jitouch: launchctl \(arguments.joined(separator: " ")) failed: \(error.localizedDescription)")
        }
    }
}
