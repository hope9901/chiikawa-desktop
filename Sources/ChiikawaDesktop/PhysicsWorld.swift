import AppKit
import Foundation
import CoreGraphics

/// Evaluates platform landing, window-riding synchronization, screen/window boundary ejection,
/// and support checks using rules from `spec/physics_and_world.json`.
public final class PhysicsWorld {
    public let constants: PhysicsAndWorldSpec.PhysicsConstantsSpec
    public let jumpAndClimb: PhysicsAndWorldSpec.JumpAndClimbRulesSpec
    public let ridingRules: PhysicsAndWorldSpec.WindowRidingRulesSpec
    public let dimensions: PhysicsAndWorldSpec.CharacterDimensionsSpec

    public init(spec: PhysicsAndWorldSpec) {
        self.constants = spec.physicsConstants
        self.jumpAndClimb = spec.jumpAndClimbRules
        self.ridingRules = spec.windowRidingRules
        self.dimensions = spec.characterDimensions
    }

    /// Returns the usable screen area (excluding Dock and top Menu Bar) on the primary overlay monitor in bottom-left coordinates.
    public var usableScreenBounds: CGRect {
        guard let screen = NSScreen.screens.first else {
            return CGRect(x: 0, y: 0, width: 1440, height: 900)
        }
        let full = screen.frame
        let visible = screen.visibleFrame
        return CGRect(
            x: visible.minX - full.minX,
            y: max(0.0, visible.minY - full.minY),
            width: visible.width,
            height: visible.height
        )
    }

    /// Checks if the entire character body (width & height) at `(centerX, feetY)` fits inside the monitor's usable screen bounds.
    public func isCharacterBodyInsideScreen(
        centerX: Double,
        feetY: Double,
        charWidth: Double,
        charHeight: Double,
        usableBounds: CGRect
    ) -> Bool {
        let halfW = charWidth * 0.42
        let leftEdge = centerX - halfW
        let rightEdge = centerX + halfW
        let topEdge = feetY + charHeight * 0.92

        let screenMinX = Double(usableBounds.minX)
        let screenMaxX = Double(usableBounds.maxX)
        let screenMaxY = Double(usableBounds.maxY)
        let screenMinY = Double(usableBounds.minY) - 4.0

        return leftEdge >= screenMinX &&
               rightEdge <= screenMaxX &&
               topEdge <= screenMaxY &&
               feetY >= screenMinY
    }

    /// Checks if the character's standing footprint fits on the given platform segment without overhanging off the window edge.
    public func isCharacterInsidePlatformSegment(
        centerX: Double,
        charWidth: Double,
        segment: PlatformSegment
    ) -> Bool {
        let footHalfW = charWidth * 0.30
        return (centerX - footHalfW) >= segment.minX && (centerX + footHalfW) <= segment.maxX
    }

    /// Checks whether a falling character crossed or reached any valid platform segment between `previousY` and `nextY`.
    /// Only lands on a window if the character's body at that position fits inside the monitor screen bounds.
    public func findLandingPlatform(
        centerX: Double,
        previousY: Double,
        nextY: Double,
        charWidth: Double,
        charHeight: Double,
        platforms: [PlatformSegment]
    ) -> PlatformSegment? {
        let tolerance = constants.landingSnapTolerance
        let usable = usableScreenBounds
        var bestCandidate: PlatformSegment?

        for segment in platforms {
            guard isCharacterInsidePlatformSegment(centerX: centerX, charWidth: charWidth, segment: segment) else {
                continue
            }

            // If landing on a window (not floor), verify the character's head/body doesn't exceed the monitor top/sides
            if !segment.isFloor && ridingRules.requireFullCharacterBodyInsideScreen {
                if !isCharacterBodyInsideScreen(
                    centerX: centerX,
                    feetY: segment.y,
                    charWidth: charWidth,
                    charHeight: charHeight,
                    usableBounds: usable
                ) {
                    continue
                }
            }

            if previousY >= (segment.y - tolerance) && nextY <= (segment.y + 2.0) {
                if let currentBest = bestCandidate {
                    if segment.y > currentBest.y {
                        bestCandidate = segment
                    }
                } else {
                    bestCandidate = segment
                }
            }
        }
        return bestCandidate
    }

    /// Tracks a standing/walking character on its current platform (including moving windows).
    /// Returns the updated `(newX, newY, updatedSegment)` if still validly supported,
    /// or `nil` if the window closed, was occluded, or moved so the character would exceed window/monitor bounds (triggering free-fall).
    public func resolveStandingSupport(
        currentX: Double,
        currentY: Double,
        charWidth: Double,
        charHeight: Double,
        previousPlatform: PlatformSegment?,
        platforms: [PlatformSegment]
    ) -> (x: Double, y: Double, segment: PlatformSegment)? {
        let usable = usableScreenBounds

        // 1. If the character was riding a specific application window (windowID != 0),
        // track that window even if the user dragged it horizontally/vertically!
        if ridingRules.followMovingWindow,
           let prev = previousPlatform,
           !prev.isFloor,
           prev.windowID != 0 {
            let matchingWindowSegments = platforms.filter { $0.windowID == prev.windowID }
            if let firstMatch = matchingWindowSegments.first {
                let deltaX = firstMatch.rawWindowMinX - prev.rawWindowMinX
                let movedX = currentX + deltaX
                let movedY = firstMatch.y

                // Verify vertical jump isn't an unrelated teleport
                if abs(movedY - currentY) <= constants.windowTrackingMaxSnapDeltaY {
                    // Check if character's body would go outside monitor screen bounds (top/left/right/bottom)
                    if ridingRules.freeFallWhenOutOfScreenBounds &&
                        !isCharacterBodyInsideScreen(
                            centerX: movedX,
                            feetY: movedY,
                            charWidth: charWidth,
                            charHeight: charHeight,
                            usableBounds: usable
                        ) {
                        return nil // Eject into free-fall!
                    }

                    // Find the visible slice of this window that contains movedX
                    if let validSlice = matchingWindowSegments.first(where: {
                        isCharacterInsidePlatformSegment(centerX: movedX, charWidth: charWidth, segment: $0)
                    }) {
                        return (movedX, movedY, validSlice)
                    } else if ridingRules.freeFallWhenCharacterExceedsWindowEdge {
                        return nil // Window was occluded or character exceeded window edge -> free-fall!
                    }
                }
            }
        }

        // 2. Standard support check (floor or stationary platform beneath feet)
        let tolerance = constants.landingSnapTolerance
        if let segment = platforms.first(where: {
            isCharacterInsidePlatformSegment(centerX: currentX, charWidth: charWidth, segment: $0) &&
            abs($0.y - currentY) <= tolerance
        }) {
            if !segment.isFloor && ridingRules.freeFallWhenOutOfScreenBounds {
                if !isCharacterBodyInsideScreen(
                    centerX: currentX,
                    feetY: segment.y,
                    charWidth: charWidth,
                    charHeight: charHeight,
                    usableBounds: usable
                ) {
                    return nil
                }
            }
            return (currentX, segment.y, segment)
        }

        return nil
    }

    // MARK: - Small Step Jump & Window Edge Climb Detection

    /// Searches for a platform slightly higher than `currentY` (up to `maxStepJumpHeightRatio * charHeight`, ~half character height)
    /// in the direction the character is walking (`facingRight`), so the character can hop up onto it.
    public func findStepJumpTarget(
        currentX: Double,
        currentY: Double,
        facingRight: Bool,
        charWidth: Double,
        charHeight: Double,
        currentWindowID: Int?,
        platforms: [PlatformSegment]
    ) -> (segment: PlatformSegment, landingX: Double)? {
        guard jumpAndClimb.enableStepJump else { return nil }

        let minDeltaY = jumpAndClimb.minStepJumpHeightPoints
        let maxDeltaY = charHeight * jumpAndClimb.maxStepJumpHeightRatio
        let reach = jumpAndClimb.stepJumpHorizontalReach
        let footHalfW = charWidth * 0.32
        let usable = usableScreenBounds

        for seg in platforms where !seg.isFloor {
            if let curWin = currentWindowID, curWin != 0, seg.windowID == curWin {
                continue
            }
            let deltaY = seg.y - currentY
            guard deltaY >= minDeltaY && deltaY <= maxDeltaY else { continue }

            // Check if the character is approaching the left edge, right edge, or walking underneath this low ledge
            var candidateLandingX: Double?

            if facingRight {
                // Approaching left edge of upper platform OR already horizontally inside it
                let distToLeft = seg.minX - currentX
                if distToLeft >= -footHalfW && distToLeft <= reach {
                    candidateLandingX = min(seg.maxX - footHalfW, seg.minX + footHalfW + 8.0)
                } else if currentX >= seg.minX + footHalfW && currentX + reach <= seg.maxX - footHalfW {
                    candidateLandingX = currentX + reach * 0.8
                }
            } else {
                // Walking left: approaching right edge of upper platform OR already horizontally inside it
                let distToRight = currentX - seg.maxX
                if distToRight >= -footHalfW && distToRight <= reach {
                    candidateLandingX = max(seg.minX + footHalfW, seg.maxX - footHalfW - 8.0)
                } else if currentX - reach >= seg.minX + footHalfW && currentX <= seg.maxX - footHalfW {
                    candidateLandingX = currentX - reach * 0.8
                }
            }

            if let landX = candidateLandingX,
               isCharacterInsidePlatformSegment(centerX: landX, charWidth: charWidth, segment: seg),
               isCharacterBodyInsideScreen(centerX: landX, feetY: seg.y, charWidth: charWidth, charHeight: charHeight, usableBounds: usable) {
                return (seg, landX)
            }
        }
        return nil
    }

    /// Searches for a taller window whose left (`minX`) or right (`maxX`) vertical side edge is right in front of the walking character,
    /// allowing the character to grab the edge of the window and climb up to its top surface.
    public func findClimbableWindowEdge(
        currentX: Double,
        currentY: Double,
        facingRight: Bool,
        charWidth: Double,
        charHeight: Double,
        currentWindowID: Int?,
        platforms: [PlatformSegment]
    ) -> (segment: PlatformSegment, climbOnLeftEdge: Bool, edgeX: Double)? {
        guard jumpAndClimb.enableWindowEdgeClimb else { return nil }

        let minClimbDeltaY = charHeight * jumpAndClimb.maxStepJumpHeightRatio
        let triggerDist = jumpAndClimb.climbTriggerDistanceX
        let footHalfW = charWidth * 0.32
        let usable = usableScreenBounds

        for seg in platforms where !seg.isFloor && seg.windowID != 0 {
            if let curWin = currentWindowID, curWin == seg.windowID {
                continue
            }
            let climbHeight = seg.y - currentY
            guard climbHeight > minClimbDeltaY else { continue }

            // Ensure the window's vertical side actually extends down to (or near) the character's current Y level
            guard currentY >= (seg.windowBottomY - 24.0) && currentY < (seg.y - 20.0) else {
                continue
            }

            // Can climb the LEFT vertical edge (minX) if near minX (especially when walking right into it, or reaching its X)
            let distToLeftEdge = abs(currentX - seg.minX)
            if distToLeftEdge <= triggerDist && abs(seg.minX - seg.rawWindowMinX) < 8.0 {
                let topLandingX = min(seg.maxX - footHalfW, seg.minX + footHalfW + 6.0)
                if isCharacterBodyInsideScreen(centerX: topLandingX, feetY: seg.y, charWidth: charWidth, charHeight: charHeight, usableBounds: usable) {
                    return (seg, true, seg.minX)
                }
            }

            // Can climb the RIGHT vertical edge (maxX) if near maxX
            let distToRightEdge = abs(currentX - seg.maxX)
            if distToRightEdge <= triggerDist && abs(seg.maxX - seg.rawWindowMaxX) < 8.0 {
                let topLandingX = max(seg.minX + footHalfW, seg.maxX - footHalfW - 6.0)
                if isCharacterBodyInsideScreen(centerX: topLandingX, feetY: seg.y, charWidth: charWidth, charHeight: charHeight, usableBounds: usable) {
                    return (seg, false, seg.maxX)
                }
            }
        }
        return nil
    }
}
