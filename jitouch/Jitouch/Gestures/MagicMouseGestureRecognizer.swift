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

        if let thumb = thumbGesture(touches: touches) {
            hasTriggered = true
            return thumb
        }

        if let vShape = vShape(touches: touches) {
            hasTriggered = true
            return vShape
        }

        if let slide = twoFixOneSlide(touches: touches) {
            hasTriggered = true
            return slide
        }

        if let pinch = pinchGesture(touches: touches) {
            hasTriggered = true
            return pinch
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
        let sorted = startTouches.sorted { $0.x < $1.x }
        let remainingIsLeft = sorted.first?.identifier == remainingTouch.identifier
        let averageX = startTouches.map(\.x).reduce(0, +) / Double(max(startTouches.count, 1))
        let isFar = abs(averageX - remainingTouch.x) > 0.22

        if remainingIsLeft {
            return isFar ? .indexFixMiddleFarTap : .indexFixMiddleNearTap
        }
        return isFar ? .middleFixIndexFarTap : .middleFixIndexNearTap
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
            return leftDelta < 0 ? .indexFixMiddleSlideOut : .indexFixMiddleSlideIn
        }

        if abs(rightDelta) > 0.12, abs(leftDelta) < 0.03 {
            return rightDelta > 0 ? .middleFixIndexSlideOut : .middleFixIndexSlideIn
        }

        return nil
    }

    private func twoFixOneSlide(touches: [TouchPoint]) -> RecognizedGesture? {
        guard startTouches.count == 3, touches.count == 3 else {
            return nil
        }

        let movement = movementClassification(startTouches: startTouches, touches: touches)
        guard movement.stationary.count == 2, movement.moving.count == 1 else {
            return nil
        }

        let moving = movement.moving[0]
        guard moving.distance > 0.14 else {
            return nil
        }

        if abs(moving.dx) > abs(moving.dy) {
            return moving.dx > 0 ? .twoFixOneSlideRight : .twoFixOneSlideLeft
        }
        return moving.dy > 0 ? .twoFixOneSlideUp : .twoFixOneSlideDown
    }

    private func pinchGesture(touches: [TouchPoint]) -> RecognizedGesture? {
        guard startTouches.count == 2, touches.count == 2 else {
            return nil
        }

        let startDistance = distance(startTouches[0], startTouches[1])
        let currentDistance = distance(touches[0], touches[1])
        guard startDistance > 0 else {
            return nil
        }

        let scale = currentDistance / startDistance
        if scale > 1.35 {
            return .pinchOut
        }
        if scale < 0.72 {
            return .pinchIn
        }
        return nil
    }

    private func thumbGesture(touches: [TouchPoint]) -> RecognizedGesture? {
        guard touches.count == 1, let touch = touches.first else {
            return nil
        }

        if touch.y < 0.22 || touch.y > 0.88 {
            return .thumb
        }
        return nil
    }

    private func vShape(touches: [TouchPoint]) -> RecognizedGesture? {
        guard touches.count >= 2 else {
            return nil
        }

        let sorted = touches.sorted { $0.x < $1.x }
        guard let left = sorted.first, let right = sorted.last else {
            return nil
        }

        if abs(left.x - right.x) > 0.34, abs(left.y - right.y) > 0.24 {
            return .vShape
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

    private func distance(_ lhs: TouchPoint, _ rhs: TouchPoint) -> Double {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func movementClassification(
        startTouches: [TouchPoint],
        touches: [TouchPoint]
    ) -> (stationary: [TouchMovement], moving: [TouchMovement]) {
        let movements = touches.compactMap { current -> TouchMovement? in
            guard let start = startTouches.first(where: { $0.identifier == current.identifier }) else {
                return nil
            }
            return TouchMovement(start: start, current: current)
        }
        return (
            stationary: movements.filter { $0.distance < 0.04 },
            moving: movements.filter { $0.distance >= 0.07 }
        )
    }
}

private struct TouchMovement {
    var start: TouchPoint
    var current: TouchPoint

    var dx: Double { current.x - start.x }
    var dy: Double { current.y - start.y }
    var distance: Double { hypot(dx, dy) }
}
