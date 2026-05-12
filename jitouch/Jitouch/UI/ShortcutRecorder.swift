import AppKit
import SwiftUI

struct SelectedGestureShortcutCapture: NSViewRepresentable {
    var isActive: Bool
    var onShortcut: (String, UInt64, UInt16) -> Void

    func makeNSView(context: Context) -> SelectedGestureShortcutCaptureView {
        let view = SelectedGestureShortcutCaptureView()
        view.onShortcut = onShortcut
        return view
    }

    func updateNSView(_ nsView: SelectedGestureShortcutCaptureView, context: Context) {
        nsView.isActive = isActive
        nsView.onShortcut = onShortcut
        guard isActive else { return }

        DispatchQueue.main.async {
            if nsView.window?.firstResponder !== nsView {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

final class SelectedGestureShortcutCaptureView: NSView {
    var isActive = false
    var onShortcut: ((String, UInt64, UInt16) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isActive else {
            super.keyDown(with: event)
            return
        }
        record(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isActive else { return false }
        record(event)
        return true
    }

    private func record(_ event: NSEvent) {
        let flags = UInt64(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
        let keyCode = UInt16(event.keyCode)
        let text = ShortcutDisplayFormatter.displayString(for: event)
        guard text.isEmpty == false else { return }
        onShortcut?(text, flags, keyCode)
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var text: String
    @Binding var modifierFlags: UInt64
    @Binding var keyCode: UInt16
    var shouldBecomeFirstResponder: Bool

    func makeNSView(context: Context) -> ShortcutRecorderField {
        let field = ShortcutRecorderField()
        field.placeholderString = L("Press shortcut")
        field.isEditable = false
        field.isSelectable = false
        field.focusRingType = .default
        field.onChange = { text, flags, keyCode in
            self.text = text
            self.modifierFlags = flags
            self.keyCode = keyCode
        }
        return field
    }

    func updateNSView(_ nsView: ShortcutRecorderField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if shouldBecomeFirstResponder, nsView.window?.firstResponder !== nsView {
            DispatchQueue.main.async {
                if nsView.window?.firstResponder !== nsView {
                    nsView.window?.makeFirstResponder(nsView)
                }
            }
        }
    }
}

final class ShortcutRecorderField: NSTextField {
    var onChange: ((String, UInt64, UInt16) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        return didBecomeFirstResponder
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        record(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        record(event)
        return true
    }

    private func record(_ event: NSEvent) {
        let flags = UInt64(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
        let keyCode = UInt16(event.keyCode)
        let text = ShortcutDisplayFormatter.displayString(for: event)
        stringValue = text
        onChange?(text, flags, keyCode)
    }
}

private enum ShortcutDisplayFormatter {
    static func displayString(for event: NSEvent) -> String {
        var parts: [String] = []
        if event.modifierFlags.contains(.control) { parts.append("^") }
        if event.modifierFlags.contains(.option) { parts.append("⌥") }
        if event.modifierFlags.contains(.shift) { parts.append("⇧") }
        if event.modifierFlags.contains(.command) { parts.append("⌘") }
        let key = displayKey(for: event)
        parts.append(key.isEmpty ? "Key \(event.keyCode)" : key)
        return parts.joined()
    }

    private static func displayKey(for event: NSEvent) -> String {
        if let specialKey = specialKeyTitle(for: event.keyCode) {
            return specialKey
        }

        let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
        guard key.count == 1, key.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }) else {
            return ""
        }
        return key
    }

    private static func specialKeyTitle(for keyCode: UInt16) -> String? {
        switch keyCode {
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "Esc"
        case 71: return "Clear"
        case 76: return "⌅"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 106: return "F16"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 114: return "Help"
        case 115: return "↖"
        case 116: return "⇞"
        case 117: return "⌦"
        case 118: return "F4"
        case 119: return "↘"
        case 120: return "F2"
        case 121: return "⇟"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return nil
        }
    }
}
