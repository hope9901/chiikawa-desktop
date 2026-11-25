import AppKit
import CoreGraphics

/// Represents a horizontal surface (either a monitor's desktop floor or the top edge of an OS window)
/// in overlay-local bottom-left coordinates (origin: bottom-left of the combined multi-monitor union rect).
public struct PlatformSegment: Equatable {
    public let id: String
    public let windowID: Int
    public let ownerName: String
    public let rawWindowMinX: Double
    public let rawWindowMaxX: Double
    public let windowBottomY: Double
    public var minX: Double
    public var maxX: Double
    public let y: Double
    public let isFloor: Bool

    public var width: Double { maxX - minX }
}

/// Polls macOS window geometry across ALL connected monitors and extracts walkable top edges
/// of visible windows plus each monitor's desktop floor.
public final class WindowTracker {
    private let rules: PhysicsAndWorldSpec.WindowDetectionRulesSpec
    private let pollInterval: TimeInterval
    private var lastPollTimestamp: TimeInterval = 0
    private(set) public var cachedPlatforms: [PlatformSegment] = []

    /// Union bounding rectangle of all connected screens in global AppKit coordinates (bottom-left of primary screen = 0,0).
    public static var virtualDesktopFrame: CGRect {
        let screens = NSScreen.screens
        guard let first = screens.first else {
            return CGRect(x: 0, y: 0, width: 1440, height: 900)
        }
        return screens.dropFirst().reduce(first.frame) { $0.union($1.frame) }
    }

    public init(spec: PhysicsAndWorldSpec) {
        self.rules = spec.windowDetectionRules
        self.pollInterval = spec.coordinateSystem.windowPollIntervalSeconds
        _ = pollPlatforms(force: true)
    }

    @discardableResult
    public func pollPlatforms(force: Bool = false) -> [PlatformSegment] {
        let now = ProcessInfo.processInfo.systemUptime
        if !force && (now - lastPollTimestamp) < pollInterval && !cachedPlatforms.isEmpty {
            return cachedPlatforms
        }
        lastPollTimestamp = now

        let screens = NSScreen.screens
        guard let primaryScreen = screens.first else { return cachedPlatforms }
        let primaryHeight = Double(primaryScreen.frame.height)
        let unionFrame = WindowTracker.virtualDesktopFrame
        let unionOriginX = Double(unionFrame.minX)
        let unionOriginY = Double(unionFrame.minY)

        var segments: [PlatformSegment] = []
        var monitorVisibleRects: [CGRect] = []

        // 1. Add a desktop floor segment for EACH connected monitor (accounting for its Dock & Menu Bar)
        for (idx, screen) in screens.enumerated() {
            let vis = screen.visibleFrame
            let localMinX = Double(vis.minX) - unionOriginX
            let localMaxX = Double(vis.maxX) - unionOriginX
            let localFloorY = max(0.0, Double(vis.minY) - unionOriginY)
            let localTopY = Double(vis.maxY) - unionOriginY

            monitorVisibleRects.append(CGRect(
                x: localMinX,
                y: localFloorY,
                width: localMaxX - localMinX,
                height: max(100.0, localTopY - localFloorY)
            ))

            segments.append(PlatformSegment(
                id: idx == 0 ? "floor" : "floor_\(idx)",
                windowID: 0,
                ownerName: "Desktop Floor \(idx + 1)",
                rawWindowMinX: localMinX,
                rawWindowMaxX: localMaxX,
                windowBottomY: localFloorY,
                minX: localMinX,
                maxX: localMaxX,
                y: localFloorY,
                isFloor: true
            ))
        }

        // 2. Query visible windows across all monitors via CoreGraphics (front-to-back order)
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            cachedPlatforms = segments
            return segments
        }

        var occludingRects: [CGRect] = []

        for info in windowList {
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  rules.allowedWindowLayers.contains(layer) else {
                continue
            }

            let ownerName = (info[kCGWindowOwnerName as String] as? String) ?? ""
            if rules.ignoredOwnerNames.contains(ownerName) {
                continue
            }

            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.1 {
                continue
            }

            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let cgX = boundsDict["X"] as? Double,
                  let cgY = boundsDict["Y"] as? Double,
                  let cgW = boundsDict["Width"] as? Double,
                  let cgH = boundsDict["Height"] as? Double else {
                continue
            }

            if cgW < rules.minWindowWidth || cgH < rules.minWindowHeight {
                continue
            }

            // Convert from CG global coordinates (top-left of primary screen = 0,0)
            // to AppKit global coordinates (bottom-left of primary screen = 0,0),
            // then to overlay-local coordinates (bottom-left of unionFrame = 0,0):
            let globalTopY = primaryHeight - cgY
            let globalBottomY = primaryHeight - (cgY + cgH)
            let topEdgeY = globalTopY - unionOriginY
            let bottomEdgeY = globalBottomY - unionOriginY
            let rawMinX = cgX - unionOriginX
            let rawMaxX = rawMinX + cgW

            let winMidX = (rawMinX + rawMaxX) * 0.5
            // Find the monitor that hosts this window's horizontal center (or overlaps it)
            guard let hostMonitor = monitorVisibleRects.first(where: { winMidX >= Double($0.minX) && winMidX <= Double($0.maxX) })
                ?? monitorVisibleRects.first(where: { rawMaxX > Double($0.minX) && rawMinX < Double($0.maxX) }) else {
                continue
            }

            let minX = max(Double(unionFrame.minX) - unionOriginX, rawMinX)
            let maxX = min(Double(unionFrame.maxX) - unionOriginX, rawMaxX)

            guard maxX - minX >= 48.0 else {
                continue
            }

            let windowRectBottomUp = CGRect(
                x: minX,
                y: bottomEdgeY,
                width: maxX - minX,
                height: cgH
            )

            let hostFloorY = Double(hostMonitor.minY)
            let hostCeilingY = Double(hostMonitor.maxY)

            if topEdgeY >= hostFloorY + 16.0 && topEdgeY <= (hostCeilingY - rules.minTopClearanceFromScreenTop) {
                let winNumber = (info[kCGWindowNumber as String] as? Int) ?? 0
                let baseSegment = PlatformSegment(
                    id: "win_\(winNumber)",
                    windowID: winNumber,
                    ownerName: ownerName,
                    rawWindowMinX: rawMinX,
                    rawWindowMaxX: rawMaxX,
                    windowBottomY: max(hostFloorY, bottomEdgeY),
                    minX: minX,
                    maxX: maxX,
                    y: topEdgeY,
                    isFloor: false
                )

                if rules.occludeLowerWindows {
                    let visibleSlices = sliceSegment(baseSegment, against: occludingRects)
                    segments.append(contentsOf: visibleSlices)
                } else {
                    segments.append(baseSegment)
                }
            }

            occludingRects.append(windowRectBottomUp)
        }

        cachedPlatforms = segments
        return segments
    }

    private func sliceSegment(_ segment: PlatformSegment, against occluders: [CGRect]) -> [PlatformSegment] {
        var intervals: [(Double, Double)] = [(segment.minX, segment.maxX)]

        for rect in occluders {
            if segment.y >= Double(rect.minY) - 2.0 && segment.y <= Double(rect.maxY) + 2.0 {
                let occMinX = Double(rect.minX)
                let occMaxX = Double(rect.maxX)
                var nextIntervals: [(Double, Double)] = []

                for (a, b) in intervals {
                    if occMaxX <= a || occMinX >= b {
                        nextIntervals.append((a, b))
                    } else {
                        if occMinX > a {
                            nextIntervals.append((a, occMinX))
                        }
                        if occMaxX < b {
                            nextIntervals.append((occMaxX, b))
                        }
                    }
                }
                intervals = nextIntervals
                if intervals.isEmpty { break }
            }
        }

        return intervals.enumerated().compactMap { idx, range in
            let width = range.1 - range.0
            guard width >= 48.0 else { return nil }
            return PlatformSegment(
                id: idx == 0 ? segment.id : "\(segment.id)_\(idx)",
                windowID: segment.windowID,
                ownerName: segment.ownerName,
                rawWindowMinX: segment.rawWindowMinX,
                rawWindowMaxX: segment.rawWindowMaxX,
                windowBottomY: segment.windowBottomY,
                minX: range.0,
                maxX: range.1,
                y: segment.y,
                isFloor: segment.isFloor
            )
        }
    }
}
