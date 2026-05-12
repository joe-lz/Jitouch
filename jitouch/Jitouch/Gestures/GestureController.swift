import ApplicationServices
import Foundation

final class GestureController {
    private let settingsStore: SettingsStore
    private let commandDispatcher: CommandDispatcher
    private var deviceManager: MultiTouchDeviceManager?
    private var eventTap: EventTap?
    private var trackpadRecognizer = TrackpadGestureRecognizer()
    private var magicMouseRecognizer = MagicMouseGestureRecognizer()
    private let windowService = AccessibilityWindowService()
    private var lastLoggedContactCounts: [GestureDevice: Int] = [:]
    private var currentContactCounts: [GestureDevice: Int] = [:]
    private var moveResizeSession: MoveResizeSession?
    private var autoScrollSession: AutoScrollSession?

    init(settingsStore: SettingsStore, commandDispatcher: CommandDispatcher) {
        self.settingsStore = settingsStore
        self.commandDispatcher = commandDispatcher
    }

    func start() {
        deviceManager = MultiTouchDeviceManager { [weak self] device, touches, timestamp in
            self?.handle(device: device, touches: touches, timestamp: timestamp)
        }
        deviceManager?.start()

        eventTap = EventTap { [weak self] _ in
            self?.handleMouseDown() ?? false
        }
        eventTap?.start()
    }

    func reload() {
        stopRecognitionState()
        deviceManager?.reload()
        eventTap?.restart()
    }

    func stopRecognitionState() {
        trackpadRecognizer.reset()
        magicMouseRecognizer.reset()
        moveResizeSession = nil
        autoScrollSession = nil
    }

    func stop() {
        deviceManager?.stop()
        eventTap?.stop()
        deviceManager = nil
        eventTap = nil
    }

    private func handle(device: GestureDevice, touches: [TouchPoint], timestamp: TimeInterval) {
        guard settingsStore.settings.isEnabled else {
            stopRecognitionState()
            return
        }

        logContactCountTransition(device: device, touches: touches)

        switch device {
        case .trackpad:
            guard settingsStore.settings.trackpadEnabled else {
                trackpadRecognizer.reset()
                return
            }
            let normalizedTouches = settingsStore.settings.trackpadLeftHanded ? touches.map(\.mirroredHorizontally) : touches
            let contacts = normalizedTouches.contactsOnly()
            if updateActiveContinuousGesture(device: .trackpad, touches: contacts, timestamp: timestamp) {
                return
            }
            if let gesture = trackpadRecognizer.update(touches: contacts, timestamp: timestamp) {
                NSLog("Jitouch: recognized trackpad gesture \(gesture.rawValue)")
                if startContinuousGestureIfNeeded(gesture: gesture, device: .trackpad, touches: contacts, timestamp: timestamp) {
                    return
                }
                commandDispatcher.dispatch(gesture.rawValue, device: .trackpad)
            }

        case .magicMouse:
            guard settingsStore.settings.magicMouseEnabled else {
                magicMouseRecognizer.reset()
                return
            }
            let normalizedTouches = settingsStore.settings.magicMouseLeftHanded ? touches.map(\.mirroredHorizontally) : touches
            let contacts = normalizedTouches.contactsOnly()
            if updateActiveContinuousGesture(device: .magicMouse, touches: contacts, timestamp: timestamp) {
                return
            }
            if let gesture = magicMouseRecognizer.update(touches: contacts, timestamp: timestamp) {
                NSLog("Jitouch: recognized magicmouse gesture \(gesture.rawValue)")
                if startContinuousGestureIfNeeded(gesture: gesture, device: .magicMouse, touches: contacts, timestamp: timestamp) {
                    return
                }
                commandDispatcher.dispatch(gesture.rawValue, device: .magicMouse)
            }
        }
    }

    private func logContactCountTransition(device: GestureDevice, touches: [TouchPoint]) {
        let contactCount = touches.contactsOnly().count
        currentContactCounts[device] = contactCount
        guard lastLoggedContactCounts[device] != contactCount else {
            return
        }
        lastLoggedContactCounts[device] = contactCount
        NSLog("Jitouch: \(device.rawValue) contact count \(contactCount) from \(touches.count) raw touch(es)")
    }

    private func handleMouseDown() -> Bool {
        guard settingsStore.settings.isEnabled else {
            return false
        }

        if settingsStore.settings.trackpadEnabled {
            switch currentContactCounts[.trackpad] {
            case 3:
                guard commandDispatcher.hasEnabledCommand(for: RecognizedGesture.threeFingerClick.rawValue, device: .trackpad) else {
                    return false
                }
                NSLog("Jitouch: recognized trackpad gesture \(RecognizedGesture.threeFingerClick.rawValue)")
                commandDispatcher.dispatch(RecognizedGesture.threeFingerClick.rawValue, device: .trackpad)
                return true
            case 4:
                guard commandDispatcher.hasEnabledCommand(for: RecognizedGesture.fourFingerClick.rawValue, device: .trackpad) else {
                    return false
                }
                NSLog("Jitouch: recognized trackpad gesture \(RecognizedGesture.fourFingerClick.rawValue)")
                commandDispatcher.dispatch(RecognizedGesture.fourFingerClick.rawValue, device: .trackpad)
                return true
            default:
                break
            }
        }

        if settingsStore.settings.magicMouseEnabled, currentContactCounts[.magicMouse] == 3 {
            guard commandDispatcher.hasEnabledCommand(for: RecognizedGesture.threeFingerClick.rawValue, device: .magicMouse) else {
                return false
            }
            NSLog("Jitouch: recognized magicmouse gesture \(RecognizedGesture.threeFingerClick.rawValue)")
            commandDispatcher.dispatch(RecognizedGesture.threeFingerClick.rawValue, device: .magicMouse)
            return true
        }

        return false
    }

    private func startContinuousGestureIfNeeded(
        gesture: RecognizedGesture,
        device: GestureDevice,
        touches: [TouchPoint],
        timestamp: TimeInterval
    ) -> Bool {
        guard let command = commandDispatcher.commandName(for: gesture.rawValue, device: device) else {
            return false
        }

        switch command {
        case "Move / Resize":
            guard
                let window = windowService.movableWindowUnderPointer(),
                let frame = windowService.frame(ofWindow: window),
                let centroid = touches.centroid
            else {
                return false
            }
            moveResizeSession = MoveResizeSession(
                device: device,
                window: window,
                startFrame: frame,
                startCentroid: centroid,
                mode: centroid.x > 0.58 || centroid.y < 0.42 ? .resize : .move
            )
            return true
        case "Auto Scroll":
            guard let centroid = touches.centroid else {
                return false
            }
            autoScrollSession = AutoScrollSession(device: device, anchorY: centroid.y, nextScrollTime: timestamp)
            return true
        default:
            return false
        }
    }

    private func updateActiveContinuousGesture(device: GestureDevice, touches: [TouchPoint], timestamp: TimeInterval) -> Bool {
        if var session = moveResizeSession {
            guard session.device == device else {
                return false
            }
            guard let centroid = touches.centroid, touches.isEmpty == false else {
                moveResizeSession = nil
                return false
            }
            let scale: CGFloat = device == .trackpad ? 900 : 700
            let dx = CGFloat(centroid.x - session.startCentroid.x) * scale
            let dy = CGFloat(session.startCentroid.y - centroid.y) * scale
            var frame = session.startFrame
            switch session.mode {
            case .move:
                frame.origin.x += dx
                frame.origin.y += dy
            case .resize:
                frame.size.width = max(240, frame.size.width + dx)
                frame.size.height = max(160, frame.size.height - dy)
            }
            windowService.setFrame(frame, ofWindow: session.window)
            session.lastCentroid = centroid
            moveResizeSession = session
            return true
        }

        if var session = autoScrollSession {
            guard session.device == device else {
                return false
            }
            guard let centroid = touches.centroid, touches.count >= 1 else {
                autoScrollSession = nil
                return false
            }
            guard timestamp >= session.nextScrollTime else {
                return true
            }
            let speed = Int(((centroid.y - session.anchorY) * 420).rounded())
            if speed != 0,
               let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: Int32(speed),
                wheel2: 0,
                wheel3: 0
               ) {
                event.post(tap: .cghidEventTap)
            }
            session.nextScrollTime = timestamp + 0.012
            autoScrollSession = session
            return true
        }

        return false
    }
}

private enum MoveResizeMode {
    case move
    case resize
}

private struct MoveResizeSession {
    var device: GestureDevice
    var window: AXUIElement
    var startFrame: CGRect
    var startCentroid: CGPoint
    var lastCentroid: CGPoint?
    var mode: MoveResizeMode
}

private struct AutoScrollSession {
    var device: GestureDevice
    var anchorY: Double
    var nextScrollTime: TimeInterval
}

private extension Array where Element == TouchPoint {
    func contactsOnly() -> [TouchPoint] {
        filter { $0.state.isContact }
    }

    var centroid: CGPoint? {
        guard isEmpty == false else {
            return nil
        }
        return CGPoint(
            x: map(\.x).reduce(0, +) / Double(count),
            y: map(\.y).reduce(0, +) / Double(count)
        )
    }
}
