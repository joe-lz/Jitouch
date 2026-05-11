import Foundation

struct GestureCommand: Equatable {
    var gesture: String
    var command: String
    var isAction: Bool
    var modifierFlags: UInt64
    var keyCode: UInt16
    var isEnabled: Bool
    var openFilePath: String?
    var openURL: String?

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
}

struct JitouchSettings {
    var isEnabled = true
    var showsMenuBarIcon = true
    var clickSpeed: TimeInterval = 0.25
    var sensitivity: Double = 4.6666
    var logLevel = 0

    var trackpadEnabled = true
    var trackpadLeftHanded = false

    var magicMouseEnabled = true
    var magicMouseLeftHanded = false

    var trackpadCommands: [String: AppGestureCommands] = [:]
    var magicMouseCommands: [String: AppGestureCommands] = [:]
    var recognitionCommands: [String: AppGestureCommands] = [:]
}
