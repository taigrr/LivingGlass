import AppKit
import simd

// MARK: - Color Tint (multiply/add/saturation transform)

struct ColorTint {
    var multiply: SIMD3<Float>
    var add: SIMD3<Float>
    var saturation: Float

    static let identity = ColorTint(
        multiply: SIMD3<Float>(1, 1, 1),
        add: SIMD3<Float>(0, 0, 0),
        saturation: 1.0
    )

    static func lerp(_ a: ColorTint, _ b: ColorTint, t: Float) -> ColorTint {
        let t = max(0, min(1, t))
        return ColorTint(
            multiply: a.multiply + (b.multiply - a.multiply) * t,
            add: a.add + (b.add - a.add) * t,
            saturation: a.saturation + (b.saturation - a.saturation) * t
        )
    }
}

// MARK: - Audio Levels (shared type for both app and screen saver)

struct AudioLevels {
    var rms: Float = 0
    var bass: Float = 0
    var mid: Float = 0
    var high: Float = 0
    var peak: Float = 0
    /// 32 frequency bands (sub-bass → air), smoothed for equalizer display
    var bands: [Float] = [Float](repeating: 0, count: 32)

    static let zero = AudioLevels()

    /// Interpolate band energy for a normalized position (0=lowest freq, 1=highest)
    func bandEnergy(at position: Float) -> Float {
        let count = Float(bands.count)
        let idx = position * (count - 1)
        let lo = Int(idx)
        let hi = min(lo + 1, bands.count - 1)
        let frac = idx - Float(lo)
        return bands[max(0, lo)] * (1 - frac) + bands[min(hi, bands.count - 1)] * frac
    }
}

// MARK: - Shared Palette Manager

class ColorManager {
    static let shared = ColorManager()

    private(set) var faceColors: [FaceRGB]
    private let basePalette: [NSColor] = GameEngine.palette

    private init() {
        faceColors = ColorManager.computeFaceColors(from: GameEngine.palette, tint: .identity)
    }

    func applyTint(_ tint: ColorTint) {
        faceColors = ColorManager.computeFaceColors(from: basePalette, tint: tint)
    }

    static func computeFaceColors(from palette: [NSColor], tint: ColorTint) -> [FaceRGB] {
        return palette.map { color in
            let c = color.usingColorSpace(.sRGB) ?? color
            var r = Float(c.redComponent)
            var g = Float(c.greenComponent)
            var b = Float(c.blueComponent)

            // Apply saturation adjustment
            if tint.saturation != 1.0 {
                let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
                r = lum + (r - lum) * tint.saturation
                g = lum + (g - lum) * tint.saturation
                b = lum + (b - lum) * tint.saturation
            }

            // Apply multiply
            r *= tint.multiply.x
            g *= tint.multiply.y
            b *= tint.multiply.z

            // Apply add
            r += tint.add.x
            g += tint.add.y
            b += tint.add.z

            // Clamp
            r = max(0, min(1, r))
            g = max(0, min(1, g))
            b = max(0, min(1, b))

            return FaceRGB(
                top: SIMD3<Float>(min(r * 1.3, 1), min(g * 1.3, 1), min(b * 1.3, 1)),
                left: SIMD3<Float>(r * 0.7, g * 0.7, b * 0.7),
                right: SIMD3<Float>(r * 0.45, g * 0.45, b * 0.45)
            )
        }
    }
}
