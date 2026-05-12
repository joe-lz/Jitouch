import ApplicationServices
import Foundation

final class EventTap {
    typealias MouseDownHandler = (CGEventType) -> Bool

    private static weak var activeTap: EventTap?

    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let mouseDownHandler: MouseDownHandler?

    init(mouseDownHandler: MouseDownHandler? = nil) {
        self.mouseDownHandler = mouseDownHandler
    }

    func start() {
        stop()
        Self.activeTap = self

        let mask =
            CGEventMask(1 << CGEventType.scrollWheel.rawValue) |
            CGEventMask(1 << CGEventType.mouseMoved.rawValue) |
            CGEventMask(1 << CGEventType.leftMouseDown.rawValue) |
            CGEventMask(1 << CGEventType.leftMouseUp.rawValue) |
            CGEventMask(1 << CGEventType.rightMouseDown.rawValue) |
            CGEventMask(1 << CGEventType.rightMouseUp.rawValue) |
            CGEventMask(1 << CGEventType.otherMouseDown.rawValue) |
            CGEventMask(1 << CGEventType.otherMouseUp.rawValue) |
            CGEventMask(1 << CGEventType.leftMouseDragged.rawValue) |
            CGEventMask(1 << CGEventType.rightMouseDragged.rawValue) |
            CGEventMask(1 << CGEventType.otherMouseDragged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: nil
        ) else {
            NSLog("Jitouch: could not create event tap. Allow Jitouch in System Settings > Privacy & Security > Accessibility.")
            return
        }

        machPort = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("Jitouch: event tap started")
    }

    func restart() {
        start()
    }

    func stop() {
        if let machPort {
            CGEvent.tapEnable(tap: machPort, enable: false)
        }
        if Self.activeTap === self {
            Self.activeTap = nil
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        machPort = nil
    }

    private static let callback: CGEventTapCallBack = { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            return Unmanaged.passUnretained(event)
        }
        if (type == .leftMouseDown || type == .rightMouseDown),
           EventTap.activeTap?.mouseDownHandler?(type) == true {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}
