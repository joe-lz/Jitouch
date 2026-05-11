import ApplicationServices
import AppKit

final class AccessibilityWindowService {
    private let systemWide = AXUIElementCreateSystemWide()
    private var savedFrames: [pid_t: CGRect] = [:]

    func applicationUnderPointer() -> String? {
        guard let element = elementUnderPointer() else {
            return NSWorkspace.shared.frontmostApplication?.localizedName
        }
        return applicationName(for: element)
    }

    func activateWindowUnderPointer() -> AXUIElement? {
        guard let element = elementUnderPointer() else {
            return focusedWindow()
        }

        var windowValue: CFTypeRef?
        let window = AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowValue) == .success
            ? (windowValue as! AXUIElement)
            : element

        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        if let pid = pid(for: window), let application = NSRunningApplication(processIdentifier: pid) {
            application.activate(options: [.activateIgnoringOtherApps])
        }
        return window
    }

    func focusedWindow() -> AXUIElement? {
        var appValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &appValue) == .success else {
            guard let app = NSWorkspace.shared.frontmostApplication else {
                return nil
            }
            return AXUIElementCreateApplication(app.processIdentifier)
        }

        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appValue as! AXUIElement, kAXFocusedWindowAttribute as CFString, &windowValue) == .success else {
            return nil
        }
        return (windowValue as! AXUIElement)
    }

    func minimizeFocusedWindow() {
        guard let window = focusedWindow() else {
            return
        }
        var buttonValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizeButtonAttribute as CFString, &buttonValue) == .success {
            AXUIElementPerformAction(buttonValue as! AXUIElement, kAXPressAction as CFString)
        }
    }

    func zoomFocusedWindow() {
        guard let window = focusedWindow() else {
            return
        }
        var buttonValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXZoomButtonAttribute as CFString, &buttonValue) == .success {
            AXUIElementPerformAction(buttonValue as! AXUIElement, kAXPressAction as CFString)
        }
    }

    func tileFocusedWindow(_ position: WindowTilePosition) {
        guard let window = focusedWindow(), let screen = NSScreen.main else {
            return
        }

        let current = frame(of: window)
        if let current, let pid = pid(for: window), savedFrames[pid] == nil {
            savedFrames[pid] = current
        }

        let visible = screen.visibleFrame
        let frame: CGRect
        switch position {
        case .full:
            frame = visible
        case .left:
            frame = CGRect(x: visible.minX, y: visible.minY, width: visible.width / 2, height: visible.height)
        case .right:
            frame = CGRect(x: visible.midX, y: visible.minY, width: visible.width / 2, height: visible.height)
        case .restore:
            guard let pid = pid(for: window), let saved = savedFrames.removeValue(forKey: pid) else {
                return
            }
            frame = saved
        }

        setFrame(frame, for: window)
    }

    private func elementUnderPointer() -> AXUIElement? {
        let location = CGEvent(source: nil)?.location ?? .zero
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(location.x), Float(location.y), &element) == .success else {
            return nil
        }
        return element
    }

    private func applicationName(for element: AXUIElement) -> String? {
        guard let pid = pid(for: element) else {
            return nil
        }
        return NSRunningApplication(processIdentifier: pid)?.localizedName
    }

    private func pid(for element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else {
            return nil
        }
        return pid
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success
        else {
            return nil
        }

        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    private func setFrame(_ frame: CGRect, for window: AXUIElement) {
        var origin = frame.origin
        var size = frame.size
        if let position = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }
}

enum WindowTilePosition {
    case full
    case left
    case right
    case restore
}
