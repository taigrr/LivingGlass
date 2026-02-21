import AppKit
import IOKit.ps

class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    var statusItem: NSStatusItem!
    var powerTimer: Timer?
    var isPaused = false
    var manualPause = false
    var pauseMenuItem: NSMenuItem!

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
        menu.addItem(pauseMenuItem)
        menu.addItem(NSMenuItem(title: "Reset", action: #selector(resetAll), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit LivingGlass", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

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
    }

    private func createWindow(for screen: NSScreen) {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.backgroundColor = NSColor(hex: 0x121117)

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
                view.engine.randomize()
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

    @objc func quit() {
        powerTimer?.invalidate()
        NSApp.terminate(nil)
    }
}
