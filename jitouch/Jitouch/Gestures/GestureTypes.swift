import Foundation

enum GestureDevice: String {
    case trackpad = "trackpad"
    case magicMouse = "magicmouse"
    case characterRecognition = "charrec"
}

enum RecognizedGesture: String {
    case oneFixLeftTap = "One-Fix Left-Tap"
    case oneFixRightTap = "One-Fix Right-Tap"
    case oneFixOneSlide = "One-Fix One-Slide"
    case oneFixTwoSlideUp = "One-Fix Two-Slide-Up"
    case oneFixTwoSlideDown = "One-Fix Two-Slide-Down"
    case oneFixPressTwoSlideUp = "One-Fix-Press Two-Slide-Up"
    case oneFixPressTwoSlideDown = "One-Fix-Press Two-Slide-Down"
    case twoFixIndexDoubleTap = "Two-Fix Index-Double-Tap"
    case twoFixMiddleDoubleTap = "Two-Fix Middle-Double-Tap"
    case twoFixRingDoubleTap = "Two-Fix Ring-Double-Tap"
    case twoFixOneSlideUp = "Two-Fix One-Slide-Up"
    case twoFixOneSlideDown = "Two-Fix One-Slide-Down"
    case twoFixOneSlideLeft = "Two-Fix One-Slide-Left"
    case twoFixOneSlideRight = "Two-Fix One-Slide-Right"
    case threeFingerTap = "Three-Finger Tap"
    case threeFingerClick = "Three-Finger Click"
    case threeFingerPinchIn = "Three-Finger Pinch-In"
    case threeFingerPinchOut = "Three-Finger Pinch-Out"
    case fourFingerTap = "Four-Finger Tap"
    case fourFingerClick = "Four-Finger Click"
    case threeSwipeUp = "Three-Swipe-Up"
    case threeSwipeDown = "Three-Swipe-Down"
    case threeSwipeLeft = "Three-Swipe-Left"
    case threeSwipeRight = "Three-Swipe-Right"
    case fourSwipeUp = "Four-Swipe-Up"
    case fourSwipeDown = "Four-Swipe-Down"
    case fourSwipeLeft = "Four-Swipe-Left"
    case fourSwipeRight = "Four-Swipe-Right"
    case pinkyToIndex = "Pinky-To-Index"
    case indexToPinky = "Index-To-Pinky"
    case leftSideScroll = "Left-Side Scroll"
    case rightSideScroll = "Right-Side Scroll"
    case middleClick = "Middle Click"
    case middleFixIndexNearTap = "Middle-Fix Index-Near-Tap"
    case middleFixIndexFarTap = "Middle-Fix Index-Far-Tap"
    case indexFixMiddleNearTap = "Index-Fix Middle-Near-Tap"
    case indexFixMiddleFarTap = "Index-Fix Middle-Far-Tap"
    case middleFixIndexSlideOut = "Middle-Fix Index-Slide-Out"
    case middleFixIndexSlideIn = "Middle-Fix Index-Slide-In"
    case indexFixMiddleSlideOut = "Index-Fix Middle-Slide-Out"
    case indexFixMiddleSlideIn = "Index-Fix Middle-Slide-In"
    case pinchOut = "Pinch Out"
    case pinchIn = "Pinch In"
    case thumb = "Thumb"
    case vShape = "V-Shape"

    static let trackpadSupported: [RecognizedGesture] = [
        .oneFixLeftTap,
        .oneFixRightTap,
        .oneFixOneSlide,
        .oneFixTwoSlideUp,
        .oneFixTwoSlideDown,
        .oneFixPressTwoSlideUp,
        .oneFixPressTwoSlideDown,
        .twoFixIndexDoubleTap,
        .twoFixMiddleDoubleTap,
        .twoFixRingDoubleTap,
        .twoFixOneSlideUp,
        .twoFixOneSlideDown,
        .twoFixOneSlideLeft,
        .twoFixOneSlideRight,
        .threeFingerTap,
        .threeFingerClick,
        .threeFingerPinchIn,
        .threeFingerPinchOut,
        .threeSwipeUp,
        .threeSwipeDown,
        .threeSwipeLeft,
        .threeSwipeRight,
        .fourFingerTap,
        .fourFingerClick,
        .fourSwipeUp,
        .fourSwipeDown,
        .fourSwipeLeft,
        .fourSwipeRight,
        .pinkyToIndex,
        .indexToPinky,
        .leftSideScroll,
        .rightSideScroll
    ]

    static let trackpadEventTapSupported: [RecognizedGesture] = [
        .threeFingerTap,
        .fourFingerTap
    ]

    static let trackpadPlanned: [RecognizedGesture] = [
    ]

    static let magicMouseSupported: [RecognizedGesture] = [
        .middleFixIndexNearTap,
        .middleFixIndexFarTap,
        .indexFixMiddleNearTap,
        .indexFixMiddleFarTap,
        .middleFixIndexSlideOut,
        .middleFixIndexSlideIn,
        .indexFixMiddleSlideOut,
        .indexFixMiddleSlideIn,
        .threeSwipeUp,
        .threeSwipeDown,
        .threeSwipeLeft,
        .threeSwipeRight,
        .threeFingerClick,
        .middleClick,
        .twoFixOneSlideUp,
        .twoFixOneSlideDown,
        .twoFixOneSlideLeft,
        .twoFixOneSlideRight,
        .pinchOut,
        .pinchIn,
        .thumb,
        .vShape
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
