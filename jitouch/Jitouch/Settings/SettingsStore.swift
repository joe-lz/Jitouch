import Foundation

final class SettingsStore {
    private enum Key {
        static let enabled = "enAll"
        static let clickSpeed = "ClickSpeed"
        static let sensitivity = "Sensitivity"
        static let showIcon = "ShowIcon"
        static let logLevel = "LogLevel"
        static let appLanguage = "AppLanguage"
        static let nightMode = "NightMode"
        static let themeMode = "ThemeMode"
        static let trackpadEnabled = "enTPAll"
        static let handed = "Handed"
        static let magicMouseEnabled = "enMMAll"
        static let magicMouseHanded = "MMHanded"
        static let trackpadCommands = "TrackpadCommands"
        static let magicMouseCommands = "MagicMouseCommands"
        static let recognitionCommands = "RecognitionCommands"
    }

    private let appID = "com.zhuanz.JitouchModern" as CFString
    private(set) var rawSettings: [String: Any] = [:]
    var settings = JitouchSettings()

    func load() {
        let preferencesDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences")
        guard
            let data = try? Data(contentsOf: preferencesDirectory.appendingPathComponent("com.zhuanz.JitouchModern.plist")),
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
        persistRawSettings()
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
        setBool(settings.isEnabled, forKey: Key.enabled)
        synchronize()
    }

    func updateGeneralSettings(_ update: (inout JitouchSettings) -> Void) {
        update(&settings)
        setBool(settings.isEnabled, forKey: Key.enabled)
        setBool(settings.showsMenuBarIcon, forKey: Key.showIcon)
        setDouble(settings.clickSpeed, forKey: Key.clickSpeed)
        setDouble(settings.sensitivity, forKey: Key.sensitivity)
        setBool(settings.trackpadEnabled, forKey: Key.trackpadEnabled)
        setBool(settings.trackpadLeftHanded, forKey: Key.handed)
        setBool(settings.magicMouseEnabled, forKey: Key.magicMouseEnabled)
        setBool(settings.magicMouseLeftHanded, forKey: Key.magicMouseHanded)
        setString(settings.appLanguage.rawValue, forKey: Key.appLanguage)
        setString(settings.themeMode.rawValue, forKey: Key.themeMode)
        synchronize()
    }

    func postRuntimeSettingsChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            .jitouchRuntimeDidChange,
            object: NotificationObject.runtime,
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

    func applicationProfiles(for device: GestureDevice) -> [AppGestureCommands] {
        let map: [String: AppGestureCommands]
        switch device {
        case .trackpad:
            map = settings.trackpadCommands
        case .magicMouse:
            map = settings.magicMouseCommands
        case .characterRecognition:
            map = settings.recognitionCommands
        }

        return map.values.sorted {
            if $0.application == "All Applications" {
                return true
            }
            if $1.application == "All Applications" {
                return false
            }
            return $0.application.localizedStandardCompare($1.application) == .orderedAscending
        }
    }

    func commands(for device: GestureDevice, application: String) -> [GestureCommand] {
        let appCommands = applicationProfiles(for: device).first { $0.application == application }
        let commands = appCommands.map { Array($0.gestures.values) } ?? []
        let catalog = gestureCatalog(for: device)
        return commands
            .sorted {
                let lhs = catalog.firstIndex(of: $0.gesture) ?? Int.max
                let rhs = catalog.firstIndex(of: $1.gesture) ?? Int.max
                if lhs == rhs {
                    return $0.gesture.localizedStandardCompare($1.gesture) == .orderedAscending
                }
                return lhs < rhs
            }
    }

    func allApplicationCommands(for device: GestureDevice) -> [GestureCommand] {
        commands(for: device, application: "All Applications")
    }

    func gestureCatalog(for device: GestureDevice) -> [String] {
        switch device {
        case .trackpad:
            return DefaultsFactory.trackpadGestures
        case .magicMouse:
            return DefaultsFactory.magicMouseGestures
        case .characterRecognition:
            return []
        }
    }

    func availableGestures(for device: GestureDevice, application: String) -> [String] {
        let assigned = Set(commands(for: device, application: application).map(\.gesture))
        return gestureCatalog(for: device).filter { !assigned.contains($0) }
    }

    func availableGestures(for device: GestureDevice) -> [String] {
        availableGestures(for: device, application: "All Applications")
    }

    func updateCommand(_ command: GestureCommand, device: GestureDevice, application: String = "All Applications", path: String = "") {
        switch device {
        case .trackpad:
            var app = settings.trackpadCommands[application] ?? AppGestureCommands(dictionary: ["Application": application, "Path": path, "Gestures": []])
            app.path = path.isEmpty ? app.path : path
            app.gestures[command.gesture] = command
            settings.trackpadCommands[application] = app
            saveCommandMap(settings.trackpadCommands, key: Key.trackpadCommands)

        case .magicMouse:
            var app = settings.magicMouseCommands[application] ?? AppGestureCommands(dictionary: ["Application": application, "Path": path, "Gestures": []])
            app.path = path.isEmpty ? app.path : path
            app.gestures[command.gesture] = command
            settings.magicMouseCommands[application] = app
            saveCommandMap(settings.magicMouseCommands, key: Key.magicMouseCommands)

        case .characterRecognition:
            var app = settings.recognitionCommands[application] ?? AppGestureCommands(dictionary: ["Application": application, "Path": path, "Gestures": []])
            app.path = path.isEmpty ? app.path : path
            app.gestures[command.gesture] = command
            settings.recognitionCommands[application] = app
            saveCommandMap(settings.recognitionCommands, key: Key.recognitionCommands)
        }
    }

    func removeCommand(gesture: String, device: GestureDevice, application: String = "All Applications") {
        switch device {
        case .trackpad:
            settings.trackpadCommands[application]?.gestures.removeValue(forKey: gesture)
            saveCommandMap(settings.trackpadCommands, key: Key.trackpadCommands)
        case .magicMouse:
            settings.magicMouseCommands[application]?.gestures.removeValue(forKey: gesture)
            saveCommandMap(settings.magicMouseCommands, key: Key.magicMouseCommands)
        case .characterRecognition:
            settings.recognitionCommands[application]?.gestures.removeValue(forKey: gesture)
            saveCommandMap(settings.recognitionCommands, key: Key.recognitionCommands)
        }
    }

    func restoreDefaultCommands(for device: GestureDevice) {
        let defaults = DefaultsFactory.makeDefaultSettings()
        switch device {
        case .trackpad:
            rawSettings[Key.trackpadCommands] = defaults[Key.trackpadCommands]
            settings.trackpadCommands = Self.commandMap(from: defaults[Key.trackpadCommands])
            CFPreferencesSetAppValue(Key.trackpadCommands as CFString, rawSettings[Key.trackpadCommands] as CFPropertyList, appID)
        case .magicMouse:
            rawSettings[Key.magicMouseCommands] = defaults[Key.magicMouseCommands]
            settings.magicMouseCommands = Self.commandMap(from: defaults[Key.magicMouseCommands])
            CFPreferencesSetAppValue(Key.magicMouseCommands as CFString, rawSettings[Key.magicMouseCommands] as CFPropertyList, appID)
        case .characterRecognition:
            rawSettings[Key.recognitionCommands] = defaults[Key.recognitionCommands]
            settings.recognitionCommands = Self.commandMap(from: defaults[Key.recognitionCommands])
            CFPreferencesSetAppValue(Key.recognitionCommands as CFString, rawSettings[Key.recognitionCommands] as CFPropertyList, appID)
        }
        synchronize()
    }

    private func apply(_ dictionary: [String: Any]) {
        settings.isEnabled = Self.bool(dictionary[Key.enabled], default: true)
        settings.showsMenuBarIcon = Self.bool(dictionary[Key.showIcon], default: true)
        settings.clickSpeed = Self.double(dictionary[Key.clickSpeed], default: 0.25)
        settings.sensitivity = Self.double(dictionary[Key.sensitivity], default: 4.6666)
        settings.logLevel = Int(Self.double(dictionary[Key.logLevel], default: 0))
        settings.appLanguage = AppLanguage(rawValue: dictionary[Key.appLanguage] as? String ?? "") ?? .system
        settings.themeMode = Self.themeMode(from: dictionary)
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

    private func setBool(_ value: Bool, forKey key: String) {
        rawSettings[key] = value ? 1 : 0
        CFPreferencesSetAppValue(key as CFString, NSNumber(value: value), appID)
    }

    private func setDouble(_ value: Double, forKey key: String) {
        rawSettings[key] = value
        CFPreferencesSetAppValue(key as CFString, NSNumber(value: value), appID)
    }

    private func setString(_ value: String, forKey key: String) {
        rawSettings[key] = value
        CFPreferencesSetAppValue(key as CFString, value as CFString, appID)
    }

    private func synchronize() {
        CFPreferencesAppSynchronize(appID)
    }

    private func saveCommandMap(_ map: [String: AppGestureCommands], key: String) {
        rawSettings[key] = map.values
            .sorted { $0.application.localizedStandardCompare($1.application) == .orderedAscending }
            .map { $0.dictionary() }
        CFPreferencesSetAppValue(key as CFString, rawSettings[key] as CFPropertyList, appID)
        synchronize()
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

    private static func themeMode(from dictionary: [String: Any]) -> AppThemeMode {
        if let rawValue = dictionary[Key.themeMode] as? String,
           let themeMode = AppThemeMode(rawValue: rawValue) {
            return themeMode
        }

        return bool(dictionary[Key.nightMode], default: false) ? .dark : .system
    }
}

private enum DefaultsFactory {
    static let trackpadGestures = [
        "One-Fix Left-Tap",
        "One-Fix Right-Tap",
        "One-Fix One-Slide",
        "One-Fix Two-Slide-Up",
        "One-Fix Two-Slide-Down",
        "One-Fix-Press Two-Slide-Up",
        "One-Fix-Press Two-Slide-Down",
        "Two-Fix Index-Double-Tap",
        "Two-Fix Middle-Double-Tap",
        "Two-Fix Ring-Double-Tap",
        "Two-Fix One-Slide-Up",
        "Two-Fix One-Slide-Down",
        "Two-Fix One-Slide-Left",
        "Two-Fix One-Slide-Right",
        "Three-Finger Tap",
        "Three-Finger Click",
        "Three-Finger Pinch-In",
        "Three-Finger Pinch-Out",
        "Three-Swipe-Up",
        "Three-Swipe-Down",
        "Three-Swipe-Left",
        "Three-Swipe-Right",
        "Four-Finger Tap",
        "Four-Finger Click",
        "Four-Swipe-Up",
        "Four-Swipe-Down",
        "Four-Swipe-Left",
        "Four-Swipe-Right",
        "Pinky-To-Index",
        "Index-To-Pinky",
        "Left-Side Scroll",
        "Right-Side Scroll",
        "All Unassigned Gestures"
    ]

    static let magicMouseGestures = [
        "Middle-Fix Index-Near-Tap",
        "Middle-Fix Index-Far-Tap",
        "Index-Fix Middle-Near-Tap",
        "Index-Fix Middle-Far-Tap",
        "Middle-Fix Index-Slide-Out",
        "Middle-Fix Index-Slide-In",
        "Index-Fix Middle-Slide-Out",
        "Index-Fix Middle-Slide-In",
        "Three-Swipe-Left",
        "Three-Swipe-Right",
        "Three-Swipe-Up",
        "Three-Swipe-Down",
        "Three-Finger Click",
        "V-Shape",
        "Middle Click",
        "Two-Fix One-Slide-Up",
        "Two-Fix One-Slide-Down",
        "Two-Fix One-Slide-Left",
        "Two-Fix One-Slide-Right",
        "Thumb",
        "All Unassigned Gestures"
    ]

    static func makeDefaultSettings() -> [String: Any] {
        [
            "enAll": 1,
            "ClickSpeed": 0.25,
            "Sensitivity": 4.6666,
            "ShowIcon": 1,
            "Revision": 20240427,
            "LogLevel": 0,
            "AppLanguage": AppLanguage.system.rawValue,
            "ThemeMode": AppThemeMode.system.rawValue,
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
