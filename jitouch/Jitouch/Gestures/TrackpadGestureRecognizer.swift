import Foundation

struct TrackpadGestureRecognizer: GestureRecognizer {
    private var previousTouches: [TouchPoint] = []
    private var startTouches: [TouchPoint] = []
    private var startTimestamp: TimeInterval = 0
    private var oneFixedTapTimestamp: TimeInterval = 0
    private var oneFixedTapAnchor: TouchPoint?
    private var oneFixedTapMovingTouch: TouchPoint?
    private var hasTriggered = false

    mutating func update(touches: [TouchPoint], timestamp: TimeInterval) -> RecognizedGesture? {
        defer {
            previousTouches = touches
            if touches.isEmpty {
                reset()
            }
        }

        if previousTouches.isEmpty, !touches.isEmpty {
            startTouches = touches
            startTimestamp = timestamp
            hasTriggered = false
        }

        updateOneFixedTapTracking(touches: touches, timestamp: timestamp)
        if let tap = oneFixedTap(touches: touches, timestamp: timestamp) {
            clearOneFixedTapTracking()
            return tap
        }

        guard !hasTriggered else {
            return nil
        }

        if previousTouches.count == 3, touches.isEmpty, timestamp - startTimestamp < 0.35 {
            hasTriggered = true
            return .threeFingerTap
        }

        if previousTouches.count == 4, touches.isEmpty, timestamp - startTimestamp < 0.35 {
            hasTriggered = true
            return .fourFingerTap
        }

        if let swipe = swipeGesture(requiredFingers: 3, touches: touches) {
            hasTriggered = true
            return swipe
        }

        return nil
    }

    mutating func reset() {
        previousTouches.removeAll()
        startTouches.removeAll()
        startTimestamp = 0
        clearOneFixedTapTracking()
        hasTriggered = false
    }

    private mutating func updateOneFixedTapTracking(touches: [TouchPoint], timestamp: TimeInterval) {
        guard previousTouches.count == 1, touches.count == 2 else {
            return
        }

        let anchor = previousTouches[0]
        oneFixedTapTimestamp = timestamp
        oneFixedTapAnchor = anchor
        oneFixedTapMovingTouch = touches.first { $0.identifier != anchor.identifier } ?? touches.sortedByIdentifier().first
    }

    private func swipeGesture(requiredFingers: Int, touches: [TouchPoint]) -> RecognizedGesture? {
        guard startTouches.count == requiredFingers, touches.count == requiredFingers else {
            return nil
        }

        let deltas = zip(startTouches.sortedByIdentifier(), touches.sortedByIdentifier()).map {
            (dx: $1.x - $0.x, dy: $1.y - $0.y)
        }
        let averageDX = deltas.map(\.dx).reduce(0, +) / Double(requiredFingers)
        let averageDY = deltas.map(\.dy).reduce(0, +) / Double(requiredFingers)

        if abs(averageDX) > abs(averageDY), abs(averageDX) > 0.18 {
            return averageDX > 0 ? .threeSwipeRight : .threeSwipeLeft
        }

        if abs(averageDY) > 0.18 {
            return averageDY > 0 ? .threeSwipeUp : .threeSwipeDown
        }

        return nil
    }

    private func oneFixedTap(touches: [TouchPoint], timestamp: TimeInterval) -> RecognizedGesture? {
        guard
            previousTouches.count == 2,
            touches.count == 1,
            let anchor = oneFixedTapAnchor,
            let movingTouch = oneFixedTapMovingTouch,
            timestamp - oneFixedTapTimestamp < 0.4
        else {
            return nil
        }

        let remainingTouch = touches[0]
        guard remainingTouch.identifier == anchor.identifier else {
            return nil
        }

        return movingTouch.x > anchor.x ? .oneFixRightTap : .oneFixLeftTap
    }

    private mutating func clearOneFixedTapTracking() {
        oneFixedTapTimestamp = 0
        oneFixedTapAnchor = nil
        oneFixedTapMovingTouch = nil
    }
}

private extension Array where Element == TouchPoint {
    func sortedByIdentifier() -> [TouchPoint] {
        sorted { $0.identifier < $1.identifier }
    }
}
