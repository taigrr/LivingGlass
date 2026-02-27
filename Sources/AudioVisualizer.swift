import Foundation

// MARK: - Multi-Layer Audio Visualizer

class AudioVisualizer {
    let w: Int
    let h: Int
    private let cellCount: Int

    // Per-cell random phase offsets (break up grid uniformity)
    private var phaseOffsets: [Float]

    // Beat detection state
    private var runningBassAvg: Float = 0.15
    private var lastBeatTime: Float = -1.0
    private var beatPulse: Float = 0

    // Smooth output (exponential smoothing)
    private var heights: [Float]

    // Smoothing speed
    private let smoothUp: Float = 0.08
    private let smoothDown: Float = 0.04

    // EQ bar strip: fast attack, fast decay so bars pump visibly
    private let eqSmoothUp: Float = 0.35
    private let eqSmoothDown: Float = 0.15

    // EQ strip config
    private let eqStripWidth: Int = 5
    private let eqStripCenter: Int
    private let numBands: Int = 32

    // MARK: - Init

    init(width: Int, height: Int) {
        self.w = width
        self.h = height
        self.cellCount = width * height

        let maxDepth = width + height - 2
        eqStripCenter = Int(Float(maxDepth) * 0.65)

        phaseOffsets = (0..<cellCount).map { _ in Float.random(in: 0...(Float.pi * 2)) }
        heights = [Float](repeating: 0, count: cellCount)
    }

    // MARK: - Public API

    func height(atX x: Int, y: Int) -> Float {
        return heights[x * h + y]
    }

    func isEQBar(atX x: Int, y: Int) -> Bool {
        let depth = x + y
        return abs(depth - eqStripCenter) <= eqStripWidth / 2
    }

    func update(audio: AudioLevels, time: Float, dt: Float, eqMin: Float, eqMax: Float) {
        detectBeat(audio: audio, time: time)

        beatPulse *= 0.96

        let eqRange = eqMax - eqMin
        let rms = audio.rms
        let bass = audio.bass
        let halfStrip = eqStripWidth / 2
        let bandCount = audio.bands.count  // 32

        for x in 0..<w {
            for y in 0..<h {
                let idx = x * h + y
                let phase = phaseOffsets[idx]
                let eqPos = eqRange > 0 ? (Float(x - y) - eqMin) / eqRange : 0.5

                let depth = x + y
                let distFromStrip = abs(depth - eqStripCenter)

                let target: Float

                if distFromStrip <= halfStrip {
                    // === EQ BAR STRIP ===
                    // Map each column to a DISCRETE band index (no interpolation)
                    let bandIdx = max(0, min(bandCount - 1, Int(eqPos * Float(bandCount))))
                    let bandE = audio.bands[bandIdx]

                    // Band energy drives bar height
                    let barH = bandE * 2.0

                    // Taper edges of strip
                    let stripFade = 1.0 - Float(distFromStrip) / Float(halfStrip + 1)
                    target = max(barH * stripFade, 0)

                    let current = heights[idx]
                    if target > current {
                        heights[idx] = current + (target - current) * eqSmoothUp
                    } else {
                        heights[idx] = current + (target - current) * eqSmoothDown
                    }
                } else if depth > eqStripCenter + halfStrip {
                    // === IN FRONT OF EQ STRIP — low but not flat ===
                    let terrain = organicTerrain(x: x, y: y, time: time, phase: phase)
                    let shimmer = sinf(time * 2.0 + phase) * 0.015
                    let beatH = beatPulse * (0.5 + sinf(phase) * 0.5) * 0.05

                    target = max(terrain * (0.08 + rms * 0.08) + shimmer + beatH, 0)

                    let current = heights[idx]
                    if target > current {
                        heights[idx] = current + (target - current) * smoothUp
                    } else {
                        heights[idx] = current + (target - current) * smoothDown
                    }
                } else {
                    // === BEHIND EQ STRIP — ambient terrain ===
                    let terrain = organicTerrain(x: x, y: y, time: time, phase: phase)
                    let bandE = audio.bandEnergy(at: eqPos)
                    let spectrum = bandE * bandE * 0.15
                    let beatH = beatPulse * (0.5 + sinf(phase) * 0.5) * 0.1
                    let throb = bass * bass * 0.1
                    let shimmer = sinf(time * 2.0 + phase) * 0.02

                    target = max(
                        terrain * (0.1 + rms * 0.15)
                        + spectrum
                        + beatH
                        + throb
                        + shimmer,
                        0)

                    let current = heights[idx]
                    if target > current {
                        heights[idx] = current + (target - current) * smoothUp
                    } else {
                        heights[idx] = current + (target - current) * smoothDown
                    }
                }
            }
        }
    }

    // MARK: - Organic Terrain

    private func organicTerrain(x: Int, y: Int, time: Float, phase: Float) -> Float {
        let fx = Float(x)
        let fy = Float(y)

        let p = phase * 0.3
        let s1 = sinf(fx * 0.15 + time * 0.4 + fy * 0.08 + p) * 0.5 + 0.5
        let s2 = sinf(fy * 0.12 - time * 0.25 + fx * 0.1 + p * 1.3) * 0.5 + 0.5
        let s3 = sinf((fx + fy) * 0.09 + time * 0.5 + p * 0.7) * 0.5 + 0.5
        let s4 = sinf((fx - fy) * 0.11 - time * 0.35 + p * 1.1) * 0.5 + 0.5
        let s5 = sinf(fx * 0.07 + fy * 0.13 + time * 0.2 + p * 0.9) * 0.5 + 0.5

        let wf = Float(w)
        let hf = Float(h)
        let ex = min(fx, wf - fx) / (wf * 0.15)
        let ey = min(fy, hf - fy) / (hf * 0.15)
        let edgeFade = min(min(ex, ey), 1.0) * 0.7 + 0.3

        return (s1 * 0.3 + s2 * 0.25 + s3 * 0.2 + s4 * 0.15 + s5 * 0.1) * edgeFade
    }

    // MARK: - Beat Detection

    private func detectBeat(audio: AudioLevels, time: Float) {
        let bass = audio.bass
        runningBassAvg = runningBassAvg * 0.93 + bass * 0.07

        let threshold = runningBassAvg * 1.5 + 0.06
        let cooldown: Float = 0.25

        if bass > threshold && (time - lastBeatTime) > cooldown {
            lastBeatTime = time
            beatPulse = min(beatPulse + 0.6 + bass * 0.4, 1.2)
        }
    }
}
