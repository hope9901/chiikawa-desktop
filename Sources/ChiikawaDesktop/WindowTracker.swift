import AppKit
import CoreGraphics

/// Represents a horizontal surface (either the desktop floor or the top edge of an OS window)
/// in normalized bottom-left coordinates (origin: bottom-left of main screen).
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

/// Polls macOS window geometry and extracts walkable top edges of visible windows plus the desktop floor.
public final class WindowTracker {
    private let rules: PhysicsAndWorldSpec.WindowDetectionRulesSpec
    private let pollInterval: TimeInterval
    private var lastPollTimestamp: TimeInterval = 0
    private(set) public var cachedPlatforms: [PlatformSegment] = []

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

        // IMPORTANT: In multi-monitor setups, NSScreen.main changes whenever focus moves to a second monitor!
        // CGWindowListCopyWindowInfo ALWAYS uses the Primary Screen (NSScreen.screens.first) top-left origin.
        // Therefore, we must ALWAYS use NSScreen.screens.first so coordinates never shift or push characters underground.
        guard let primaryScreen = NSScreen.screens.first else { return cachedPlatforms }
        let fullFrame = primaryScreen.frame
        let visibleFrame = primaryScreen.visibleFrame
        let screenHeight = Double(fullFrame.height)
        let screenMinX = Double(fullFrame.minX)
        let screenMaxX = Double(fullFrame.maxX)

        var segments: [PlatformSegment] = []

        // 1. Add the desktop floor (top of Dock / bottom of visible screen on the primary monitor)
        let floorY = max(0.0, Double(visibleFrame.minY - fullFrame.minY))
        let floorMinX = Double(visibleFrame.minX - fullFrame.minX)
        let floorMaxX = Double(visibleFrame.maxX - fullFrame.minX)
        let floorSegment = PlatformSegment(
            id: "floor",
            windowID: 0,
            ownerName: "Desktop Floor",
            rawWindowMinX: floorMinX,
            rawWindowMaxX: floorMaxX,
            windowBottomY: floorY,
            minX: floorMinX,
            maxX: floorMaxX,
            y: floorY,
            isFloor: true
        )
        segments.append(floorSegment)

        // 2. Query visible windows via CoreGraphics (front-to-back order)
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

            // Reject windows that have been moved completely onto another monitor (outside primary screen bounds)
            if (cgX + cgW) <= screenMinX || cgX >= screenMaxX || (cgY + cgH) <= 0.0 || cgY >= screenHeight {
                continue
            }

            // CGWindowBounds uses primary screen top-left origin: cgY is distance from top of primary screen.
            let topEdgeY = screenHeight - cgY
            let bottomEdgeY = screenHeight - (cgY + cgH)
            let rawMinX = cgX - screenMinX
            let rawMaxX = rawMinX + cgW
            let minX = max(floorMinX, rawMinX)
            let maxX = min(floorMaxX, rawMaxX)

            guard maxX - minX >= 48.0 else {
                continue
            }

            // Also ensure the window top edge lies within the primary monitor's vertical visible range
            guard topEdgeY >= floorSegment.y + 16.0 && topEdgeY <= Double(visibleFrame.maxY - fullFrame.minY) else {
                continue
            }

            let windowRectBottomUp = CGRect(
                x: minX,
                y: bottomEdgeY,
                width: maxX - minX,
                height: cgH
            )

            let clearanceFromTop = cgY
            if clearanceFromTop >= rules.minTopClearanceFromScreenTop {
                let winNumber = (info[kCGWindowNumber as String] as? Int) ?? 0
                let baseSegment = PlatformSegment(
                    id: "win_\(winNumber)",
                    windowID: winNumber,
                    ownerName: ownerName,
                    rawWindowMinX: rawMinX,
                    rawWindowMaxX: rawMaxX,
                    windowBottomY: max(floorSegment.y, bottomEdgeY),
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
