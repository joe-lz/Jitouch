import Foundation

typealias MTDeviceRef = UnsafeMutableRawPointer?

struct MTPoint {
    var x: Float
    var y: Float
}

struct MTReadout {
    var pos: MTPoint
    var vel: MTPoint
}

struct MTFinger {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: UInt32
    var fingerID: Int32
    var handID: Int32
    var normalized: MTReadout
    var size: Float
    var zero1: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var mm: MTReadout
    var zero2: (Int32, Int32)
    var zDensity: Float
}

typealias MTContactCallback = @convention(c) (MTDeviceRef, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

@_silgen_name("MTDeviceCreateList")
func MTDeviceCreateList() -> Unmanaged<CFMutableArray>?

@_silgen_name("MTRegisterContactFrameCallback")
func MTRegisterContactFrameCallback(_ device: MTDeviceRef, _ callback: MTContactCallback)

@_silgen_name("MTUnregisterContactFrameCallback")
func MTUnregisterContactFrameCallback(_ device: MTDeviceRef, _ callback: MTContactCallback)

@_silgen_name("MTDeviceStart")
func MTDeviceStart(_ device: MTDeviceRef, _ unknown: Int32)

@_silgen_name("MTDeviceStop")
func MTDeviceStop(_ device: MTDeviceRef)

@_silgen_name("MTDeviceGetFamilyID")
func MTDeviceGetFamilyID(_ device: MTDeviceRef, _ familyID: UnsafeMutablePointer<Int32>)

@_silgen_name("MTDeviceIsRunning")
func MTDeviceIsRunning(_ device: MTDeviceRef) -> Bool

enum MultiTouchFamily {
    static let minimumSupportedID: Int32 = 98
    static let builtInTrackpad: Set<Int32> = [98, 99, 100, 101, 102, 103, 104, 105, 113]
    static let magicMouse: Set<Int32> = [112]
    static let magicTrackpad: Set<Int32> = [128, 129, 130]

    static func deviceType(for familyID: Int32) -> GestureDevice? {
        if builtInTrackpad.contains(familyID) || magicTrackpad.contains(familyID) {
            return .trackpad
        }
        if magicMouse.contains(familyID) {
            return .magicMouse
        }
        if familyID >= minimumSupportedID {
            return .trackpad
        }
        return nil
    }
}
