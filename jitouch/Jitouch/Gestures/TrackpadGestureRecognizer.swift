import Foundation

struct TrackpadGestureRecognizer: GestureRecognizer {
    private var previousTouches: [TouchPoint] = []
    private var startTouches: [TouchPoint] = []
    private var startTimestamp: TimeInterval = 0
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

        if let tap = oneFixedTap(touches: touches, timestamp: timestamp) {
            hasTriggered = true
            return tap
        }

        return nil
    }

    mutating func reset() {
        previousTouches.removeAll()
        startTouches.removeAll()
        startTimestamp = 0
        hasTriggered = false
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
        guard startTouches.count == 1, previousTouches.count == 2, touches.count == 1, timestamp - startTimestamp < 0.4 else {
            return nil
        }

        let startX = startTouches[0].x
        let remainingX = touches[0].x
        return remainingX > startX ? .oneFixRightTap : .oneFixLeftTap
    }
}

private extension Array where Element == TouchPoint {
    func sortedByIdentifier() -> [TouchPoint] {
        sorted { $0.identifier < $1.identifier }
    }
}
