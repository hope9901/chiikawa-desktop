import AppKit
import CoreGraphics

public protocol OverlayViewDelegate: AnyObject {
    func overlayViewRequestToggleCharacter(characterID: String)
    func overlayViewRequestToggleWandering()
    func overlayViewRequestSetScale(_ scale: Double)
    func overlayViewRequestResetPositions()
    func overlayViewRequestQuit()
}

public final class OverlayView: NSView {
    public weak var delegate: OverlayViewDelegate?

    private let specBundle: SpecBundle
    private let windowTracker: WindowTracker
    private let physicsWorld: PhysicsWorld
    private let spriteRepository: SpriteAssetRepository

    public private(set) var characters: [CharacterEntity] = []
    public var wanderingEnabled: Bool = true
    public var currentScale: Double = 1.0

    private var grabbedCharacter: CharacterEntity?
    private weak var rightClickedCharacter: CharacterEntity?
    private var lastUpdateTimestamp: TimeInterval = ProcessInfo.processInfo.systemUptime

    public init(frame: NSRect, specBundle: SpecBundle, windowTracker: WindowTracker, physicsWorld: PhysicsWorld) {
        self.specBundle = specBundle
        self.windowTracker = windowTracker
        self.physicsWorld = physicsWorld
        self.spriteRepository = SpriteAssetRepository(fsmSpec: specBundle.characterFSM)
        super.init(frame: frame)
        self.wantsLayer = true
        self.layer?.isOpaque = false
        self.layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var isOpaque: Bool { false }

    // MARK: - Character Management (Unique per character ID, Max 4 enforced by spec)

    public func isCharacterActive(id: String) -> Bool {
        return characters.contains { $0.profile.id == id }
    }

    @discardableResult
    public func spawnCharacter(id: String) -> Bool {
        let limits = specBundle.physicsAndWorld.populationLimits
        guard characters.count < limits.maxConcurrentCharacters else { return false }

        if !limits.allowDuplicateCharacters && isCharacterActive(id: id) {
            return false
        }

        guard let profile = specBundle.characterFSM.defaultCharacters.first(where: { $0.id == id }) else {
            return false
        }

        let screenBounds = self.bounds
        let margin = 140.0
        let randomX = Double.random(in: (Double(screenBounds.minX) + margin)...(max(Double(screenBounds.minX) + margin + 10, Double(screenBounds.maxX) - margin)))
        let spawnY = Double(screenBounds.maxY) - 140.0

        let entity = CharacterEntity(
            profile: profile,
            fsmSpec: specBundle.characterFSM,
            physics: physicsWorld,
            startX: randomX,
            startY: spawnY,
            scaleFactor: currentScale
        )
        characters.append(entity)
        setNeedsDisplay(entity.dirtyRect)
        return true
    }

    public func removeCharacter(id: String) {
        let targets = characters.filter { $0.profile.id == id }
        for target in targets {
            let oldRect = target.dirtyRect
            characters.removeAll { $0.instanceID == target.instanceID }
            setNeedsDisplay(oldRect)
        }
    }

    /// Toggles a character by ID: if active on desktop -> rests (removes); if resting -> summons (spawns).
    public func toggleCharacter(id: String) {
        if isCharacterActive(id: id) {
            removeCharacter(id: id)
        } else {
            _ = spawnCharacter(id: id)
        }
    }

    public func setScaleForAll(_ scale: Double) {
        currentScale = scale
        for char in characters {
            let oldRect = char.dirtyRect
            char.scaleFactor = scale
            setNeedsDisplay(oldRect.union(char.dirtyRect))
        }
    }

    public func resetAllPositions() {
        let screenBounds = self.bounds
        let count = max(1, characters.count)
        let spacing = min(140.0, Double(screenBounds.width) / Double(count + 1))
        let startX = Double(screenBounds.midX) - Double(count - 1) * spacing * 0.5

        for (idx, char) in characters.enumerated() {
            let oldRect = char.dirtyRect
            char.x = startX + Double(idx) * spacing
            char.y = Double(screenBounds.maxY) - 160.0
            char.vx = 0
            char.vy = 0
            char.transition(to: .fall)
            setNeedsDisplay(oldRect.union(char.dirtyRect))
        }
    }

    // MARK: - Low-Resource Tick & Dirty-Rect Invalidation

    public var recommendedTimerInterval: TimeInterval {
        let coord = specBundle.physicsAndWorld.coordinateSystem
        if characters.contains(where: { $0.isHighFrequencyState }) {
            return 1.0 / Double(coord.activeFrameRate) // 60 FPS during fall / drag / cry / tumble
        }
        if !wanderingEnabled && characters.allSatisfy({ $0.state == .idle }) {
            return 1.0 / Double(coord.idleFrameRate) // 12 FPS when all stationary
        }
        return 1.0 / Double(coord.normalFrameRate) // 30 FPS normal walking/idle
    }

    public func stepSimulation() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.05, max(0.001, now - lastUpdateTimestamp))
        lastUpdateTimestamp = now

        let platforms = windowTracker.pollPlatforms(force: false)
        let useDirtyRect = specBundle.architecture.resourceOptimizationPolicy.useDirtyRectInvalidation

        for char in characters {
            let prevRect = char.dirtyRect
            char.update(
                dt: dt,
                platforms: platforms,
                screenBounds: self.bounds,
                wanderingEnabled: wanderingEnabled
            )
            let nextRect = char.dirtyRect
            if useDirtyRect {
                setNeedsDisplay(prevRect.union(nextRect))
            }
        }

        if !useDirtyRect {
            self.needsDisplay = true
        }

        updateWindowClickThroughState()
    }

    /// Ensures the full-screen window passes all mouse clicks through to underlying apps
    /// UNLESS the mouse cursor is currently inside one of the characters' hitboxes (or dragging).
    public func updateWindowClickThroughState() {
        guard let win = self.window else { return }
        if grabbedCharacter != nil {
            if win.ignoresMouseEvents {
                win.ignoresMouseEvents = false
            }
            return
        }

        let mouseScreenLoc = NSEvent.mouseLocation
        let localPoint = self.convert(win.convertPoint(fromScreen: mouseScreenLoc), from: nil)
        let isHoveringCharacter = characters.contains { $0.hitboxRect.contains(localPoint) }

        let shouldIgnore = !isHoveringCharacter
        if win.ignoresMouseEvents != shouldIgnore {
            win.ignoresMouseEvents = shouldIgnore
        }
    }

    // MARK: - Mouse Events (Left Click / Hold / Drag / Release & Right Click Menu)

    public override func mouseDown(with event: NSEvent) {
        let pt = self.convert(event.locationInWindow, from: nil)
        if let target = characters.reversed().first(where: { $0.hitboxRect.contains(pt) }) {
            let oldRect = target.dirtyRect
            grabbedCharacter = target
            target.handleMouseDown(at: pt)
            setNeedsDisplay(oldRect.union(target.dirtyRect))
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let target = grabbedCharacter else { return }
        let pt = self.convert(event.locationInWindow, from: nil)
        let oldRect = target.dirtyRect
        target.handleMouseDragged(to: pt, dt: 1.0 / 60.0)
        setNeedsDisplay(oldRect.union(target.dirtyRect))
    }

    public override func mouseUp(with event: NSEvent) {
        guard let target = grabbedCharacter else { return }
        let pt = self.convert(event.locationInWindow, from: nil)
        let oldRect = target.dirtyRect
        target.handleMouseUp(at: pt)
        grabbedCharacter = nil
        setNeedsDisplay(oldRect.union(target.dirtyRect))
        updateWindowClickThroughState()
    }

    public override func rightMouseDown(with event: NSEvent) {
        let pt = self.convert(event.locationInWindow, from: nil)
        guard let target = characters.reversed().first(where: { $0.hitboxRect.contains(pt) }) else {
            return
        }
        rightClickedCharacter = target
        let menu = buildContextMenu(for: target)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func buildContextMenu(for character: CharacterEntity) -> NSMenu {
        let menu = NSMenu(title: character.profile.displayName)

        let headerItem = NSMenuItem(title: "🐾 \(character.profile.displayName)", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(.separator())

        let wanderItem = NSMenuItem(
            title: wanderingEnabled ? "자율 이동 멈추기 (Pause Wandering)" : "자율 이동 켜기 (Resume Wandering)",
            action: #selector(contextToggleWandering),
            keyEquivalent: ""
        )
        wanderItem.target = self
        menu.addItem(wanderItem)

        menu.addItem(.separator())

        let restSelfItem = NSMenuItem(
            title: "\(character.profile.displayName) 휴식",
            action: #selector(contextRestClickedCharacter),
            keyEquivalent: ""
        )
        restSelfItem.target = self
        menu.addItem(restSelfItem)

        let rosterSubmenu = NSMenu(title: "캐릭터 소환 / 휴식")
        for profile in specBundle.characterFSM.defaultCharacters {
            let active = isCharacterActive(id: profile.id)
            let actionWord = active ? "휴식" : "소환"
            let item = NSMenuItem(
                title: "\(profile.displayName) \(actionWord)",
                action: #selector(contextToggleCharacter(_:)),
                keyEquivalent: ""
            )
            item.state = active ? .on : .off
            item.representedObject = profile.id
            item.target = self
            rosterSubmenu.addItem(item)
        }
        let rosterMenuItem = NSMenuItem(title: "캐릭터 소환 / 휴식 설정", action: nil, keyEquivalent: "")
        rosterMenuItem.submenu = rosterSubmenu
        menu.addItem(rosterMenuItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "종료 (Quit)", action: #selector(contextQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func contextToggleWandering() {
        delegate?.overlayViewRequestToggleWandering()
    }

    @objc private func contextRestClickedCharacter() {
        if let target = rightClickedCharacter {
            delegate?.overlayViewRequestToggleCharacter(characterID: target.profile.id)
        }
    }

    @objc private func contextToggleCharacter(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String {
            delegate?.overlayViewRequestToggleCharacter(characterID: id)
        }
    }

    @objc private func contextQuit() {
        delegate?.overlayViewRequestQuit()
    }

    // MARK: - Vector Placeholder Rendering (Chiikawa Style)

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        for char in characters {
            guard char.dirtyRect.intersects(dirtyRect) else { continue }
            drawCharacter(char, in: ctx)
        }
    }

    private func drawCharacter(_ char: CharacterEntity, in ctx: CGContext) {
        ctx.saveGState()

        let w = CGFloat(char.width)
        let h = CGFloat(char.height)
        let centerX = CGFloat(char.x)
        let baseY = CGFloat(char.y)
        let phase = CGFloat(char.animPhase)

        // Compute posture offsets & rotations per FSM state
        var bobY: CGFloat = 0.0
        var tiltAngle: CGFloat = 0.0
        var squashX: CGFloat = 1.0
        var squashY: CGFloat = 1.0

        switch char.state {
        case .idle:
            bobY = sin(phase * 3.2) * 1.8
            squashY = 1.0 + sin(phase * 3.2) * 0.02
        case .walk:
            bobY = abs(sin(phase * 9.5)) * 5.5
            tiltAngle = sin(phase * 9.5) * 0.11
        case .jumpStep:
            squashX = 0.94
            squashY = 1.08
            tiltAngle = (char.facingRight ? -1.0 : 1.0) * 0.12
        case .climbWall:
            bobY = abs(sin(phase * 13.0)) * 3.5
            tiltAngle = (char.climbingOnLeftEdge ? 1.0 : -1.0) * 0.18 + sin(phase * 13.0) * 0.06
        case .climbRest:
            bobY = sin(phase * 6.5) * 2.0
            squashX = 1.04 + sin(phase * 6.5) * 0.03
            squashY = 0.96 - sin(phase * 6.5) * 0.03
            tiltAngle = (char.climbingOnLeftEdge ? 1.0 : -1.0) * 0.10
        case .cryClick:
            bobY = abs(sin(phase * 22.0)) * 2.5
            tiltAngle = sin(phase * 28.0) * 0.08
            squashX = 1.04
            squashY = 0.96
        case .draggedStruggle:
            bobY = sin(phase * 25.0) * 3.5
            tiltAngle = sin(phase * 24.0) * 0.24
            squashX = 0.94
            squashY = 1.07
        case .fall, .fallFromGrab:
            squashX = 0.90
            squashY = 1.10
            tiltAngle = sin(phase * 14.0) * 0.14
        case .tumble:
            // Falling over / lying down motion then bouncing back up
            let progress = min(1.0, CGFloat(char.stateElapsed / max(0.1, char.targetStateDuration)))
            if progress < 0.72 {
                tiltAngle = (char.facingRight ? -1.0 : 1.0) * (.pi * 0.45)
                bobY = -h * 0.12
                squashX = 1.12
                squashY = 0.88
            } else {
                let recover = (progress - 0.72) / 0.28
                tiltAngle = (char.facingRight ? -1.0 : 1.0) * (.pi * 0.45) * (1.0 - recover)
                bobY = sin(recover * .pi) * 8.0
            }
        }

        let bodyCenterX = centerX
        let bodyCenterY = baseY + h * 0.45 + bobY

        // Soft ground shadow when near platform (skip while climbing vertical wall or jumping)
        if let support = char.currentPlatform, char.state != .climbWall && char.state != .climbRest && char.state != .jumpStep {
            let shadowW = w * 0.62
            let shadowH: CGFloat = 8.0
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.18).cgColor)
            ctx.fillEllipse(in: CGRect(
                x: centerX - shadowW * 0.5,
                y: CGFloat(support.y) - shadowH * 0.5,
                width: shadowW,
                height: shadowH
            ))
        }

        // Check if custom PNG sprite frames exist in assets/<id>/<state>/*.png
        if let customSprite = spriteRepository.frame(
            for: char.profile.id,
            state: char.state,
            stateElapsed: char.stateElapsed,
            animPhase: char.animPhase
        ) {
            ctx.saveGState()
            ctx.translateBy(x: centerX, y: baseY + (char.state == .climbWall || char.state == .climbRest ? bobY : 0))
            if char.state == .climbWall || char.state == .climbRest || char.state == .jumpStep {
                ctx.rotate(by: tiltAngle)
            }
            ctx.scaleBy(x: squashX * (char.facingRight ? 1.0 : -1.0), y: squashY)
            let spriteRect = CGRect(x: -w * 0.5, y: 0, width: w, height: h)
            ctx.interpolationQuality = .high
            ctx.draw(customSprite, in: spriteRect)

            // Draw cute sweat drops when resting mid-climb
            if char.state == .climbRest {
                let sweatColor = NSColor(calibratedRed: 0.40, green: 0.78, blue: 1.0, alpha: 0.90)
                ctx.setFillColor(sweatColor.cgColor)
                let dropOffset = (phase * 18.0).truncatingRemainder(dividingBy: 10.0)
                ctx.fillEllipse(in: CGRect(x: w * 0.28, y: h * 0.62 - dropOffset, width: 6.5, height: 9.5))
                ctx.fillEllipse(in: CGRect(x: -w * 0.34, y: h * 0.56 - dropOffset * 0.7, width: 5.5, height: 8.5))
            }
            ctx.restoreGState()

            if let text = char.activeSpeechText {
                drawSpeechBubble(text: text, centerX: centerX, topY: baseY + h + 4.0, in: ctx)
            }
            ctx.restoreGState()
            return
        }

        ctx.saveGState()
        ctx.translateBy(x: bodyCenterX, y: bodyCenterY)
        ctx.rotate(by: tiltAngle)
        ctx.scaleBy(x: squashX * (char.facingRight ? 1.0 : -1.0), y: squashY)

        let primaryColor = NSColor.fromHex(char.profile.primaryColorHex)
        let accentColor = NSColor.fromHex(char.profile.accentColorHex)
        let outlineColor = NSColor(calibratedRed: 0.22, green: 0.18, blue: 0.18, alpha: 1.0)

        // 1. Draw Ears / Tail behind body
        drawEarsAndTail(style: char.profile.earStyle, w: w, h: h, primary: primaryColor, accent: accentColor, outline: outlineColor, in: ctx)

        // 2. Draw Main Chubby Body
        let bodyW = w * 0.76
        let bodyH = h * 0.68
        let bodyRect = CGRect(x: -bodyW * 0.5, y: -bodyH * 0.5, width: bodyW, height: bodyH)
        let bodyPath = CGPath(roundedRect: bodyRect, cornerWidth: bodyW * 0.44, cornerHeight: bodyH * 0.44, transform: nil)

        ctx.addPath(bodyPath)
        ctx.setFillColor(primaryColor.cgColor)
        ctx.fillPath()

        // Hachiware blue forehead pattern
        if char.profile.earStyle == "pointed_blue" {
            ctx.saveGState()
            ctx.addPath(bodyPath)
            ctx.clip()
            ctx.setFillColor(accentColor.cgColor)
            let leftPart = CGMutablePath()
            leftPart.move(to: CGPoint(x: 0, y: bodyH * 0.22))
            leftPart.addLine(to: CGPoint(x: -bodyW * 0.55, y: bodyH * 0.05))
            leftPart.addLine(to: CGPoint(x: -bodyW * 0.55, y: bodyH * 0.6))
            leftPart.addLine(to: CGPoint(x: 0, y: bodyH * 0.6))
            leftPart.closeSubpath()

            leftPart.move(to: CGPoint(x: 0, y: bodyH * 0.22))
            leftPart.addLine(to: CGPoint(x: bodyW * 0.55, y: bodyH * 0.05))
            leftPart.addLine(to: CGPoint(x: bodyW * 0.55, y: bodyH * 0.6))
            leftPart.addLine(to: CGPoint(x: 0, y: bodyH * 0.6))
            leftPart.closeSubpath()
            ctx.addPath(leftPart)
            ctx.fillPath()
            ctx.restoreGState()
        }

        ctx.addPath(bodyPath)
        ctx.setStrokeColor(outlineColor.cgColor)
        ctx.setLineWidth(2.6)
        ctx.strokePath()

        // 3. Draw Short Arms & Feet (flailing when struggling!)
        drawLimbs(state: char.state, phase: phase, bodyW: bodyW, bodyH: bodyH, primary: primaryColor, outline: outlineColor, in: ctx)

        // 4. Draw Face (Eyes, Blush, Mouth, Tears)
        drawFace(char: char, phase: phase, bodyW: bodyW, bodyH: bodyH, outline: outlineColor, in: ctx)

        ctx.restoreGState()

        // 5. Draw Speech Bubble above character if active
        if let text = char.activeSpeechText {
            drawSpeechBubble(text: text, centerX: centerX, topY: bodyCenterY + h * 0.52, in: ctx)
        }

        ctx.restoreGState()
    }

    private func drawEarsAndTail(
        style: String,
        w: CGFloat,
        h: CGFloat,
        primary: NSColor,
        accent: NSColor,
        outline: NSColor,
        in ctx: CGContext
    ) {
        ctx.setLineWidth(2.5)
        ctx.setStrokeColor(outline.cgColor)

        switch style {
        case "long_rabbit": // Usagi long ears
            for sign: CGFloat in [-1.0, 1.0] {
                ctx.saveGState()
                ctx.translateBy(x: sign * w * 0.16, y: h * 0.26)
                ctx.rotate(by: -sign * 0.12)
                let earRect = CGRect(x: -w * 0.08, y: 0, width: w * 0.16, height: h * 0.34)
                let path = CGPath(roundedRect: earRect, cornerWidth: w * 0.08, cornerHeight: w * 0.08, transform: nil)
                ctx.addPath(path)
                ctx.setFillColor(primary.cgColor)
                ctx.fillPath()
                ctx.addPath(path)
                ctx.strokePath()

                let innerRect = earRect.insetBy(dx: 3.5, dy: 5.0)
                ctx.setFillColor(NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.82, alpha: 0.8).cgColor)
                ctx.fillEllipse(in: innerRect)
                ctx.restoreGState()
            }
        case "pointed_blue": // Hachiware cat ears
            for sign: CGFloat in [-1.0, 1.0] {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: sign * w * 0.12, y: h * 0.25))
                path.addLine(to: CGPoint(x: sign * w * 0.26, y: h * 0.45))
                path.addLine(to: CGPoint(x: sign * w * 0.32, y: h * 0.16))
                path.closeSubpath()
                ctx.addPath(path)
                ctx.setFillColor(accent.cgColor)
                ctx.fillPath()
                ctx.addPath(path)
                ctx.strokePath()
            }
        case "fluffy_squirrel": // Momonga fluffy tail + round ears
            let tailRect = CGRect(x: -w * 0.52, y: -h * 0.15, width: w * 0.34, height: h * 0.46)
            ctx.setFillColor(accent.cgColor)
            ctx.fillEllipse(in: tailRect)
            ctx.strokeEllipse(in: tailRect)

            for sign: CGFloat in [-1.0, 1.0] {
                let earRect = CGRect(x: sign * w * 0.22 - w * 0.10, y: h * 0.22, width: w * 0.20, height: h * 0.20)
                ctx.setFillColor(primary.cgColor)
                ctx.fillEllipse(in: earRect)
                ctx.strokeEllipse(in: earRect)
            }
        default: // Chiikawa round bear ears
            for sign: CGFloat in [-1.0, 1.0] {
                let earRect = CGRect(x: sign * w * 0.23 - w * 0.10, y: h * 0.22, width: w * 0.20, height: h * 0.20)
                ctx.setFillColor(primary.cgColor)
                ctx.fillEllipse(in: earRect)
                ctx.strokeEllipse(in: earRect)
            }
        }
    }

    private func drawLimbs(
        state: CharacterStateID,
        phase: CGFloat,
        bodyW: CGFloat,
        bodyH: CGFloat,
        primary: NSColor,
        outline: NSColor,
        in ctx: CGContext
    ) {
        ctx.setFillColor(primary.cgColor)
        ctx.setStrokeColor(outline.cgColor)
        ctx.setLineWidth(2.4)

        let armSwing: CGFloat
        let legSwing: CGFloat
        switch state {
        case .draggedStruggle, .cryClick:
            armSwing = sin(phase * 34.0) * 9.0
            legSwing = cos(phase * 34.0) * 8.0
        case .walk, .climbWall, .jumpStep:
            armSwing = sin(phase * 12.0) * 5.0
            legSwing = sin(phase * 12.0) * 6.0
        default:
            armSwing = 0.0
            legSwing = 0.0
        }

        // Left & Right Arms
        for sign: CGFloat in [-1.0, 1.0] {
            let armY = (state == .draggedStruggle || state == .cryClick) ? bodyH * 0.05 + sign * armSwing : -bodyH * 0.05 + sign * armSwing
            let armRect = CGRect(x: sign * bodyW * 0.46 - 6.0, y: armY - 6.0, width: 12.0, height: 12.0)
            ctx.fillEllipse(in: armRect)
            ctx.strokeEllipse(in: armRect)
        }

        // Left & Right Feet
        for sign: CGFloat in [-1.0, 1.0] {
            let footY = -bodyH * 0.52 + (sign * legSwing * 0.6)
            let footRect = CGRect(x: sign * bodyW * 0.22 - 7.0, y: footY, width: 14.0, height: 11.0)
            ctx.fillEllipse(in: footRect)
            ctx.strokeEllipse(in: footRect)
        }
    }

    private func drawFace(
        char: CharacterEntity,
        phase: CGFloat,
        bodyW: CGFloat,
        bodyH: CGFloat,
        outline: NSColor,
        in ctx: CGContext
    ) {
        let eyeY = bodyH * 0.04
        let eyeOffsetX = bodyW * 0.19

        // Pink cheeks
        ctx.setFillColor(NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.70, alpha: 0.55).cgColor)
        for sign: CGFloat in [-1.0, 1.0] {
            let cheekRect = CGRect(x: sign * (eyeOffsetX + 7.0) - 6.5, y: eyeY - 9.0, width: 13.0, height: 8.0)
            ctx.fillEllipse(in: cheekRect)
        }

        ctx.setStrokeColor(outline.cgColor)
        ctx.setFillColor(outline.cgColor)
        ctx.setLineWidth(2.4)
        ctx.setLineCap(.round)

        switch char.state {
        case .cryClick, .draggedStruggle, .fallFromGrab:
            // Crying eyes (> <) + streaming tears!
            for sign: CGFloat in [-1.0, 1.0] {
                let cx = sign * eyeOffsetX
                ctx.beginPath()
                ctx.move(to: CGPoint(x: cx - sign * 4.5, y: eyeY + 4.0))
                ctx.addLine(to: CGPoint(x: cx + sign * 2.5, y: eyeY))
                ctx.addLine(to: CGPoint(x: cx - sign * 4.5, y: eyeY - 4.0))
                ctx.strokePath()

                // Animated tear drops
                let tearColor = NSColor(calibratedRed: 0.40, green: 0.75, blue: 1.0, alpha: 0.88)
                ctx.setFillColor(tearColor.cgColor)
                let tearDropOffset = (phase * 38.0).truncatingRemainder(dividingBy: 14.0)
                let tearRect = CGRect(
                    x: cx + sign * 3.0 - 3.5,
                    y: eyeY - 6.0 - tearDropOffset,
                    width: 7.0,
                    height: 10.0
                )
                ctx.fillEllipse(in: tearRect)
            }

            // Wailing open mouth
            let mouthRect = CGRect(x: -5.5, y: eyeY - 12.0, width: 11.0, height: 8.5)
            ctx.setFillColor(NSColor(calibratedRed: 0.92, green: 0.38, blue: 0.45, alpha: 1.0).cgColor)
            ctx.fillEllipse(in: mouthRect)
            ctx.strokeEllipse(in: mouthRect)

        case .tumble:
            // Dizzy spiral / X eyes (@ @)
            for sign: CGFloat in [-1.0, 1.0] {
                let cx = sign * eyeOffsetX
                ctx.beginPath()
                ctx.move(to: CGPoint(x: cx - 4.0, y: eyeY - 4.0))
                ctx.addLine(to: CGPoint(x: cx + 4.0, y: eyeY + 4.0))
                ctx.move(to: CGPoint(x: cx - 4.0, y: eyeY + 4.0))
                ctx.addLine(to: CGPoint(x: cx + 4.0, y: eyeY - 4.0))
                ctx.strokePath()
            }
            // Wavy mouth
            ctx.beginPath()
            ctx.move(to: CGPoint(x: -4.0, y: eyeY - 9.0))
            ctx.addQuadCurve(to: CGPoint(x: 4.0, y: eyeY - 9.0), control: CGPoint(x: 0.0, y: eyeY - 5.0))
            ctx.strokePath()

        default:
            // Cute dark round eyes with white highlight
            for sign: CGFloat in [-1.0, 1.0] {
                let cx = sign * eyeOffsetX
                let eyeRect = CGRect(x: cx - 4.2, y: eyeY - 4.2, width: 8.4, height: 8.4)
                ctx.setFillColor(outline.cgColor)
                ctx.fillEllipse(in: eyeRect)

                let highlightRect = CGRect(x: cx - 2.2, y: eyeY + 0.5, width: 3.2, height: 3.2)
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fillEllipse(in: highlightRect)
            }

            // Cute ω mouth
            ctx.beginPath()
            ctx.move(to: CGPoint(x: -5.0, y: eyeY - 7.5))
            ctx.addQuadCurve(to: CGPoint(x: 0.0, y: eyeY - 6.0), control: CGPoint(x: -2.5, y: eyeY - 10.5))
            ctx.addQuadCurve(to: CGPoint(x: 5.0, y: eyeY - 7.5), control: CGPoint(x: 2.5, y: eyeY - 10.5))
            ctx.strokePath()
        }
    }

    private func drawSpeechBubble(text: String, centerX: CGFloat, topY: CGFloat, in ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 0.20, green: 0.16, blue: 0.16, alpha: 1.0)
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrStr.size()

        let padX: CGFloat = 10.0
        let padY: CGFloat = 5.0
        let bubbleW = textSize.width + padX * 2.0
        let bubbleH = textSize.height + padY * 2.0
        let bubbleRect = CGRect(
            x: centerX - bubbleW * 0.5,
            y: topY + 4.0,
            width: bubbleW,
            height: bubbleH
        )

        let path = CGPath(roundedRect: bubbleRect, cornerWidth: 10.0, cornerHeight: 10.0, transform: nil)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.94).cgColor)
        ctx.fillPath()
        ctx.addPath(path)
        ctx.setStrokeColor(NSColor(calibratedRed: 0.25, green: 0.20, blue: 0.20, alpha: 0.85).cgColor)
        ctx.setLineWidth(1.6)
        ctx.strokePath()

        attrStr.draw(at: CGPoint(x: bubbleRect.minX + padX, y: bubbleRect.minY + padY))
        ctx.restoreGState()
    }
}

// MARK: - Hex Color Helper

extension NSColor {
    static func fromHex(_ hex: String) -> NSColor {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (255, 253, 249)
        }
        return NSColor(
            calibratedRed: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: 1.0
        )
    }
}
