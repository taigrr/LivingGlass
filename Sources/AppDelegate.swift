import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.title = "🧬"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Reset", action: #selector(resetAll), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Life Wallpaper", action: #selector(quit), keyEquivalent: "q"))
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

    @objc func quit() {
        NSApp.terminate(nil)
    }
}
