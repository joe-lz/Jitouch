import Foundation

final class GestureController {
    private let settingsStore: SettingsStore
    private let commandDispatcher: CommandDispatcher
    private var deviceManager: MultiTouchDeviceManager?
    private var eventTap: EventTap?
    private var trackpadRecognizer = TrackpadGestureRecognizer()
    private var magicMouseRecognizer = MagicMouseGestureRecognizer()
    private var lastLoggedContactCounts: [GestureDevice: Int] = [:]
    private var currentContactCounts: [GestureDevice: Int] = [:]

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
            if let gesture = trackpadRecognizer.update(touches: normalizedTouches.contactsOnly(), timestamp: timestamp) {
                NSLog("Jitouch: recognized trackpad gesture \(gesture.rawValue)")
                commandDispatcher.dispatch(gesture.rawValue, device: .trackpad)
            }

        case .magicMouse:
            guard settingsStore.settings.magicMouseEnabled else {
                magicMouseRecognizer.reset()
                return
            }
            let normalizedTouches = settingsStore.settings.magicMouseLeftHanded ? touches.map(\.mirroredHorizontally) : touches
            if let gesture = magicMouseRecognizer.update(touches: normalizedTouches.contactsOnly(), timestamp: timestamp) {
                NSLog("Jitouch: recognized magicmouse gesture \(gesture.rawValue)")
                commandDispatcher.dispatch(gesture.rawValue, device: .magicMouse)
            }

        case .characterRecognition:
            break
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
}

private extension Array where Element == TouchPoint {
    func contactsOnly() -> [TouchPoint] {
        filter { $0.state.isContact }
    }
}
