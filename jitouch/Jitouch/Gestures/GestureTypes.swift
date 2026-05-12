import Foundation

enum GestureDevice: String {
    case trackpad = "trackpad"
    case magicMouse = "magicmouse"
    case characterRecognition = "charrec"
}

enum RecognizedGesture: String {
    case oneFixLeftTap = "One-Fix Left-Tap"
    case oneFixRightTap = "One-Fix Right-Tap"
    case threeFingerTap = "Three-Finger Tap"
    case fourFingerTap = "Four-Finger Tap"
    case threeSwipeUp = "Three-Swipe-Up"
    case threeSwipeDown = "Three-Swipe-Down"
    case threeSwipeLeft = "Three-Swipe-Left"
    case threeSwipeRight = "Three-Swipe-Right"
    case middleClick = "Middle Click"
    case middleFixIndexNearTap = "Middle-Fix Index-Near-Tap"
    case middleFixIndexFarTap = "Middle-Fix Index-Far-Tap"
    case middleFixIndexSlideOut = "Middle-Fix Index-Slide-Out"
    case middleFixIndexSlideIn = "Middle-Fix Index-Slide-In"

    static let trackpadSupported: [RecognizedGesture] = [
        .oneFixLeftTap,
        .oneFixRightTap,
        .threeFingerTap,
        .fourFingerTap,
        .threeSwipeUp,
        .threeSwipeDown,
        .threeSwipeLeft,
        .threeSwipeRight
    ]

    static let magicMouseSupported: [RecognizedGesture] = [
        .middleFixIndexNearTap,
        .middleFixIndexFarTap,
        .middleFixIndexSlideOut,
        .middleFixIndexSlideIn,
        .threeSwipeLeft,
        .threeSwipeRight,
        .threeSwipeUp,
        .threeSwipeDown,
        .middleClick
    ]

    static func supportedGestures(for device: GestureDevice) -> [String] {
        switch device {
        case .trackpad:
            return trackpadSupported.map(\.rawValue)
        case .magicMouse:
            return magicMouseSupported.map(\.rawValue)
        case .characterRecognition:
            return []
        }
    }
}

struct TouchPoint: Equatable {
    var identifier: Int32
    var x: Double
    var y: Double
    var size: Double
    var state: TouchState

    var mirroredHorizontally: TouchPoint {
        TouchPoint(identifier: identifier, x: 1.0 - x, y: y, size: size, state: state)
    }
}

enum TouchState: UInt32 {
    case notTracking = 0
    case startInRange = 1
    case hoverInRange = 2
    case makeTouch = 3
    case touching = 4
    case breakTouch = 5
    case lingerInRange = 6
    case outOfRange = 7

    var isContact: Bool {
        self == .makeTouch || self == .touching || self == .breakTouch
    }
}

protocol GestureRecognizer {
    mutating func update(touches: [TouchPoint], timestamp: TimeInterval) -> RecognizedGesture?
    mutating func reset()
}
