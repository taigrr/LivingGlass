import AppKit
import IOKit.ps

class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    var statusItem: NSStatusItem!
    var powerTimer: Timer?
    var isPaused = false
    var manualPause = false
    var pauseMenuItem: NSMenuItem!
    var originalWallpapers: [NSScreen: URL] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Poll power state every 30s
        powerTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkPowerState()
        }
        checkPowerState()

        // Instant response to Low Power Mode toggle
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateChanged),
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
        // Menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.title = "🧬"
        }

        let menu = NSMenu()
        pauseMenuItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "p")
        pauseMenuItem.target = self
        menu.addItem(pauseMenuItem)
        let resetItem = NSMenuItem(title: "Reset", action: #selector(resetAll), keyEquivalent: "r")
        resetItem.target = self
        menu.addItem(resetItem)
        menu.addItem(NSMenuItem.separator())
        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit LivingGlass", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu

        // Set desktop wallpaper to caviar to prevent flash on space switch
        setCaviarWallpaper()

        // Create a window for each screen
        for screen in NSScreen.screens {
            createWindow(for: screen)
        }

        // Watch for screen changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Watch for space switches — trigger reveal animation
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    private func createWindow(for screen: NSScreen) {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )

        // Sit at the desktop level (behind desktop icons and all windows)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.backgroundColor = NSColor(hex: 0x121117)
        window.hidesOnDeactivate = false
        window.canHide = false
        window.animationBehavior = .none

        let lifeView = GameOfLifeView(frame: screen.frame)
        window.contentView = lifeView

        window.orderFront(nil)
        windows.append(window)
    }

    @objc func screensChanged() {
        // Tear down and rebuild for new screen config
        for w in windows {
            w.close()
        }
        windows.removeAll()
        for screen in NSScreen.screens {
            createWindow(for: screen)
        }
    }

    @objc func resetAll() {
        for window in windows {
            if let view = window.contentView as? GameOfLifeView {
                view.reset()
            }
        }
    }

    @objc func spaceChanged() {
        guard LivingGlassPreferences.bounceOnSpaceSwitch else { return }
        for window in windows {
            if let view = window.contentView as? GameOfLifeView {
                view.triggerBounce()
            }
        }
    }

    @objc func togglePause() {
        manualPause.toggle()
        if manualPause {
            pause()
            pauseMenuItem.title = "Resume"
            statusItem.button?.title = "⏸"
        } else {
            // Only resume if low power mode isn't active
            if !ProcessInfo.processInfo.isLowPowerModeEnabled {
                resume()
            }
            pauseMenuItem.title = "Pause"
            statusItem.button?.title = "🧬"
        }
    }

    @objc func powerStateChanged() {
        checkPowerState()
    }

    // MARK: - Low Power Mode Detection

    private func checkPowerState() {
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        if isLowPower && !isPaused {
            pause()
        } else if !isLowPower && isPaused && !manualPause {
            resume()
        }
    }

    private func pause() {
        isPaused = true
        for window in windows {
            if let view = window.contentView as? GameOfLifeView {
                view.pause()
            }
        }
    }

    private func resume() {
        isPaused = false
        for window in windows {
            if let view = window.contentView as? GameOfLifeView {
                view.resume()
            }
        }
    }

    // MARK: - Wallpaper Management

    private func setCaviarWallpaper() {
        // Save original wallpapers, then set to caviar so space-switch flash matches
        let workspace = NSWorkspace.shared
        guard let caviarURL = Bundle.main.url(forResource: "caviar_bg", withExtension: "png") else { return }

        for screen in NSScreen.screens {
            if let current = workspace.desktopImageURL(for: screen) {
                originalWallpapers[screen] = current
            }
            try? workspace.setDesktopImageURL(caviarURL, for: screen, options: [:])
        }
    }

    private func restoreWallpapers() {
        let workspace = NSWorkspace.shared
        for (screen, url) in originalWallpapers {
            try? workspace.setDesktopImageURL(url, for: screen, options: [:])
        }
    }

    @objc func showPreferences() {
        PreferencesWindowController.shared.onApply = { [weak self] in
            self?.applyPreferences()
        }
        PreferencesWindowController.shared.showPreferences()
    }

    private func applyPreferences() {
        // Rebuild all windows with new settings
        for w in windows {
            if let view = w.contentView as? GameOfLifeView {
                view.applyPreferences()
            }
        }
    }

    @objc func quit() {
        powerTimer?.invalidate()
        restoreWallpapers()
        NSApp.terminate(nil)
    }
}
