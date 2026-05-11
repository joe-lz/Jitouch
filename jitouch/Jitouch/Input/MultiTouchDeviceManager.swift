import Foundation

final class MultiTouchDeviceManager {
    typealias TouchHandler = (GestureDevice, [TouchPoint], TimeInterval) -> Void

    private static weak var current: MultiTouchDeviceManager?

    private let handler: TouchHandler
    private var devices: [MTDeviceRef] = []
    private var deviceTypes: [UnsafeMutableRawPointer: GestureDevice] = [:]

    init(handler: @escaping TouchHandler) {
        self.handler = handler
        Self.current = self
    }

    func start() {
        stop()
        guard let list = MTDeviceCreateList()?.takeRetainedValue() else {
            NSLog("Jitouch: unable to create multitouch device list")
            return
        }

        let count = CFArrayGetCount(list)
        for index in 0..<count {
            guard let rawDevice = CFArrayGetValueAtIndex(list, index) else {
                continue
            }

            let mutableDevice = UnsafeMutableRawPointer(mutating: rawDevice)
            let device = MTDeviceRef(mutableDevice)
            var familyID: Int32 = 0
            MTDeviceGetFamilyID(device, &familyID)

            guard let deviceType = MultiTouchFamily.deviceType(for: familyID) else {
                continue
            }

            MTRegisterContactFrameCallback(device, Self.contactCallback)
            MTDeviceStart(device, 0)
            devices.append(device)
            deviceTypes[mutableDevice] = deviceType
        }
    }

    func reload() {
        stop()
        start()
    }

    func stop() {
        for device in devices {
            MTUnregisterContactFrameCallback(device, Self.contactCallback)
            MTDeviceStop(device)
        }
        devices.removeAll()
        deviceTypes.removeAll()
    }

    private func receive(device: MTDeviceRef, fingers: UnsafeMutableRawPointer?, count: Int32, timestamp: Double) -> Int32 {
        guard
            let device,
            let fingers,
            let deviceType = deviceTypes[device],
            count >= 0
        else {
            return 0
        }

        let typedFingers = fingers.bindMemory(to: MTFinger.self, capacity: Int(count))
        let points = (0..<Int(count)).map { index -> TouchPoint in
            let finger = typedFingers[index]
            return TouchPoint(
                identifier: finger.identifier,
                x: Double(finger.normalized.pos.x),
                y: Double(finger.normalized.pos.y),
                size: Double(finger.size),
                state: TouchState(rawValue: finger.state) ?? .notTracking
            )
        }

        handler(deviceType, points, timestamp)
        return 0
    }

    private static let contactCallback: MTContactCallback = { device, fingers, count, timestamp, _ in
        current?.receive(device: device, fingers: fingers, count: count, timestamp: timestamp) ?? 0
    }
}
