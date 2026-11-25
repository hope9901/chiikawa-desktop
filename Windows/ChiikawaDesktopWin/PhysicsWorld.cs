using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;

namespace ChiikawaDesktopWin;

/// Evaluates platform landing, window-riding synchronization, screen/window boundary ejection,
/// small-step jumping, and window side-edge climbing using rules from spec/physics_and_world.json.
public sealed class PhysicsWorld
{
    public PhysicsAndWorldSpec.PhysicsConstantsSpec Constants { get; }
    public PhysicsAndWorldSpec.JumpAndClimbRulesSpec JumpAndClimb { get; }
    public PhysicsAndWorldSpec.WindowRidingRulesSpec RidingRules { get; }
    public PhysicsAndWorldSpec.CharacterDimensionsSpec Dimensions { get; }

    public PhysicsWorld(PhysicsAndWorldSpec spec)
    {
        Constants = spec.PhysicsConstants;
        JumpAndClimb = spec.JumpAndClimbRules;
        RidingRules = spec.WindowRidingRules;
        Dimensions = spec.CharacterDimensions;
    }

    /// Returns the combined virtual desktop area across all connected monitors in bottom-left coordinates.
    public Rect UsableScreenBounds =>
        new(0, 0, SystemParameters.VirtualScreenWidth, SystemParameters.VirtualScreenHeight);

    public bool IsCharacterBodyInsideScreen(
        double centerX,
        double feetY,
        double charWidth,
        double charHeight,
        Rect usableBounds)
    {
        double halfW = charWidth * 0.42;
        double leftEdge = centerX - halfW;
        double rightEdge = centerX + halfW;
        double topEdge = feetY + charHeight * 0.92;

        double screenMinX = usableBounds.Left;
        double screenMaxX = usableBounds.Right;
        double screenMinY = usableBounds.Top - 4.0;
        double screenMaxY = usableBounds.Bottom;

        return leftEdge >= screenMinX &&
               rightEdge <= screenMaxX &&
               topEdge <= screenMaxY &&
               feetY >= screenMinY;
    }

    public bool IsCharacterInsidePlatformSegment(double centerX, double charWidth, PlatformSegment segment)
    {
        double footHalfW = charWidth * 0.30;
        return (centerX - footHalfW) >= segment.MinX && (centerX + footHalfW) <= segment.MaxX;
    }

    public PlatformSegment? FindLandingPlatform(
        double centerX,
        double previousY,
        double nextY,
        double charWidth,
        double charHeight,
        List<PlatformSegment> platforms)
    {
        double tolerance = Constants.LandingSnapTolerance;
        Rect usable = UsableScreenBounds;
        PlatformSegment? bestCandidate = null;

        foreach (var segment in platforms)
        {
            if (!IsCharacterInsidePlatformSegment(centerX, charWidth, segment))
                continue;

            if (!segment.IsFloor && RidingRules.RequireFullCharacterBodyInsideScreen)
            {
                if (!IsCharacterBodyInsideScreen(centerX, segment.Y, charWidth, charHeight, usable))
                    continue;
            }

            if (previousY >= (segment.Y - tolerance) && nextY <= (segment.Y + 2.0))
            {
                if (bestCandidate == null || segment.Y > bestCandidate.Y)
                {
                    bestCandidate = segment;
                }
            }
        }
        return bestCandidate;
    }

    public (double X, double Y, PlatformSegment Segment)? ResolveStandingSupport(
        double currentX,
        double currentY,
        double charWidth,
        double charHeight,
        PlatformSegment? previousPlatform,
        List<PlatformSegment> platforms)
    {
        Rect usable = UsableScreenBounds;

        if (RidingRules.FollowMovingWindow &&
            previousPlatform is { IsFloor: false, WindowID: not 0 } prev)
        {
            var matching = platforms.Where(p => p.WindowID == prev.WindowID).ToList();
            if (matching.Count > 0)
            {
                var firstMatch = matching[0];
                double deltaX = firstMatch.RawWindowMinX - prev.RawWindowMinX;
                double movedX = currentX + deltaX;
                double movedY = firstMatch.Y;

                if (Math.Abs(movedY - currentY) <= Constants.WindowTrackingMaxSnapDeltaY)
                {
                    if (RidingRules.FreeFallWhenOutOfScreenBounds &&
                        !IsCharacterBodyInsideScreen(movedX, movedY, charWidth, charHeight, usable))
                    {
                        return null;
                    }

                    var validSlice = matching.FirstOrDefault(s => IsCharacterInsidePlatformSegment(movedX, charWidth, s));
                    if (validSlice != null)
                    {
                        return (movedX, movedY, validSlice);
                    }
                    if (RidingRules.FreeFallWhenCharacterExceedsWindowEdge)
                    {
                        return null;
                    }
                }
            }
        }

        double tolerance = Constants.LandingSnapTolerance;
        var stationary = platforms.FirstOrDefault(s =>
            IsCharacterInsidePlatformSegment(currentX, charWidth, s) &&
            Math.Abs(s.Y - currentY) <= tolerance);

        if (stationary != null)
        {
            if (!stationary.IsFloor && RidingRules.FreeFallWhenOutOfScreenBounds &&
                !IsCharacterBodyInsideScreen(currentX, stationary.Y, charWidth, charHeight, usable))
            {
                return null;
            }
            return (currentX, stationary.Y, stationary);
        }

        return null;
    }

    public (PlatformSegment Segment, double LandingX)? FindStepJumpTarget(
        double currentX,
        double currentY,
        bool facingRight,
        double charWidth,
        double charHeight,
        int? currentWindowID,
        List<PlatformSegment> platforms)
    {
        if (!JumpAndClimb.EnableStepJump) return null;

        double minDeltaY = JumpAndClimb.MinStepJumpHeightPoints;
        double maxDeltaY = charHeight * JumpAndClimb.MaxStepJumpHeightRatio;
        double reach = JumpAndClimb.StepJumpHorizontalReach;
        double footHalfW = charWidth * 0.32;
        Rect usable = UsableScreenBounds;

        foreach (var seg in platforms)
        {
            if (seg.IsFloor) continue;
            if (currentWindowID is > 0 && seg.WindowID == currentWindowID.Value) continue;

            double deltaY = seg.Y - currentY;
            if (deltaY < minDeltaY || deltaY > maxDeltaY) continue;

            double? candidateLandingX = null;
            if (facingRight)
            {
                double distToLeft = seg.MinX - currentX;
                if (distToLeft >= -footHalfW && distToLeft <= reach)
                    candidateLandingX = Math.Min(seg.MaxX - footHalfW, seg.MinX + footHalfW + 8.0);
                else if (currentX >= seg.MinX + footHalfW && currentX + reach <= seg.MaxX - footHalfW)
                    candidateLandingX = currentX + reach * 0.8;
            }
            else
            {
                double distToRight = currentX - seg.MaxX;
                if (distToRight >= -footHalfW && distToRight <= reach)
                    candidateLandingX = Math.Max(seg.MinX + footHalfW, seg.MaxX - footHalfW - 8.0);
                else if (currentX - reach >= seg.MinX + footHalfW && currentX <= seg.MaxX - footHalfW)
                    candidateLandingX = currentX - reach * 0.8;
            }

            if (candidateLandingX is double landX &&
                IsCharacterInsidePlatformSegment(landX, charWidth, seg) &&
                IsCharacterBodyInsideScreen(landX, seg.Y, charWidth, charHeight, usable))
            {
                return (seg, landX);
            }
        }
        return null;
    }

    public (PlatformSegment Segment, bool ClimbOnLeftEdge, double EdgeX)? FindClimbableWindowEdge(
        double currentX,
        double currentY,
        bool facingRight,
        double charWidth,
        double charHeight,
        int? currentWindowID,
        List<PlatformSegment> platforms)
    {
        if (!JumpAndClimb.EnableWindowEdgeClimb) return null;

        double minClimbDeltaY = charHeight * JumpAndClimb.MaxStepJumpHeightRatio;
        double triggerDist = JumpAndClimb.ClimbTriggerDistanceX;
        double footHalfW = charWidth * 0.32;
        Rect usable = UsableScreenBounds;

        foreach (var seg in platforms)
        {
            if (seg.IsFloor || seg.WindowID == 0) continue;
            if (currentWindowID is > 0 && seg.WindowID == currentWindowID.Value) continue;

            double climbHeight = seg.Y - currentY;
            if (climbHeight <= minClimbDeltaY) continue;
            if (currentY < (seg.WindowBottomY - 24.0) || currentY >= (seg.Y - 20.0)) continue;

            if (Math.Abs(currentX - seg.MinX) <= triggerDist && Math.Abs(seg.MinX - seg.RawWindowMinX) < 8.0)
            {
                double topLandingX = Math.Min(seg.MaxX - footHalfW, seg.MinX + footHalfW + 6.0);
                if (IsCharacterBodyInsideScreen(topLandingX, seg.Y, charWidth, charHeight, usable))
                    return (seg, true, seg.MinX);
            }

            if (Math.Abs(currentX - seg.MaxX) <= triggerDist && Math.Abs(seg.MaxX - seg.RawWindowMaxX) < 8.0)
            {
                double topLandingX = Math.Max(seg.MinX + footHalfW, seg.MaxX - footHalfW - 6.0);
                if (IsCharacterBodyInsideScreen(topLandingX, seg.Y, charWidth, charHeight, usable))
                    return (seg, false, seg.MaxX);
            }
        }
        return null;
    }
}
