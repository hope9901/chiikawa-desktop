import Foundation
import CoreGraphics

public enum CharacterStateID: String {
    case idle = "IDLE"
    case walk = "WALK"
    case jumpStep = "JUMP_STEP"
    case climbWall = "CLIMB_WALL"
    case climbRest = "CLIMB_REST"
    case cryClick = "CRY_CLICK"
    case draggedStruggle = "DRAGGED_STRUGGLE"
    case fall = "FALL"
    case fallFromGrab = "FALL_FROM_GRAB"
    case tumble = "TUMBLE"
}

public final class CharacterEntity {
    public let instanceID: UUID = UUID()
    public let profile: CharacterFSMSpec.CharacterProfileSpec
    private let fsmSpec: CharacterFSMSpec
    private let physics: PhysicsWorld

    // Position in normalized bottom-left coordinates (x: center X of feet, y: bottom Y of feet)
    public var x: Double
    public var y: Double
    public var vx: Double = 0.0
    public var vy: Double = 0.0
    public var facingRight: Bool = true
    public var scaleFactor: Double = 1.0

    public private(set) var state: CharacterStateID
    public private(set) var stateElapsed: Double = 0.0
    public private(set) var targetStateDuration: Double = 2.5
    public private(set) var currentPlatform: PlatformSegment?

    // Small Step Jump state tracking
    private var jumpStartX: Double = 0.0
    private var jumpStartY: Double = 0.0
    private var jumpTargetX: Double = 0.0
    private var jumpTargetY: Double = 0.0
    private var jumpTargetPlatform: PlatformSegment?

    // Window Side-Edge Climb state tracking
    public private(set) var climbingWindowID: Int = 0
    public private(set) var climbingOnLeftEdge: Bool = true
    private var climbDistanceSinceRest: Double = 0.0
    private var climbTotalHeight: Double = 0.0
    private var climbActionCooldown: Double = 0.0
    // Per-window decision memory so a character doesn't re-roll every frame and tracks declined windows
    private var ignoredWindowCooldowns: [Int: Double] = [:]

    // Mouse interaction tracking
    public private(set) var isMousePressed: Bool = false
    private var mousePressOrigin: CGPoint = .zero
    private var lastMousePosition: CGPoint = .zero
    private var lastMouseVelocityX: Double = 0.0

    // Speech bubble effects
    public private(set) var activeSpeechText: String?
    private var speechTimer: Double = 0.0

    // Animation phase counter
    public private(set) var animPhase: Double = 0.0

    public init(
        profile: CharacterFSMSpec.CharacterProfileSpec,
        fsmSpec: CharacterFSMSpec,
        physics: PhysicsWorld,
        startX: Double,
        startY: Double,
        scaleFactor: Double = 1.0
    ) {
        self.profile = profile
        self.fsmSpec = fsmSpec
        self.physics = physics
        self.x = startX
        self.y = startY
        self.scaleFactor = scaleFactor
        self.state = CharacterStateID(rawValue: fsmSpec.initialState) ?? .fall
        self.facingRight = Bool.random()
        transition(to: self.state)
    }

    public var width: Double {
        physics.dimensions.width * scaleFactor
    }

    public var height: Double {
        physics.dimensions.height * scaleFactor
    }

    var spriteRenderScale: Double {
        if state == .cryClick && profile.playsSongOnClick {
            return profile.songSpriteScale
        }
        return profile.baseSpriteScale
    }

    private var spriteBoundsHeight: Double {
        height * profile.heightMultiplier
    }

    /// Bounding box in bottom-left screen coordinates for hit-testing
    public var hitboxRect: CGRect {
        let pad = physics.dimensions.hitboxPadding
        let w = width * spriteRenderScale + pad * 2.0
        let h = spriteBoundsHeight * spriteRenderScale + pad * 2.0
        return CGRect(x: x - w * 0.5, y: y - pad, width: w, height: h)
    }

    /// Expanded bounding box including speech bubble / tears / flailing limbs for dirty-rect redrawing
    public var dirtyRect: CGRect {
        let margin = physics.dimensions.dirtyRectMargin * max(1.0, scaleFactor)
        let w = width * spriteRenderScale + margin * 2.2
        let h = spriteBoundsHeight * spriteRenderScale + margin * 2.4
        return CGRect(x: x - w * 0.5, y: y - margin * 0.6, width: w, height: h)
    }

    public var isHighFrequencyState: Bool {
        switch state {
        case .draggedStruggle, .fall, .fallFromGrab, .tumble, .cryClick, .jumpStep, .climbWall, .climbRest:
            return true
        case .walk, .idle:
            if let plat = currentPlatform, !plat.isFloor {
                return true
            }
            return false
        }
    }

    // MARK: - FSM Update

    public func update(
        dt: Double,
        platforms: [PlatformSegment],
        screenBounds: CGRect,
        wanderingEnabled: Bool
    ) {
        stateElapsed += dt
        animPhase += dt

        if speechTimer > 0 {
            speechTimer -= dt
            if speechTimer <= 0 {
                activeSpeechText = nil
            }
        }

        if climbActionCooldown > 0 {
            climbActionCooldown -= dt
        }

        if !ignoredWindowCooldowns.isEmpty {
            for (winID, remaining) in ignoredWindowCooldowns {
                let nextRemaining = remaining - dt
                if nextRemaining <= 0 {
                    ignoredWindowCooldowns.removeValue(forKey: winID)
                } else {
                    ignoredWindowCooldowns[winID] = nextRemaining
                }
            }
        }

        let timings = fsmSpec.interactionTimings
        let usableBounds = physics.usableScreenBounds
        let monitorBounds = physics.usableMonitorBounds(atX: x)
        let halfW = width * 0.42
        let effectiveH = spriteBoundsHeight
        let minScreenX = Double(usableBounds.minX) + halfW
        let maxScreenX = Double(usableBounds.maxX) - halfW
        let maxScreenY = Double(monitorBounds.maxY) - effectiveH * 0.92
        let activeFloorSegment = platforms.first(where: { $0.isFloor && x >= $0.minX && x <= $0.maxX })
            ?? platforms.first(where: { $0.isFloor })
        let floorY = max(0.0, activeFloorSegment?.y ?? Double(monitorBounds.minY))

        // Hard safety guard: if y somehow dropped below floorY (e.g., monitor reconfiguration), snap back to floor
        if physics.ridingRules.hardFloorClampEnabled && y < floorY - 2.0 && state != .fall && state != .fallFromGrab {
            y = floorY
        }

        switch state {
        case .idle:
            vx = 0
            vy = 0
            if let resolved = physics.resolveStandingSupport(
                currentX: x,
                currentY: y,
                charWidth: width,
                charHeight: height,
                previousPlatform: currentPlatform,
                platforms: platforms
            ) {
                x = resolved.x
                y = resolved.y
                currentPlatform = resolved.segment
            } else {
                x = min(max(x, minScreenX), maxScreenX)
                y = max(floorY, min(y, maxScreenY))
                currentPlatform = nil
                transition(to: .fall)
                return
            }

            if wanderingEnabled && stateElapsed >= timings.idleMinDurationSeconds && stateElapsed >= targetStateDuration {
                facingRight = Bool.random()
                transition(to: .walk)
            }

        case .walk:
            if !wanderingEnabled {
                transition(to: .idle)
                return
            }

            guard let resolved = physics.resolveStandingSupport(
                currentX: x,
                currentY: y,
                charWidth: width,
                charHeight: height,
                previousPlatform: currentPlatform,
                platforms: platforms
            ) else {
                x = min(max(x, minScreenX), maxScreenX)
                y = max(floorY, min(y, maxScreenY))
                currentPlatform = nil
                transition(to: .fall)
                return
            }

            x = resolved.x
            y = resolved.y
            let support = resolved.segment
            currentPlatform = support

            // 1. Check if there is a small step/ledge ahead (up to ~0.55x character height) to hop onto!
            if climbActionCooldown <= 0,
               let stepTarget = physics.findStepJumpTarget(
                   currentX: x,
                   currentY: y,
                   facingRight: facingRight,
                   charWidth: width,
                   charHeight: height,
                   currentWindowID: support.windowID,
                   platforms: platforms
               ),
               ignoredWindowCooldowns[stepTarget.segment.windowID] == nil {
                if Double.random(in: 0...1) < physics.jumpAndClimb.stepJumpProbability {
                    startStepJump(to: stepTarget.segment, landingX: stepTarget.landingX)
                    return
                } else {
                    // Declined to jump onto this window -> ignore this window for decisionCooldownSeconds so character walks past it
                    ignoredWindowCooldowns[stepTarget.segment.windowID] = physics.jumpAndClimb.decisionCooldownSeconds
                }
            }

            // 2. Check if the character reached the left/right vertical side edge of a taller window to climb!
            if climbActionCooldown <= 0,
               let climbTarget = physics.findClimbableWindowEdge(
                   currentX: x,
                   currentY: y,
                   facingRight: facingRight,
                   charWidth: width,
                   charHeight: height,
                   currentWindowID: support.windowID,
                   platforms: platforms
               ),
               ignoredWindowCooldowns[climbTarget.segment.windowID] == nil {
                if Double.random(in: 0...1) < physics.jumpAndClimb.climbProbability {
                    startWindowClimb(target: climbTarget.segment, onLeftEdge: climbTarget.climbOnLeftEdge, edgeX: climbTarget.edgeX)
                    return
                } else {
                    // Declined to climb this window -> ignore this window for decisionCooldownSeconds so character walks right past it
                    ignoredWindowCooldowns[climbTarget.segment.windowID] = physics.jumpAndClimb.decisionCooldownSeconds
                }
            }

            let speed = physics.constants.walkSpeed
            vx = facingRight ? speed : -speed
            let nextX = x + vx * dt

            let footHalfW = width * 0.30
            let segMinX = max(minScreenX, support.minX + footHalfW)
            let segMaxX = min(maxScreenX, support.maxX - footHalfW)

            if segMinX >= segMaxX {
                x = min(max(x, minScreenX), maxScreenX)
                currentPlatform = nil
                transition(to: .fall)
                return
            }

            if nextX <= segMinX || nextX >= segMaxX {
                if !support.isFloor && Double.random(in: 0...1) < physics.constants.edgeDropProbability {
                    let dropX = facingRight ? (support.maxX + footHalfW + 4.0) : (support.minX - footHalfW - 4.0)
                    x = min(max(dropX, minScreenX), maxScreenX)
                    vx = facingRight ? speed * 0.4 : -speed * 0.4
                    currentPlatform = nil
                    transition(to: .fall)
                    return
                } else {
                    facingRight.toggle()
                    x = min(max(nextX, segMinX), segMaxX)
                }
            } else {
                x = nextX
            }

            if stateElapsed >= targetStateDuration {
                transition(to: .idle)
            }

        case .jumpStep:
            // Parabolic hop up onto a low ledge
            guard let targetPlat = jumpTargetPlatform,
                  let updatedTarget = platforms.first(where: { $0.windowID == targetPlat.windowID }) else {
                currentPlatform = nil
                transition(to: .fall)
                return
            }

            // Track moving target window during hop
            let deltaX = updatedTarget.rawWindowMinX - targetPlat.rawWindowMinX
            jumpTargetX += deltaX
            jumpTargetY = updatedTarget.y
            jumpTargetPlatform = updatedTarget

            let duration = max(0.15, physics.jumpAndClimb.stepJumpDurationSeconds)
            let t = min(1.0, stateElapsed / duration)
            let arcOffset = sin(t * .pi) * physics.jumpAndClimb.stepJumpArcPeakOffset * scaleFactor

            let nextX = jumpStartX + (jumpTargetX - jumpStartX) * t
            let nextY = jumpStartY + (jumpTargetY - jumpStartY) * t + arcOffset

            if !physics.isCharacterBodyInsideScreen(centerX: nextX, feetY: nextY, charWidth: width, charHeight: height, usableBounds: usableBounds) {
                x = min(max(nextX, minScreenX), maxScreenX)
                y = min(nextY, maxScreenY)
                currentPlatform = nil
                transition(to: .fall)
                return
            }

            x = nextX
            y = nextY

            if t >= 1.0 {
                x = jumpTargetX
                y = updatedTarget.y
                currentPlatform = updatedTarget
                climbActionCooldown = 0.8
                transition(to: .walk)
            }

        case .climbWall:
            // Climbing up the left or right vertical side edge of a window
            guard climbingWindowID != 0,
                  let winSeg = platforms.first(where: { $0.windowID == climbingWindowID }) else {
                x = min(max(x, minScreenX), maxScreenX)
                y = min(y, maxScreenY)
                currentPlatform = nil
                transition(to: .fall)
                return
            }

            let edgeX = climbingOnLeftEdge ? winSeg.rawWindowMinX : winSeg.rawWindowMaxX
            // Synchronize with vertical window movement while climbing
            if let prev = currentPlatform, prev.windowID == climbingWindowID {
                y += (winSeg.y - prev.y)
            }
            currentPlatform = winSeg
            // Face toward the window while climbing
            facingRight = climbingOnLeftEdge

            let climbSpeed = physics.jumpAndClimb.climbSpeed
            let dy = climbSpeed * dt
            let nextY = y + dy
            climbDistanceSinceRest += dy

            // Check if the window moved out of screen bounds while the character is clinging to its edge
            if !physics.isCharacterBodyInsideScreen(
                centerX: edgeX,
                feetY: min(nextY, winSeg.y),
                charWidth: width,
                charHeight: effectiveH,
                usableBounds: usableBounds
            ) {
                x = min(max(edgeX, minScreenX), maxScreenX)
                y = max(floorY, min(y, maxScreenY))
                currentPlatform = nil
                transition(to: .fall)
                return
            }

            x = edgeX

            // Did we reach the top edge of the window?
            if nextY >= winSeg.y {
                let footHalfW = width * 0.32
                let stepInX = climbingOnLeftEdge
                    ? min(winSeg.maxX - footHalfW, winSeg.minX + footHalfW + 8.0)
                    : max(winSeg.minX + footHalfW, winSeg.maxX - footHalfW - 8.0)
                x = min(max(stepInX, minScreenX), maxScreenX)
                y = winSeg.y
                currentPlatform = winSeg
                climbActionCooldown = 1.5
                showSpeech(speech(for: "CLIMB_TOP", fallback: "영차! 올라왔다! ( ˶ˆᗜˆ˵ )"))
                transition(to: .walk)
                return
            }

            y = nextY

            // Check if the window is tall enough to trigger a mid-climb rest pause (unless canRestDuringClimb is false, e.g., Usagi!)
            let minTotalForRest = height * physics.jumpAndClimb.minClimbHeightForRestRatio
            let restSegmentDist = height * physics.jumpAndClimb.climbRestSegmentDistanceRatio
            let remainingToTop = winSeg.y - y

            if profile.canRestDuringClimb &&
               climbTotalHeight >= minTotalForRest &&
               climbDistanceSinceRest >= restSegmentDist &&
               remainingToTop > height * 0.45 {
                climbDistanceSinceRest = 0.0
                transition(to: .climbRest)
                return
            }

        case .climbRest:
            // Resting mid-climb while clinging to the window edge
            guard climbingWindowID != 0,
                  let winSeg = platforms.first(where: { $0.windowID == climbingWindowID }) else {
                x = min(max(x, minScreenX), maxScreenX)
                y = min(y, maxScreenY)
                currentPlatform = nil
                transition(to: .fall)
                return
            }

            let edgeX = climbingOnLeftEdge ? winSeg.rawWindowMinX : winSeg.rawWindowMaxX
            // If window moved vertically while resting, move along with it
            if let prev = currentPlatform, prev.windowID == climbingWindowID {
                let deltaY = winSeg.y - prev.y
                y += deltaY
            }
            currentPlatform = winSeg
            x = edgeX

            if !physics.isCharacterBodyInsideScreen(
                centerX: x,
                feetY: y,
                charWidth: width,
                charHeight: height,
                usableBounds: usableBounds
            ) || y > winSeg.y {
                x = min(max(x, minScreenX), maxScreenX)
                y = min(y, maxScreenY)
                currentPlatform = nil
                transition(to: .fall)
                return
            }

            if stateElapsed >= targetStateDuration {
                transition(to: .climbWall)
            }

        case .cryClick:
            vx = 0
            vy = 0
            if isMousePressed && stateElapsed >= timings.holdThresholdSeconds {
                transition(to: .draggedStruggle)
                return
            }

            if !isMousePressed {
                if let resolved = physics.resolveStandingSupport(
                    currentX: x,
                    currentY: y,
                    charWidth: width,
                    charHeight: height,
                    previousPlatform: currentPlatform,
                    platforms: platforms
                ) {
                    x = resolved.x
                    y = resolved.y
                    currentPlatform = resolved.segment
                } else {
                    x = min(max(x, minScreenX), maxScreenX)
                    y = min(y, maxScreenY)
                    currentPlatform = nil
                    transition(to: .fall)
                    return
                }

                if stateElapsed >= targetStateDuration {
                    AudioAssetPlayer.shared.stopSong(for: profile.id)
                    transition(to: .idle)
                }
            }

        case .draggedStruggle:
            currentPlatform = nil
            climbingWindowID = 0
            let anchorOffset = physics.dimensions.grabAnchorOffsetY * scaleFactor
            x = min(max(Double(lastMousePosition.x), minScreenX), maxScreenX)
            y = min(max(0.0, Double(lastMousePosition.y) - anchorOffset), maxScreenY)

        case .fall, .fallFromGrab:
            let prevY = y
            vy += physics.constants.gravity * dt
            if vy < physics.constants.terminalVelocity {
                vy = physics.constants.terminalVelocity
            }
            vx *= physics.constants.airResistance

            let nextX = min(max(x + vx * dt, minScreenX), maxScreenX)
            let nextY = min(y + vy * dt, maxScreenY)

            if let landed = physics.findLandingPlatform(
                centerX: nextX,
                previousY: max(prevY, floorY),
                nextY: nextY,
                charWidth: width,
                charHeight: height,
                platforms: platforms
            ) {
                x = nextX
                y = max(floorY, landed.y)
                vx = 0
                vy = 0
                currentPlatform = landed
                transition(to: .tumble)
                return
            }

            if nextY <= floorY {
                x = nextX
                y = floorY
                vx = 0
                vy = 0
                currentPlatform = activeFloorSegment
                transition(to: .tumble)
                return
            }

            x = nextX
            y = nextY

        case .tumble:
            vx = 0
            vy = 0
            if let resolved = physics.resolveStandingSupport(
                currentX: x,
                currentY: y,
                charWidth: width,
                charHeight: height,
                previousPlatform: currentPlatform,
                platforms: platforms
            ) {
                x = resolved.x
                y = resolved.y
                currentPlatform = resolved.segment
            } else {
                x = min(max(x, minScreenX), maxScreenX)
                y = max(floorY, min(y, maxScreenY))
                currentPlatform = nil
                transition(to: .fall)
                return
            }

            if stateElapsed >= targetStateDuration {
                transition(to: .idle)
            }
        }
    }

    private func speech(for key: String, fallback: String) -> String {
        return profile.stateSpeeches?[key] ?? fallback
    }

    // MARK: - Jump & Climb Initiators

    private func startStepJump(to segment: PlatformSegment, landingX: Double) {
        jumpStartX = x
        jumpStartY = y
        jumpTargetX = landingX
        jumpTargetY = segment.y
        jumpTargetPlatform = segment
        facingRight = landingX >= x
        showSpeech(speech(for: "JUMP_STEP", fallback: "폴짝! ♪"))
        transition(to: .jumpStep)
    }

    private func startWindowClimb(target: PlatformSegment, onLeftEdge: Bool, edgeX: Double) {
        climbingWindowID = target.windowID
        climbingOnLeftEdge = onLeftEdge
        climbDistanceSinceRest = 0.0
        climbTotalHeight = max(0.0, target.y - y)
        currentPlatform = target
        x = edgeX
        facingRight = onLeftEdge
        showSpeech(speech(for: "CLIMB_WALL", fallback: "영차.. 영차..!"))
        transition(to: .climbWall)
    }

    // MARK: - Mouse Interactions

    public func handleMouseDown(at point: CGPoint) {
        isMousePressed = true
        mousePressOrigin = point
        lastMousePosition = point
        lastMouseVelocityX = 0.0

        switch state {
        case .fall, .fallFromGrab, .jumpStep, .climbWall, .climbRest:
            transition(to: .draggedStruggle)
        default:
            transition(to: .cryClick)
        }
    }

    public func handleMouseDragged(to point: CGPoint, dt: Double) {
        guard isMousePressed else { return }
        let dx = Double(point.x - lastMousePosition.x)
        if dt > 0.001 {
            lastMouseVelocityX = max(-350.0, min(350.0, dx / dt * 0.35))
        }
        if abs(dx) > 1.5 {
            facingRight = dx > 0
        }
        lastMousePosition = point

        let distFromOrigin = hypot(point.x - mousePressOrigin.x, point.y - mousePressOrigin.y)
        if state == .cryClick && distFromOrigin > 5.0 {
            transition(to: .draggedStruggle)
        }
    }

    public func handleMouseUp(at point: CGPoint) {
        guard isMousePressed else { return }
        isMousePressed = false
        lastMousePosition = point

        if state == .draggedStruggle {
            vx = lastMouseVelocityX
            vy = -60.0
            transition(to: .fallFromGrab)
        } else if state == .cryClick && profile.playsSongOnClick {
            // Single click confirmed! Toggle full song playback (if no other character is already singing)
            if let songDuration = AudioAssetPlayer.shared.toggleOrPlayClickSong(
                for: profile,
                allowConcurrent: fsmSpec.interactionTimings.allowConcurrentSinging
            ) {
                if songDuration < 0 {
                    // Another character is already singing -> transition to IDLE first, then show SONG_BUSY speech if non-empty (e.g., Hachiware)
                    transition(to: .idle)
                    let busySpeech = speech(for: "SONG_BUSY", fallback: "")
                    if !busySpeech.isEmpty {
                        showSpeech(busySpeech, duration: 2.5)
                    } else {
                        activeSpeechText = nil
                        speechTimer = 0
                    }
                } else {
                    targetStateDuration = stateElapsed + songDuration
                    showSpeech(profile.clickSpeech, duration: 4.0)
                }
            } else {
                // Clicked again while singing -> stop song and return to IDLE
                transition(to: .idle)
            }
        }
    }

    public func showSpeech(_ text: String, duration: Double? = nil) {
        activeSpeechText = text
        speechTimer = duration ?? fsmSpec.interactionTimings.speechBubbleDurationSeconds
    }

    // MARK: - State Transitions

    public func transition(to newState: CharacterStateID) {
        state = newState
        stateElapsed = 0.0
        let timings = fsmSpec.interactionTimings

        switch newState {
        case .idle:
            targetStateDuration = Double.random(
                in: timings.idleMinDurationSeconds...timings.idleMaxDurationSeconds
            )
            if Double.random(in: 0...1) < 0.28, let phrase = profile.catchphrases.randomElement() {
                showSpeech(phrase)
            }
        case .walk:
            targetStateDuration = Double.random(
                in: timings.walkMinDurationSeconds...timings.walkMaxDurationSeconds
            )
        case .jumpStep:
            targetStateDuration = physics.jumpAndClimb.stepJumpDurationSeconds
        case .climbWall:
            break
        case .climbRest:
            targetStateDuration = physics.jumpAndClimb.climbRestDurationSeconds
            showSpeech(speech(for: "CLIMB_REST", fallback: "헉헉.. 잠깐만 쉬자.. 💦"))
        case .cryClick:
            targetStateDuration = timings.clickCryDurationSeconds
            showSpeech(profile.clickSpeech)
        case .draggedStruggle:
            AudioAssetPlayer.shared.stopSong(for: profile.id)
            showSpeech(speech(for: "DRAGGED_STRUGGLE", fallback: "으아아앙!! 놔줘~!! 💦"))
        case .fall:
            climbingWindowID = 0
        case .fallFromGrab:
            climbingWindowID = 0
            AudioAssetPlayer.shared.stopSong(for: profile.id)
            showSpeech(speech(for: "FALL_FROM_GRAB", fallback: "와아아앗~!!"))
        case .tumble:
            targetStateDuration = profile.tumbleDurationSeconds
            showSpeech(speech(for: "TUMBLE", fallback: "철푸덕..! @~@"))
        }
    }
}
