import AppKit

@main
public final class AppDelegate: NSObject, NSApplicationDelegate, OverlayViewDelegate {
    private var specBundle: SpecBundle!
    private var windowTracker: WindowTracker!
    private var physicsWorld: PhysicsWorld!

    private var overlayWindow: NSWindow!
    private var secondaryWindows: [NSWindow] = []
    private var overlayView: OverlayView!
    private var statusItem: NSStatusItem!

    private var simulationTimer: Timer?
    private var currentTimerInterval: TimeInterval = 1.0 / 30.0
    private var isPausedForSleep: Bool = false

    public static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // Runs as a lightweight menu-bar desktop pet without cluttering Dock
        app.run()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            specBundle = try SpecBundle.loadDefault()
        } catch {
            NSLog("[ChiikawaDesktop] Failed to load spec/*.json: \(error)")
            NSApp.terminate(nil)
            return
        }

        windowTracker = WindowTracker(spec: specBundle.physicsAndWorld)
        physicsWorld = PhysicsWorld(spec: specBundle.physicsAndWorld)

        setupOverlayWindow()
        setupStatusBarMenu()
        setupWorkspaceObservers()

        // Spawn initial characters defined in spec/physics_and_world.json
        for id in specBundle.physicsAndWorld.populationLimits.initialSpawnCharacters {
            _ = overlayView.spawnCharacter(id: id)
        }

        scheduleAdaptiveTimer(interval: overlayView.recommendedTimerInterval)
    }

    private func setupOverlayWindow() {
        let screens = NSScreen.screens
        let primaryFrame = screens.first?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        overlayWindow = makeTransparentOverlayWindow(frame: primaryFrame)

        overlayView = OverlayView(
            frame: NSRect(origin: .zero, size: primaryFrame.size),
            specBundle: specBundle,
            windowTracker: windowTracker,
            physicsWorld: physicsWorld
        )
        overlayView.delegate = self

        overlayWindow.contentView = overlayView
        overlayWindow.orderFrontRegardless()

        rebuildSecondaryMonitorWindows()
    }

    private func makeTransparentOverlayWindow(frame: NSRect) -> NSWindow {
        let win = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        win.ignoresMouseEvents = true
        win.acceptsMouseMovedEvents = true
        win.isReleasedWhenClosed = false
        return win
    }

    private func rebuildSecondaryMonitorWindows() {
        for win in secondaryWindows {
            win.orderOut(nil)
        }
        secondaryWindows.removeAll()
        overlayView.mirrorViews.removeAll()

        let screens = NSScreen.screens
        guard screens.count > 1 else { return }

        for screen in screens.dropFirst() {
            let sFrame = screen.frame
            let win = makeTransparentOverlayWindow(frame: sFrame)
            let mirror = MonitorMirrorView(
                frame: NSRect(origin: .zero, size: sFrame.size),
                primaryView: overlayView
            )
            win.contentView = mirror
            win.orderFrontRegardless()
            secondaryWindows.append(win)
            overlayView.mirrorViews.append(mirror)
        }
    }

    private func setupStatusBarMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "🐾 치이카와"
        }
        rebuildStatusBarMenu()
    }

    private func rebuildStatusBarMenu() {
        let menu = NSMenu(title: "ChiikawaDesktop")
        let maxCount = specBundle.physicsAndWorld.populationLimits.maxConcurrentCharacters
        let currentCount = overlayView.characters.count

        let countItem = NSMenuItem(
            title: "현재 캐릭터: \(currentCount) / \(maxCount)명",
            action: nil,
            keyEquivalent: ""
        )
        countItem.isEnabled = false
        menu.addItem(countItem)
        menu.addItem(.separator())

        for profile in specBundle.characterFSM.defaultCharacters {
            let isActive = overlayView.isCharacterActive(id: profile.id)
            let actionWord = isActive ? "휴식" : "소환"
            let item = NSMenuItem(
                title: "\(profile.displayName) \(actionWord)",
                action: #selector(menuToggleCharacter(_:)),
                keyEquivalent: ""
            )
            item.state = isActive ? .on : .off
            item.representedObject = profile.id
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let wanderItem = NSMenuItem(
            title: overlayView.wanderingEnabled ? "자율 돌아다니기: 켜짐" : "자율 돌아다니기: 꺼짐",
            action: #selector(menuToggleWandering),
            keyEquivalent: ""
        )
        wanderItem.state = overlayView.wanderingEnabled ? .on : .off
        wanderItem.target = self
        menu.addItem(wanderItem)

        menu.addItem(.separator())
        menu.addItem(overlayView.makeScaleSliderMenuItem())
        menu.addItem(.separator())

        let resetItem = NSMenuItem(
            title: "모두 위로 부르기 (Reset Positions)",
            action: #selector(menuResetPositions),
            keyEquivalent: "r"
        )
        resetItem.target = self
        menu.addItem(resetItem)

        let loginItem = NSMenuItem(
            title: "시작프로그램 등록 (로그인 시 자동 실행)",
            action: #selector(menuToggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "종료 (Quit)",
            action: #selector(menuQuit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Low-Resource Adaptive Loop & OS Workspace Observers

    private func setupWorkspaceObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter

        // Immediately refresh platforms when user switches active app
        wsCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            _ = self.windowTracker.pollPlatforms(force: true)
        }

        // Resize overlay windows if monitor resolution, multi-monitor layout, or Dock geometry changes
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let primaryFrame = NSScreen.screens.first?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            self.overlayWindow.setFrame(primaryFrame, display: true)
            self.overlayView.frame = NSRect(origin: .zero, size: primaryFrame.size)
            self.rebuildSecondaryMonitorWindows()
            _ = self.windowTracker.pollPlatforms(force: true)
        }

        if specBundle.architecture.resourceOptimizationPolicy.sleepOnScreenLock {
            wsCenter.addObserver(
                forName: NSWorkspace.screensDidSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.isPausedForSleep = true
                self?.simulationTimer?.invalidate()
                self?.simulationTimer = nil
            }

            wsCenter.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.isPausedForSleep = false
                self.scheduleAdaptiveTimer(interval: self.overlayView.recommendedTimerInterval)
            }
        }
    }

    private func scheduleAdaptiveTimer(interval: TimeInterval) {
        simulationTimer?.invalidate()
        currentTimerInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = interval * 0.15 // Allows macOS timer coalescing for low CPU & energy impact
        RunLoop.main.add(timer, forMode: .common)
        simulationTimer = timer
    }

    private func tick() {
        guard !isPausedForSleep else { return }
        overlayView.stepSimulation()

        let desired = overlayView.recommendedTimerInterval
        if abs(desired - currentTimerInterval) > 0.004 {
            scheduleAdaptiveTimer(interval: desired)
        }
    }

    // MARK: - Menu Actions & OverlayViewDelegate

    @objc private func menuToggleCharacter(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String {
            overlayViewRequestToggleCharacter(characterID: id)
        }
    }

    @objc private func menuToggleWandering() {
        overlayViewRequestToggleWandering()
    }

    @objc private func menuSelectScale(_ sender: NSMenuItem) {
        if let scale = sender.representedObject as? Double {
            overlayViewRequestSetScale(scale)
        }
    }

    @objc private func menuResetPositions() {
        overlayViewRequestResetPositions()
    }

    @objc private func menuToggleLaunchAtLogin() {
        overlayViewRequestToggleLaunchAtLogin()
    }

    @objc private func menuQuit() {
        overlayViewRequestQuit()
    }

    public func overlayViewRequestToggleCharacter(characterID: String) {
        overlayView.toggleCharacter(id: characterID)
        rebuildStatusBarMenu()
    }

    public func overlayViewRequestToggleWandering() {
        overlayView.wanderingEnabled.toggle()
        rebuildStatusBarMenu()
    }

    public func overlayViewRequestSetScale(_ scale: Double) {
        overlayView.setScaleForAll(scale)
    }

    public func overlayViewRequestResetPositions() {
        overlayView.resetAllPositions()
    }

    public func overlayViewRequestToggleLaunchAtLogin() {
        _ = LaunchAtLoginManager.shared.toggle()
        rebuildStatusBarMenu()
    }

    public func overlayViewRequestQuit() {
        NSApp.terminate(nil)
    }
}
