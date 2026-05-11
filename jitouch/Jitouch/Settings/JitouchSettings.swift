import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }

    var localizationIdentifier: String? {
        switch self {
        case .system:
            return nil
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        }
    }
}

enum AppThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
}

struct GestureCommand: Equatable {
    var gesture: String
    var command: String
    var isAction: Bool
    var modifierFlags: UInt64
    var keyCode: UInt16
    var isEnabled: Bool
    var openFilePath: String?
    var openURL: String?

    init(
        gesture: String,
        command: String,
        isAction: Bool,
        modifierFlags: UInt64,
        keyCode: UInt16,
        isEnabled: Bool,
        openFilePath: String?,
        openURL: String?
    ) {
        self.gesture = gesture
        self.command = command
        self.isAction = isAction
        self.modifierFlags = modifierFlags
        self.keyCode = keyCode
        self.isEnabled = isEnabled
        self.openFilePath = openFilePath
        self.openURL = openURL
    }

    init(dictionary: [String: Any]) {
        gesture = dictionary["Gesture"] as? String ?? ""
        command = dictionary["Command"] as? String ?? "-"
        isAction = (dictionary["IsAction"] as? Bool) ?? true
        modifierFlags = Self.number(dictionary["ModifierFlags"])?.uint64Value ?? 0
        keyCode = Self.number(dictionary["KeyCode"])?.uint16Value ?? 0
        isEnabled = Self.number(dictionary["Enable"])?.intValue != 0
        openFilePath = dictionary["OpenFilePath"] as? String
        openURL = dictionary["OpenURL"] as? String
    }

    func dictionary() -> [String: Any] {
        var value: [String: Any] = [
            "Gesture": gesture,
            "Command": command,
            "IsAction": isAction,
            "ModifierFlags": NSNumber(value: modifierFlags),
            "KeyCode": NSNumber(value: keyCode),
            "Enable": NSNumber(value: isEnabled)
        ]
        if let openFilePath {
            value["OpenFilePath"] = openFilePath
        }
        if let openURL {
            value["OpenURL"] = openURL
        }
        return value
    }

    private static func number(_ value: Any?) -> NSNumber? {
        if let number = value as? NSNumber {
            return number
        }
        if let bool = value as? Bool {
            return NSNumber(value: bool)
        }
        return nil
    }
}

struct AppGestureCommands {
    var application: String
    var path: String
    var gestures: [String: GestureCommand]

    init(dictionary: [String: Any]) {
        application = dictionary["Application"] as? String ?? "All Applications"
        path = dictionary["Path"] as? String ?? ""

        let gestureList = dictionary["Gestures"] as? [[String: Any]] ?? []
        gestures = Dictionary(uniqueKeysWithValues: gestureList.map {
            let command = GestureCommand(dictionary: $0)
            return (command.gesture, command)
        })
    }

    func dictionary() -> [String: Any] {
        [
            "Application": application,
            "Path": path,
            "Gestures": gestures.values
                .sorted { $0.gesture.localizedStandardCompare($1.gesture) == .orderedAscending }
                .map { $0.dictionary() }
        ]
    }
}

struct JitouchSettings {
    var isEnabled = true
    var showsMenuBarIcon = true
    var clickSpeed: TimeInterval = 0.25
    var sensitivity: Double = 4.6666
    var logLevel = 0
    var appLanguage: AppLanguage = .system
    var themeMode: AppThemeMode = .system
    var iCloudSyncEnabled = false

    var trackpadEnabled = true
    var trackpadLeftHanded = false

    var magicMouseEnabled = true
    var magicMouseLeftHanded = false

    var trackpadCommands: [String: AppGestureCommands] = [:]
    var magicMouseCommands: [String: AppGestureCommands] = [:]
    var recognitionCommands: [String: AppGestureCommands] = [:]
}
