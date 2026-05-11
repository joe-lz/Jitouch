import Foundation

struct MagicMouseGestureRecognizer: GestureRecognizer {
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

        if previousTouches.count == 2, touches.isEmpty, timestamp - startTimestamp < 0.35 {
            hasTriggered = true
            return .middleClick
        }

        if previousTouches.count == 2, touches.count == 1, timestamp - startTimestamp < 0.45 {
            hasTriggered = true
            return fixedFingerTap(remainingTouch: touches[0])
        }

        if let slide = fixedFingerSlide(touches: touches) {
            hasTriggered = true
            return slide
        }

        if let swipe = threeFingerSwipe(touches: touches) {
            hasTriggered = true
            return swipe
        }

        return nil
    }

    mutating func reset() {
        previousTouches.removeAll()
        startTouches.removeAll()
        startTimestamp = 0
        hasTriggered = false
    }

    private func fixedFingerTap(remainingTouch: TouchPoint) -> RecognizedGesture {
        let averageX = startTouches.map(\.x).reduce(0, +) / Double(max(startTouches.count, 1))
        return abs(averageX - remainingTouch.x) > 0.22 ? .middleFixIndexFarTap : .middleFixIndexNearTap
    }

    private func fixedFingerSlide(touches: [TouchPoint]) -> RecognizedGesture? {
        guard startTouches.count == 2, touches.count == 2 else {
            return nil
        }

        let sortedStart = startTouches.sorted { $0.x < $1.x }
        let sortedNow = touches.sorted { $0.x < $1.x }
        let leftDelta = sortedNow[0].x - sortedStart[0].x
        let rightDelta = sortedNow[1].x - sortedStart[1].x

        if abs(leftDelta) > 0.12, abs(rightDelta) < 0.03 {
            return leftDelta < 0 ? .middleFixIndexSlideOut : .middleFixIndexSlideIn
        }

        if abs(rightDelta) > 0.12, abs(leftDelta) < 0.03 {
            return rightDelta > 0 ? .middleFixIndexSlideOut : .middleFixIndexSlideIn
        }

        return nil
    }

    private func threeFingerSwipe(touches: [TouchPoint]) -> RecognizedGesture? {
        guard startTouches.count == 3, touches.count == 3 else {
            return nil
        }

        let pairs = zip(startTouches.sorted { $0.identifier < $1.identifier }, touches.sorted { $0.identifier < $1.identifier })
        let deltas = pairs.map { (dx: $1.x - $0.x, dy: $1.y - $0.y) }
        let averageDX = deltas.map(\.dx).reduce(0, +) / 3.0
        let averageDY = deltas.map(\.dy).reduce(0, +) / 3.0

        if abs(averageDX) > abs(averageDY), abs(averageDX) > 0.16 {
            return averageDX > 0 ? .threeSwipeRight : .threeSwipeLeft
        }

        if abs(averageDY) > 0.16 {
            return averageDY > 0 ? .threeSwipeUp : .threeSwipeDown
        }

        return nil
    }
}
