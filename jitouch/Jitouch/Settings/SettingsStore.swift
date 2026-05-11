import Foundation

final class SettingsStore {
    private enum Key {
        static let enabled = "enAll"
        static let clickSpeed = "ClickSpeed"
        static let sensitivity = "Sensitivity"
        static let showIcon = "ShowIcon"
        static let logLevel = "LogLevel"
        static let trackpadEnabled = "enTPAll"
        static let handed = "Handed"
        static let magicMouseEnabled = "enMMAll"
        static let magicMouseHanded = "MMHanded"
        static let trackpadCommands = "TrackpadCommands"
        static let magicMouseCommands = "MagicMouseCommands"
        static let recognitionCommands = "RecognitionCommands"
    }

    private let appID = "com.jitouch.Jitouch" as CFString
    private(set) var rawSettings: [String: Any] = [:]
    var settings = JitouchSettings()

    func load() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.jitouch.Jitouch.plist")

        guard
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [.mutableContainersAndLeaves], format: nil),
            let dictionary = plist as? [String: Any]
        else {
            rawSettings = DefaultsFactory.makeDefaultSettings()
            persistRawSettings()
            apply(rawSettings)
            return
        }

        rawSettings = dictionary
        apply(dictionary)
    }

    func load(from userInfo: [AnyHashable: Any]?) {
        guard let dictionary = userInfo as? [String: Any] else {
            load()
            return
        }
        rawSettings = dictionary
        apply(dictionary)
    }

    func saveRuntimeToggle() {
        rawSettings[Key.enabled] = settings.isEnabled ? 1 : 0
        let value = NSNumber(value: settings.isEnabled)
        CFPreferencesSetAppValue(Key.enabled as CFString, value, appID)
        CFPreferencesAppSynchronize(appID)
    }

    func postRuntimeSettingsChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            .jitouchRuntimeDidChange,
            object: NotificationObject.appToPreferencePane,
            userInfo: [Key.enabled: NSNumber(value: settings.isEnabled)],
            deliverImmediately: true
        )
    }

    func command(for gesture: String, device: GestureDevice, application: String?) -> GestureCommand? {
        let maps: [String: AppGestureCommands]
        switch device {
        case .trackpad:
            maps = settings.trackpadCommands
        case .magicMouse:
            maps = settings.magicMouseCommands
        case .characterRecognition:
            maps = settings.recognitionCommands
        }

        let applicationMap = application.flatMap { maps[$0] }
        if let command = applicationMap?.gestures[gesture], command.isEnabled {
            return command
        }

        if let fallback = applicationMap?.gestures["All Unassigned Gestures"], fallback.isEnabled {
            return fallback
        }

        let allApplications = maps["All Applications"]
        if let command = allApplications?.gestures[gesture], command.isEnabled {
            return command
        }

        return nil
    }

    private func apply(_ dictionary: [String: Any]) {
        settings.isEnabled = Self.bool(dictionary[Key.enabled], default: true)
        settings.showsMenuBarIcon = Self.bool(dictionary[Key.showIcon], default: true)
        settings.clickSpeed = Self.double(dictionary[Key.clickSpeed], default: 0.25)
        settings.sensitivity = Self.double(dictionary[Key.sensitivity], default: 4.6666)
        settings.logLevel = Int(Self.double(dictionary[Key.logLevel], default: 0))
        settings.trackpadEnabled = Self.bool(dictionary[Key.trackpadEnabled], default: true)
        settings.trackpadLeftHanded = Self.bool(dictionary[Key.handed], default: false)
        settings.magicMouseEnabled = Self.bool(dictionary[Key.magicMouseEnabled], default: true)
        settings.magicMouseLeftHanded = Self.bool(dictionary[Key.magicMouseHanded], default: false)
        settings.trackpadCommands = Self.commandMap(from: dictionary[Key.trackpadCommands])
        settings.magicMouseCommands = Self.commandMap(from: dictionary[Key.magicMouseCommands])
        settings.recognitionCommands = Self.commandMap(from: dictionary[Key.recognitionCommands])
    }

    private func persistRawSettings() {
        for (key, value) in rawSettings {
            CFPreferencesSetAppValue(key as CFString, value as CFPropertyList, appID)
        }
        CFPreferencesAppSynchronize(appID)
    }

    private static func commandMap(from value: Any?) -> [String: AppGestureCommands] {
        guard let apps = value as? [[String: Any]] else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: apps.map {
            let app = AppGestureCommands(dictionary: $0)
            let normalizedName: String
            switch app.application {
            case "Chrome":
                normalizedName = "Google Chrome"
            case "Word":
                normalizedName = "Microsoft Word"
            default:
                normalizedName = app.application
            }
            return (normalizedName, app)
        })
    }

    private static func bool(_ value: Any?, default defaultValue: Bool) -> Bool {
        guard let value else {
            return defaultValue
        }
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.intValue != 0
        }
        return defaultValue
    }

    private static func double(_ value: Any?, default defaultValue: Double) -> Double {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return defaultValue
    }
}

private enum DefaultsFactory {
    static func makeDefaultSettings() -> [String: Any] {
        [
            "enAll": 1,
            "ClickSpeed": 0.25,
            "Sensitivity": 4.6666,
            "ShowIcon": 1,
            "Revision": 20240427,
            "LogLevel": 0,
            "enTPAll": 1,
            "Handed": 0,
            "enMMAll": 1,
            "MMHanded": 0,
            "enCharRegTP": 0,
            "enCharRegMM": 0,
            "charRegMouseButton": 0,
            "charRegIndexRingDistance": 0.33,
            "enOneDrawing": 0,
            "enTwoDrawing": 1,
            "TrackpadCommands": [
                app("All Applications", gestures: [
                    gesture("One-Fix Left-Tap", "Previous Tab"),
                    gesture("One-Fix Right-Tap", "Next Tab"),
                    gesture("One-Fix One-Slide", "Move / Resize"),
                    gesture("One-Fix Two-Slide-Down", "Close / Close Tab"),
                    gesture("Three-Finger Tap", "Middle Click"),
                    gesture("Pinky-To-Index", "Zoom"),
                    gesture("Index-To-Pinky", "Minimize")
                ])
            ],
            "MagicMouseCommands": [
                app("All Applications", gestures: [
                    gesture("Middle-Fix Index-Near-Tap", "Next Tab"),
                    gesture("Middle-Fix Index-Far-Tap", "Previous Tab"),
                    gesture("Middle-Fix Index-Slide-Out", "Close / Close Tab"),
                    gesture("Middle-Fix Index-Slide-In", "Refresh"),
                    gesture("Three-Swipe-Up", "Show Desktop"),
                    gesture("Three-Swipe-Down", "Mission Control"),
                    gesture("V-Shape", "Move / Resize"),
                    gesture("Middle Click", "Middle Click")
                ])
            ],
            "RecognitionCommands": [
                app("All Applications", gestures: [
                    gesture("B", "Launch Browser"),
                    gesture("F", "Launch Finder"),
                    gesture("N", "New"),
                    gesture("O", "Open"),
                    gesture("S", "Save"),
                    gesture("T", "New Tab"),
                    gesture("Up", "Copy"),
                    gesture("Down", "Paste")
                ])
            ]
        ]
    }

    private static func app(_ name: String, gestures: [[String: Any]]) -> [String: Any] {
        ["Application": name, "Path": "", "Gestures": gestures]
    }

    private static func gesture(_ gesture: String, _ command: String) -> [String: Any] {
        [
            "Gesture": gesture,
            "Command": command,
            "IsAction": true,
            "ModifierFlags": 0,
            "KeyCode": 0,
            "Enable": 1
        ]
    }
}
