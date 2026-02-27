import AppKit
import SwiftUI

// MARK: - User Preferences

struct LivingGlassPreferences {
    static let defaults = UserDefaults.standard

    enum Key: String {
        case gameSpeed = "LG_GameSpeed"
        case tileCount = "LG_TileCount"
        case cubeHeight = "LG_CubeHeight"
        case colorScheme = "LG_ColorScheme"
        case launchAtLogin = "LG_LaunchAtLogin"
        case bounceOnSpaceSwitch = "LG_BounceOnSpaceSwitch"
        case audioReactivityEnabled = "LG_AudioReactivityEnabled"
        case audioSensitivity = "LG_AudioSensitivity"
        case dayNightEnabled = "LG_DayNightEnabled"
    }

    /// Game tick interval in frames (lower = faster). Default: 120 (2 seconds at 60fps)
    static var gameSpeed: Int {
        get {
            let v = defaults.integer(forKey: Key.gameSpeed.rawValue)
            return v > 0 ? v : 120
        }
        set { defaults.set(newValue, forKey: Key.gameSpeed.rawValue) }
    }

    /// Number of tiles across the screen width. Default: 20
    static var tileCount: Int {
        get {
            let v = defaults.integer(forKey: Key.tileCount.rawValue)
            return v > 0 ? v : 20
        }
        set { defaults.set(newValue, forKey: Key.tileCount.rawValue) }
    }

    /// Cube height as percentage of tile width (10-100). Default: 55
    static var cubeHeight: Int {
        get {
            let v = defaults.integer(forKey: Key.cubeHeight.rawValue)
            return v > 0 ? v : 55
        }
        set { defaults.set(newValue, forKey: Key.cubeHeight.rawValue) }
    }

    /// Color scheme name. Default: "charmtone"
    static var colorScheme: String {
        get { defaults.string(forKey: Key.colorScheme.rawValue) ?? "charmtone" }
        set { defaults.set(newValue, forKey: Key.colorScheme.rawValue) }
    }

    /// Launch at login. Default: false
    static var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin.rawValue) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin.rawValue) }
    }

    /// Bounce effect on space switch. Default: true
    static var bounceOnSpaceSwitch: Bool {
        get {
            if defaults.object(forKey: Key.bounceOnSpaceSwitch.rawValue) == nil { return true }
            return defaults.bool(forKey: Key.bounceOnSpaceSwitch.rawValue)
        }
        set { defaults.set(newValue, forKey: Key.bounceOnSpaceSwitch.rawValue) }
    }

    /// Audio reactivity enabled. Default: false
    static var audioReactivityEnabled: Bool {
        get { defaults.bool(forKey: Key.audioReactivityEnabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.audioReactivityEnabled.rawValue) }
    }

    /// Audio sensitivity: 0=low, 1=medium, 2=high. Default: 1
    static var audioSensitivity: Int {
        get {
            if defaults.object(forKey: Key.audioSensitivity.rawValue) == nil { return 1 }
            return defaults.integer(forKey: Key.audioSensitivity.rawValue)
        }
        set { defaults.set(newValue, forKey: Key.audioSensitivity.rawValue) }
    }

    /// Day/night color theme enabled. Default: true
    static var dayNightEnabled: Bool {
        get {
            if defaults.object(forKey: Key.dayNightEnabled.rawValue) == nil { return true }
            return defaults.bool(forKey: Key.dayNightEnabled.rawValue)
        }
        set { defaults.set(newValue, forKey: Key.dayNightEnabled.rawValue) }
    }
}

// MARK: - SwiftUI Preferences View

@available(macOS 13.0, *)
struct PreferencesView: View {
    @State private var gameSpeed: Double
    @State private var tileCount: Double
    @State private var cubeHeight: Double
    @State private var colorScheme: String
    @State private var bounceOnSpaceSwitch: Bool
    @State private var audioReactivityEnabled: Bool
    @State private var audioSensitivity: Int
    @State private var dayNightEnabled: Bool

    var onApply: (() -> Void)?

    static let speedLabels: [(String, Int)] = [
        ("Glacial", 240),
        ("Slow", 180),
        ("Default", 120),
        ("Fast", 60),
        ("Frantic", 30),
    ]

    static let colorSchemes = ["charmtone"]

    init(onApply: (() -> Void)? = nil) {
        self.onApply = onApply
        _gameSpeed = State(initialValue: Double(LivingGlassPreferences.gameSpeed))
        _tileCount = State(initialValue: Double(LivingGlassPreferences.tileCount))
        _cubeHeight = State(initialValue: Double(LivingGlassPreferences.cubeHeight))
        _colorScheme = State(initialValue: LivingGlassPreferences.colorScheme)
        _bounceOnSpaceSwitch = State(initialValue: LivingGlassPreferences.bounceOnSpaceSwitch)
        _audioReactivityEnabled = State(initialValue: LivingGlassPreferences.audioReactivityEnabled)
        _audioSensitivity = State(initialValue: LivingGlassPreferences.audioSensitivity)
        _dayNightEnabled = State(initialValue: LivingGlassPreferences.dayNightEnabled)
    }

    private var speedLabel: String {
        let closest = Self.speedLabels.min(by: {
            abs(Double($0.1) - gameSpeed) < abs(Double($1.1) - gameSpeed)
        })
        return closest?.0 ?? "Custom"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("LivingGlass")
                .font(.title2)
                .fontWeight(.semibold)

            GroupBox("Simulation") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Speed")
                            .frame(width: 80, alignment: .leading)
                        Slider(value: $gameSpeed, in: 30...240, step: 30)
                        Text(speedLabel)
                            .foregroundColor(.secondary)
                            .frame(width: 60)
                    }

                    HStack {
                        Text("Grid Size")
                            .frame(width: 80, alignment: .leading)
                        Slider(value: $tileCount, in: 10...40, step: 2)
                        Text("\(Int(tileCount)) tiles")
                            .foregroundColor(.secondary)
                            .frame(width: 60)
                    }

                    HStack {
                        Text("Cube Height")
                            .frame(width: 80, alignment: .leading)
                        Slider(value: $cubeHeight, in: 20...100, step: 5)
                        Text("\(Int(cubeHeight))%")
                            .foregroundColor(.secondary)
                            .frame(width: 60)
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox("Appearance") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Palette")
                            .frame(width: 80, alignment: .leading)
                        Picker("", selection: $colorScheme) {
                            ForEach(Self.colorSchemes, id: \.self) { scheme in
                                Text(scheme).tag(scheme)
                            }
                        }
                        .labelsHidden()
                    }

                    Toggle("Bounce on space switch", isOn: $bounceOnSpaceSwitch)
                }
                .padding(.vertical, 4)
            }

            GroupBox("Audio Reactivity") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable audio reactivity", isOn: $audioReactivityEnabled)

                    if audioReactivityEnabled {
                        HStack {
                            Text("Sensitivity")
                                .frame(width: 80, alignment: .leading)
                            Picker("", selection: $audioSensitivity) {
                                Text("Low").tag(0)
                                Text("Medium").tag(1)
                                Text("High").tag(2)
                            }
                            .pickerStyle(.segmented)
                        }

                        Text("Cubes will pulse and react to audio playing on your system.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox("Time of Day") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable day/night color theme", isOn: $dayNightEnabled)

                    Text("Palette shifts automatically — warm at dawn/dusk, cool at night.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            Divider()

            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    gameSpeed = 120
                    tileCount = 20
                    cubeHeight = 55
                    colorScheme = "charmtone"
                    bounceOnSpaceSwitch = true
                    audioReactivityEnabled = false
                    audioSensitivity = 1
                    dayNightEnabled = true
                    save()
                }
                .buttonStyle(.bordered)

                Button("Apply") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }

            Text("v1.0 — 0BSD License — Tai Groot")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 400)
    }

    private func save() {
        LivingGlassPreferences.gameSpeed = Int(gameSpeed)
        LivingGlassPreferences.tileCount = Int(tileCount)
        LivingGlassPreferences.cubeHeight = Int(cubeHeight)
        LivingGlassPreferences.colorScheme = colorScheme
        LivingGlassPreferences.bounceOnSpaceSwitch = bounceOnSpaceSwitch
        LivingGlassPreferences.audioReactivityEnabled = audioReactivityEnabled
        LivingGlassPreferences.audioSensitivity = audioSensitivity
        LivingGlassPreferences.dayNightEnabled = dayNightEnabled
        onApply?()
    }
}

// MARK: - Preferences Window Controller

class PreferencesWindowController {
    static let shared = PreferencesWindowController()

    private var window: NSWindow?
    var onApply: (() -> Void)?

    func showPreferences() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        if #available(macOS 13.0, *) {
            let prefsView = PreferencesView(onApply: { [weak self] in
                self?.onApply?()
            })
            let hostingView = NSHostingView(rootView: prefsView)
            hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 520)

            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "LivingGlass Preferences"
            w.contentView = hostingView
            w.center()
            w.isReleasedWhenClosed = false
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            window = w
        }
    }
}
