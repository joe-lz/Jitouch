import Foundation

struct TrackpadGestureRecognizer: GestureRecognizer {
    private var previousTouches: [TouchPoint] = []
    private var startTouches: [TouchPoint] = []
    private var startTimestamp: TimeInterval = 0
    private var oneFixedTapTimestamp: TimeInterval = 0
    private var oneFixedTapAnchor: TouchPoint?
    private var oneFixedTapMovingTouch: TouchPoint?
    private var oneFixedTapWasCancelled = false
    private var twoFixDoubleTapTimestamp: TimeInterval = 0
    private var twoFixDoubleTapCandidate: RecognizedGesture?
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
        updateOneFixedTapCancellation(touches: touches, timestamp: timestamp)
        if let tap = oneFixedTap(touches: touches, timestamp: timestamp) {
            clearOneFixedTapTracking()
            return tap
        }

        if let doubleTap = twoFixDoubleTap(touches: touches, timestamp: timestamp) {
            clearTwoFixDoubleTapTracking()
            return doubleTap
        }
        updateTwoFixDoubleTapTracking(touches: touches, timestamp: timestamp)

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

        if let swipe = swipeGesture(requiredFingers: 4, touches: touches) {
            hasTriggered = true
            return swipe
        }

        if let pinch = pinchGesture(requiredFingers: 3, touches: touches) {
            hasTriggered = true
            return pinch
        }

        if let slide = twoFixOneSlide(touches: touches) {
            hasTriggered = true
            return slide
        }

        if let slide = oneFixTwoSlide(touches: touches) {
            hasTriggered = true
            return slide
        }

        if let slide = oneFixOneSlide(touches: touches) {
            hasTriggered = true
            return slide
        }

        if let roll = fingerRoll(touches: touches) {
            hasTriggered = true
            return roll
        }

        if let sideScroll = sideScroll(touches: touches) {
            hasTriggered = true
            return sideScroll
        }

        return nil
    }

    mutating func reset() {
        previousTouches.removeAll()
        startTouches.removeAll()
        startTimestamp = 0
        clearOneFixedTapTracking()
        clearTwoFixDoubleTapTracking()
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
        oneFixedTapWasCancelled = false
    }

    private mutating func updateOneFixedTapCancellation(touches: [TouchPoint], timestamp: TimeInterval) {
        guard
            oneFixedTapWasCancelled == false,
            touches.count == 2,
            let anchor = oneFixedTapAnchor,
            let movingTouch = oneFixedTapMovingTouch,
            let currentAnchor = touches.first(where: { $0.identifier == anchor.identifier }),
            let currentMovingTouch = touches.first(where: { $0.identifier == movingTouch.identifier })
        else {
            return
        }

        let anchorDX = currentAnchor.x - anchor.x
        let anchorDY = currentAnchor.y - anchor.y
        let movingDX = currentMovingTouch.x - movingTouch.x
        let movingDY = currentMovingTouch.y - movingTouch.y
        let anchorDistance = hypot(anchorDX, anchorDY)
        let movingDistance = hypot(movingDX, movingDY)
        let averageVerticalMovement = (abs(anchorDY) + abs(movingDY)) / 2
        let averageHorizontalMovement = (abs(anchorDX) + abs(movingDX)) / 2
        let isTwoFingerVerticalScroll = anchorDY.sign == movingDY.sign
            && averageVerticalMovement > 0.035
            && averageVerticalMovement > averageHorizontalMovement * 1.5

        if anchorDistance > 0.045 || movingDistance > 0.09 || isTwoFingerVerticalScroll || timestamp - oneFixedTapTimestamp > 0.28 {
            oneFixedTapWasCancelled = true
        }
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
            if requiredFingers == 4 {
                return averageDX > 0 ? .fourSwipeRight : .fourSwipeLeft
            }
            return averageDX > 0 ? .threeSwipeRight : .threeSwipeLeft
        }

        if abs(averageDY) > 0.18 {
            if requiredFingers == 4 {
                return averageDY > 0 ? .fourSwipeUp : .fourSwipeDown
            }
            return averageDY > 0 ? .threeSwipeUp : .threeSwipeDown
        }

        return nil
    }

    private func pinchGesture(requiredFingers: Int, touches: [TouchPoint]) -> RecognizedGesture? {
        guard startTouches.count == requiredFingers, touches.count == requiredFingers else {
            return nil
        }

        let startDistance = averageDistanceFromCenter(startTouches)
        let currentDistance = averageDistanceFromCenter(touches)
        guard startDistance > 0 else {
            return nil
        }

        let scale = currentDistance / startDistance
        if scale > 1.28 {
            return .threeFingerPinchOut
        }
        if scale < 0.78 {
            return .threeFingerPinchIn
        }
        return nil
    }

    private func oneFixOneSlide(touches: [TouchPoint]) -> RecognizedGesture? {
        guard startTouches.count == 2, touches.count == 2 else {
            return nil
        }

        let movement = movementClassification(startTouches: startTouches, touches: touches)
        guard movement.stationary.count == 1, movement.moving.count == 1, movement.moving[0].distance > 0.18 else {
            return nil
        }
        return .oneFixOneSlide
    }

    private func oneFixTwoSlide(touches: [TouchPoint]) -> RecognizedGesture? {
        guard startTouches.count == 3, touches.count == 3 else {
            return nil
        }

        let movement = movementClassification(startTouches: startTouches, touches: touches)
        guard movement.stationary.count == 1, movement.moving.count == 2 else {
            return nil
        }

        let averageDX = movement.moving.map(\.dx).reduce(0, +) / 2
        let averageDY = movement.moving.map(\.dy).reduce(0, +) / 2
        guard abs(averageDY) > abs(averageDX), abs(averageDY) > 0.16 else {
            return nil
        }

        let anchorPressed = movement.stationary[0].current.size > movement.stationary[0].start.size * 1.35
        if averageDY > 0 {
            return anchorPressed ? .oneFixPressTwoSlideUp : .oneFixTwoSlideUp
        }
        return anchorPressed ? .oneFixPressTwoSlideDown : .oneFixTwoSlideDown
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
        guard moving.distance > 0.16 else {
            return nil
        }

        if abs(moving.dx) > abs(moving.dy) {
            return moving.dx > 0 ? .twoFixOneSlideRight : .twoFixOneSlideLeft
        }
        return moving.dy > 0 ? .twoFixOneSlideUp : .twoFixOneSlideDown
    }

    private func fingerRoll(touches: [TouchPoint]) -> RecognizedGesture? {
        guard startTouches.count == 4, touches.count == 4 else {
            return nil
        }

        let sortedStart = startTouches.sortedByX()
        let sortedNow = touches.sortedByX()
        let firstDelta = sortedNow[0].y - sortedStart[0].y
        let lastDelta = sortedNow[3].y - sortedStart[3].y

        if firstDelta > 0.12, lastDelta < -0.12 {
            return .pinkyToIndex
        }
        if firstDelta < -0.12, lastDelta > 0.12 {
            return .indexToPinky
        }
        return nil
    }

    private func sideScroll(touches: [TouchPoint]) -> RecognizedGesture? {
        guard startTouches.count == 2, touches.count == 2 else {
            return nil
        }

        let startX = startTouches.map(\.x)
        let currentY = touches.map(\.y).reduce(0, +) / 2
        let startY = startTouches.map(\.y).reduce(0, +) / 2
        guard abs(currentY - startY) > 0.08 else {
            return nil
        }

        if (startX.min() ?? 1) < 0.08 {
            return .leftSideScroll
        }
        if (startX.max() ?? 0) > 0.92 {
            return .rightSideScroll
        }
        return nil
    }

    private func oneFixedTap(touches: [TouchPoint], timestamp: TimeInterval) -> RecognizedGesture? {
        guard
            previousTouches.count == 2,
            touches.count == 1,
            let anchor = oneFixedTapAnchor,
            let movingTouch = oneFixedTapMovingTouch,
            oneFixedTapWasCancelled == false,
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
        oneFixedTapWasCancelled = false
    }

    private mutating func updateTwoFixDoubleTapTracking(touches: [TouchPoint], timestamp: TimeInterval) {
        guard previousTouches.count == 3, touches.count == 2 else {
            return
        }

        let sorted = previousTouches.sortedByX()
        guard let missing = sorted.first(where: { previous in
            !touches.contains(where: { $0.identifier == previous.identifier })
        }) else {
            return
        }

        let index = sorted.firstIndex(of: missing) ?? 0
        let candidate: RecognizedGesture
        switch index {
        case 0:
            candidate = .twoFixIndexDoubleTap
        case 1:
            candidate = .twoFixMiddleDoubleTap
        default:
            candidate = .twoFixRingDoubleTap
        }

        if twoFixDoubleTapCandidate == nil || timestamp - twoFixDoubleTapTimestamp > 0.65 {
            twoFixDoubleTapCandidate = candidate
            twoFixDoubleTapTimestamp = timestamp
        }
    }

    private func twoFixDoubleTap(touches: [TouchPoint], timestamp: TimeInterval) -> RecognizedGesture? {
        guard
            previousTouches.count == 3,
            touches.count == 2,
            let candidate = twoFixDoubleTapCandidate,
            timestamp - twoFixDoubleTapTimestamp < 0.65
        else {
            return nil
        }

        return candidate
    }

    private mutating func clearTwoFixDoubleTapTracking() {
        twoFixDoubleTapTimestamp = 0
        twoFixDoubleTapCandidate = nil
    }

    private func averageDistanceFromCenter(_ touches: [TouchPoint]) -> Double {
        let centerX = touches.map(\.x).reduce(0, +) / Double(touches.count)
        let centerY = touches.map(\.y).reduce(0, +) / Double(touches.count)
        return touches
            .map { hypot($0.x - centerX, $0.y - centerY) }
            .reduce(0, +) / Double(touches.count)
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
            stationary: movements.filter { $0.distance < 0.045 },
            moving: movements.filter { $0.distance >= 0.075 }
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

private extension Array where Element == TouchPoint {
    func sortedByIdentifier() -> [TouchPoint] {
        sorted { $0.identifier < $1.identifier }
    }

    func sortedByX() -> [TouchPoint] {
        sorted { $0.x < $1.x }
    }
}
