import Foundation

final class GestureController {
    private let settingsStore: SettingsStore
    private let commandDispatcher: CommandDispatcher
    private var deviceManager: MultiTouchDeviceManager?
    private var eventTap: EventTap?
    private var trackpadRecognizer = TrackpadGestureRecognizer()
    private var magicMouseRecognizer = MagicMouseGestureRecognizer()

    init(settingsStore: SettingsStore, commandDispatcher: CommandDispatcher) {
        self.settingsStore = settingsStore
        self.commandDispatcher = commandDispatcher
    }

    func start() {
        deviceManager = MultiTouchDeviceManager { [weak self] device, touches, timestamp in
            self?.handle(device: device, touches: touches, timestamp: timestamp)
        }
        deviceManager?.start()

        eventTap = EventTap()
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

        switch device {
        case .trackpad:
            guard settingsStore.settings.trackpadEnabled else {
                trackpadRecognizer.reset()
                return
            }
            let normalizedTouches = settingsStore.settings.trackpadLeftHanded ? touches.map(\.mirroredHorizontally) : touches
            if let gesture = trackpadRecognizer.update(touches: normalizedTouches.contactsOnly(), timestamp: timestamp) {
                commandDispatcher.dispatch(gesture.rawValue, device: .trackpad)
            }

        case .magicMouse:
            guard settingsStore.settings.magicMouseEnabled else {
                magicMouseRecognizer.reset()
                return
            }
            let normalizedTouches = settingsStore.settings.magicMouseLeftHanded ? touches.map(\.mirroredHorizontally) : touches
            if let gesture = magicMouseRecognizer.update(touches: normalizedTouches.contactsOnly(), timestamp: timestamp) {
                commandDispatcher.dispatch(gesture.rawValue, device: .magicMouse)
            }

        case .characterRecognition:
            break
        }
    }
}

private extension Array where Element == TouchPoint {
    func contactsOnly() -> [TouchPoint] {
        filter { $0.state.isContact }
    }
}
