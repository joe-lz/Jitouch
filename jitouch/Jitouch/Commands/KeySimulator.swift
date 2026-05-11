import ApplicationServices
import AppKit

enum KeySimulator {
    private static let keyCodes: [String: CGKeyCode] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7,
        "C": 8, "V": 9, "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15,
        "Y": 16, "T": 17, "O": 31, "U": 32, "I": 34, "P": 35, "L": 37,
        "J": 38, "K": 40, "N": 45, "M": 46, "Tab": 48, "Space": 49,
        "Escape": 53, "Home": 115, "End": 119, "Left": 123, "Right": 124,
        "Down": 125, "Up": 126
    ]

    static func press(_ key: String, modifiers: CGEventFlags = []) {
        guard let code = keyCodes[key] else {
            NSLog("Jitouch: unknown key \(key)")
            return
        }
        press(keyCode: code, modifiers: modifiers)
    }

    static func press(keyCode: CGKeyCode, modifiers: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = modifiers
        up?.flags = modifiers
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    static func click(button: CGMouseButton, typeDown: CGEventType, typeUp: CGEventType) {
        let source = CGEventSource(stateID: .hidSystemState)
        let location = CGEvent(source: source)?.location ?? .zero
        CGEvent(mouseEventSource: source, mouseType: typeDown, mouseCursorPosition: location, mouseButton: button)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: source, mouseType: typeUp, mouseCursorPosition: location, mouseButton: button)?.post(tap: .cghidEventTap)
    }

    static func mediaKey(_ key: Int32) {
        let down = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((key << 16) | 0xa00),
            data2: -1
        )
        let up = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xb00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((key << 16) | 0xb00),
            data2: -1
        )
        if let event = down?.cgEvent {
            event.post(tap: .cghidEventTap)
        }
        if let event = up?.cgEvent {
            event.post(tap: .cghidEventTap)
        }
    }
}
