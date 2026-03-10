import Foundation

// MARK: - Day/Night Theme

class DayNightTheme {
    static let shared = DayNightTheme()

    private var timer: Timer?

    // Phase boundaries (hours as decimals)
    // Night: 20:00 - 05:30, Dawn: 05:30 - 08:30, Day: 08:30 - 16:30, Dusk: 16:30 - 20:00
    private let nightEnd: Float = 5.5    // 5:30 AM
    private let dawnEnd: Float = 8.5     // 8:30 AM
    private let dayEnd: Float = 16.5     // 4:30 PM
    private let duskEnd: Float = 20.0    // 8:00 PM

    // Transition duration in hours
    private let transitionDuration: Float = 1.0

    // Phase tints
    private let nightTint = ColorTint(
        multiply: SIMD3<Float>(0.7, 0.75, 1.15),
        add: SIMD3<Float>(0, 0, 0),
        saturation: 1.15
    )

    private let dawnTint = ColorTint(
        multiply: SIMD3<Float>(1.1, 1.0, 0.85),
        add: SIMD3<Float>(0, 0, 0),
        saturation: 0.85
    )

    private let dayTint = ColorTint.identity

    private let duskTint = ColorTint(
        multiply: SIMD3<Float>(1.1, 0.85, 0.8),
        add: SIMD3<Float>(0, 0, 0),
        saturation: 1.05
    )

    private init() {}

    func start() {
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.update()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func update() {
        guard LivingGlassPreferences.dayNightEnabled else {
            ColorManager.shared.applyTint(.identity)
            return
        }
        let tint = currentTint()
        ColorManager.shared.applyTint(tint)
    }

    private func currentHour() -> Float {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: Date())
        return Float(comps.hour ?? 12) + Float(comps.minute ?? 0) / 60.0
    }

    private func currentTint() -> ColorTint {
        let hour = currentHour()
        let halfT = transitionDuration / 2.0

        // Transition zones (centered on boundary):
        // night→dawn around nightEnd (5:30), dawn→day around dawnEnd (8:30),
        // day→dusk around dayEnd (16:30), dusk→night around duskEnd (20:00)

        // Night→Dawn transition
        if hour >= nightEnd - halfT && hour <= nightEnd + halfT {
            let t = (hour - (nightEnd - halfT)) / transitionDuration
            return ColorTint.lerp(nightTint, dawnTint, t: t)
        }
        // Dawn→Day transition
        if hour >= dawnEnd - halfT && hour <= dawnEnd + halfT {
            let t = (hour - (dawnEnd - halfT)) / transitionDuration
            return ColorTint.lerp(dawnTint, dayTint, t: t)
        }
        // Day→Dusk transition
        if hour >= dayEnd - halfT && hour <= dayEnd + halfT {
            let t = (hour - (dayEnd - halfT)) / transitionDuration
            return ColorTint.lerp(dayTint, duskTint, t: t)
        }
        // Dusk→Night transition
        if hour >= duskEnd - halfT && hour <= duskEnd + halfT {
            let t = (hour - (duskEnd - halfT)) / transitionDuration
            return ColorTint.lerp(duskTint, nightTint, t: t)
        }

        // Solid phases
        if hour > nightEnd + halfT && hour < dawnEnd - halfT {
            return dawnTint
        }
        if hour >= dawnEnd + halfT && hour < dayEnd - halfT {
            return dayTint
        }
        if hour >= dayEnd + halfT && hour < duskEnd - halfT {
            return duskTint
        }
        // Night (after dusk or before dawn)
        return nightTint
    }
}
