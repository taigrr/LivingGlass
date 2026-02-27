import AppKit
import MetalKit

// MARK: - Per-Cell Animation State

struct CellAnim {
    enum State { case empty, spawning, alive, dying }

    var state: State = .empty
    var progress: CGFloat = 0
    var colorIndex: Int = 0
    var bobPhase: CGFloat = 0
    var age: Int = 0
}

// MARK: - Metal-backed Isometric Game of Life View

class GameOfLifeView: NSView {
    // Tile geometry (dynamic, computed from screen size)
    var tileW: CGFloat = 72
    var tileH: CGFloat = 18
    var maxCubeH: CGFloat = 40

    // Grid & animation
    var engine: GameEngine!
    var anims: [[CellAnim]] = []

    // Render loop
    var displayTimer: Timer?
    var frameCount: Int = 0
    var gameTickEvery = 120
    var globalTime: CGFloat = 0

    // Precomputed game state diffs
    var diffQueue: [GameDiff] = []
    let precomputeBatchSize = 1000
    let refillThreshold = 100
    var isPrecomputing = false
    var isStopped = false
    let precomputeQueue = DispatchQueue(label: "com.taigrr.livingglass.precompute", qos: .utility)

    // Metal
    var mtkView: MTKView!
    var renderer: MetalRenderer?

    // Grid origin for centering
    var originX: CGFloat = 0
    var originY: CGFloat = 0

    // Bounce effect on space switch
    var bounceTime: CGFloat = -1  // <0 means no bounce active

    // Audio: cached grid range for equalizer position mapping
    var eqRangeMin: Float = 0
    var eqRangeMax: Float = 1
    var wasInAudioMode = false

    // Audio visualizer (multi-layer effects engine)
    var visualizer: AudioVisualizer?

    // Bundle for loading resources (Metal shaders)
    var resourceBundle: Bundle = Bundle.main

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup(bundle: Bundle.main)
    }

    init(frame: NSRect, bundle: Bundle) {
        super.init(frame: frame)
        setup(bundle: bundle)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup(bundle: Bundle.main)
    }

    private func setup(bundle: Bundle) {
        resourceBundle = bundle
        wantsLayer = true

        // Create MTKView
        mtkView = MTKView(frame: bounds)
        mtkView.autoresizingMask = [.width, .height]
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0x12/255.0, green: 0x11/255.0, blue: 0x17/255.0, alpha: 1)
        mtkView.isPaused = true           // We drive rendering manually
        mtkView.enableSetNeedsDisplay = false
        mtkView.framebufferOnly = true

        addSubview(mtkView)

        renderer = MetalRenderer(mtkView: mtkView, bundle: bundle)
        mtkView.delegate = renderer

        // Trigger initial size
        if let renderer = renderer {
            renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
        }

        initGrid()
        startTimer()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        mtkView?.frame = bounds
    }

    // MARK: - Grid Setup

    private func initGrid(audioMode: Bool = false) {
        let screenW = bounds.width
        let screenH = bounds.height

        let baseTiles = CGFloat(LivingGlassPreferences.tileCount)
        // Audio mode: ~60% as many tiles → bigger, chunkier cubes
        let targetTilesAcross = audioMode ? max(baseTiles * 0.6, 8) : baseTiles
        tileW = max(floor(screenW / targetTilesAcross), 24)
        tileH = floor(tileW / 4)
        let cubeHeightPct = CGFloat(LivingGlassPreferences.cubeHeight) / 100.0
        maxCubeH = floor(tileW * cubeHeightPct)

        let diagonal = sqrt(screenW * screenW + screenH * screenH)
        let nForWidth = Int(ceil(diagonal / tileW)) + 4
        let nForHeight = Int(ceil(diagonal / tileH)) + 4
        let gridSize = max(max(nForWidth, nForHeight), 20)

        engine = GameEngine(width: gridSize, height: gridSize)
        anims = Array(repeating: Array(repeating: CellAnim(), count: gridSize), count: gridSize)

        originX = bounds.midX
        let visualHeight = CGFloat(gridSize * 2) * (tileH / 2) + maxCubeH
        originY = bounds.midY + visualHeight / 2

        // Sync initial state
        for x in 0..<gridSize {
            for y in 0..<gridSize {
                if engine.cells[x][y].alive {
                    anims[x][y].state = .alive
                    anims[x][y].colorIndex = engine.cells[x][y].colorIndex
                    anims[x][y].bobPhase = CGFloat.random(in: 0...(.pi * 2))
                    anims[x][y].age = Int.random(in: 0...60)
                }
            }
        }

        renderer?.tileW = Float(tileW)
        renderer?.tileH = Float(tileH)

        // Cache equalizer range: screen-horizontal axis is (x - y)
        eqRangeMin = Float(-(gridSize - 1))
        eqRangeMax = Float(gridSize - 1)

        // Precompute initial batch
        diffQueue = engine.precompute(steps: precomputeBatchSize)
    }

    // MARK: - Render Loop

    private func startTimer() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.renderFrame()
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private var isAudioMode: Bool {
        #if LIVINGGLASS_APP
        return LivingGlassPreferences.audioReactivityEnabled && AudioReactor.shared.isRunning
        #else
        return false
        #endif
    }

    private func renderFrame() {
        guard !isStopped else { return }
        frameCount += 1
        globalTime += 1.0 / 60.0

        let audioMode = isAudioMode
        if audioMode {
            if !wasInAudioMode {
                wasInAudioMode = true
                enterAudioMode()
            }
            // Update the visualizer each frame (all layers + spring physics)
            let dt: Float = 1.0 / 60.0
            let audio = currentAudioLevels
            visualizer?.update(audio: audio, time: Float(globalTime), dt: dt,
                               eqMin: eqRangeMin, eqMax: eqRangeMax)
        } else {
            if wasInAudioMode {
                wasInAudioMode = false
                visualizer = nil
                initGrid()  // rebuild with normal tile size
            }
            if frameCount % gameTickEvery == 0 {
                applyNextDiff()
                refillIfNeeded()
            }
        }

        updateAnimations()
        buildAndRender()
    }

    /// Transition into audio mode: rebuild grid with bigger tiles, create visualizer.
    private func enterAudioMode() {
        // Rebuild grid with larger tiles for audio mode
        initGrid(audioMode: true)

        let w = engine.width, h = engine.height
        let paletteCount = GameEngine.palette.count

        // Create the visualizer for the new grid size
        visualizer = AudioVisualizer(width: w, height: h)

        let centerX = Float(w) * 0.5
        let centerY = Float(h) * 0.5
        let maxDist = sqrtf(centerX * centerX + centerY * centerY)

        for x in 0..<w {
            for y in 0..<h {
                // Base color from frequency position + random scatter for variety
                let eqRange = eqRangeMax - eqRangeMin
                let eqPos = eqRange > 0 ? (Float(x - y) - eqRangeMin) / eqRange : 0.5
                let baseIdx = Int(eqPos * Float(paletteCount - 1))
                let scatter = Int.random(in: -4...4)
                let colorIdx = max(0, min(paletteCount - 1, baseIdx + scatter))

                // Stagger spawn by distance from center (center appears first)
                let dx = Float(x) - centerX
                let dy = Float(y) - centerY
                let dist = sqrtf(dx * dx + dy * dy)
                let stagger = CGFloat(dist / maxDist) * 0.85

                if anims[x][y].state == .empty || anims[x][y].state == .dying {
                    anims[x][y].state = .spawning
                    anims[x][y].progress = stagger
                }
                anims[x][y].colorIndex = colorIdx
                anims[x][y].bobPhase = CGFloat(Float.random(in: 0...(Float.pi * 2)))
                anims[x][y].age = 0
            }
        }
    }

    private func applyNextDiff() {
        guard !diffQueue.isEmpty else { return }
        let diff = diffQueue.removeFirst()

        for birth in diff.births {
            anims[birth.x][birth.y].state = .spawning
            anims[birth.x][birth.y].progress = 0
            anims[birth.x][birth.y].colorIndex = birth.colorIndex
            anims[birth.x][birth.y].bobPhase = CGFloat.random(in: 0...(.pi * 2))
            anims[birth.x][birth.y].age = 0
        }
        for death in diff.deaths {
            anims[death.x][death.y].state = .dying
            anims[death.x][death.y].progress = 0
        }
    }

    private func refillIfNeeded() {
        guard diffQueue.count < refillThreshold && !isPrecomputing && !isStopped else { return }
        isPrecomputing = true
        precomputeQueue.async { [weak self] in
            guard let self = self, !self.isStopped else { return }
            let diffs = self.engine.precompute(steps: self.precomputeBatchSize)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.isStopped else { return }
                self.diffQueue.append(contentsOf: diffs)
                self.isPrecomputing = false
            }
        }
    }

    /// Global scale multiplier from bounce effect (1.0 = no effect)
    private var bounceScale: CGFloat {
        guard bounceTime >= 0 else { return 1.0 }
        let t = min(bounceTime / 0.5, 1.0)  // 0.5s duration
        // Quick dip then overshoot back: 1.0 → 0.85 → 1.05 → 1.0
        let scale = 1.0 + sin(t * .pi * 2) * 0.15 * (1.0 - t)
        return scale
    }

    private func updateAnimations() {
        // Advance bounce
        if bounceTime >= 0 {
            bounceTime += 1.0 / 60.0
            if bounceTime > 0.5 { bounceTime = -1 }
        }
        let audioMode = isAudioMode
        for x in 0..<engine.width {
            for y in 0..<engine.height {
                switch anims[x][y].state {
                case .spawning:
                    anims[x][y].progress += audioMode ? 0.15 : 0.02
                    if anims[x][y].progress >= 1.0 {
                        anims[x][y].state = .alive
                        anims[x][y].progress = 0
                        anims[x][y].age = 0
                    }
                case .alive:
                    anims[x][y].age += 1
                case .dying:
                    anims[x][y].progress += audioMode ? 0.08 : 0.015
                    if anims[x][y].progress >= 1.0 {
                        anims[x][y].state = .empty
                        anims[x][y].progress = 0
                    }
                case .empty:
                    break
                }
            }
        }
    }

    // MARK: - Build Instance Buffer & Render

    private var currentAudioLevels: AudioLevels {
        #if LIVINGGLASS_APP
        return AudioReactor.shared.levels
        #else
        return AudioLevels.zero
        #endif
    }

    private func buildAndRender() {
        guard let renderer = renderer else { return }

        let halfW = tileW / 2
        let halfH = tileH / 2
        let w = engine.width, h = engine.height
        let palette = ColorManager.shared.faceColors
        let bScale = Float(bounceScale)
        let audio = currentAudioLevels
        let audioMode = isAudioMode

        // Use view coordinates consistently (shader maps to NDC via viewportSize)
        renderer.viewportSize = SIMD2<Float>(Float(bounds.width), Float(bounds.height))

        var instances: [CubeInstance] = []
        instances.reserveCapacity(w * h / 3)  // rough estimate of visible cells

        let maxDepth = Float(w + h - 2)

        for y in 0..<h {
            for x in 0..<w {
                let anim = anims[x][y]
                if anim.state == .empty { continue }

                let baseSX = originX + CGFloat(x - y) * halfW
                let baseSY = originY - CGFloat(x + y) * halfH

                // Normalized depth: 0=back (small x+y), 1=front (large x+y)
                let depth = maxDepth > 0 ? Float(x + y) / maxDepth : 0

                let faces = palette[anim.colorIndex]

                switch anim.state {
                case .spawning:
                    let t = anim.progress
                    let eased = easeOutBack(t)
                    let scale = max(eased, 0.01)
                    let cubeH = Float(maxCubeH * scale)
                    let alpha = Float(min(t * 2.5, 1.0))

                    // Offset Y so cube scales from its visual center (not bottom)
                    let centerOffset = Float(maxCubeH) * 0.5 * (1.0 - Float(scale))
                    let px = Float(baseSX)
                    let py = Float(baseSY) + centerOffset

                    instances.append(CubeInstance(
                        posHeightScale: SIMD4<Float>(px, py, cubeH * bScale, Float(scale * tileW) * bScale),
                        topColor: SIMD4<Float>(faces.top, alpha),
                        leftColor: SIMD4<Float>(faces.left, depth),
                        rightColor: SIMD4<Float>(faces.right, 0)
                    ))

                case .alive:
                    if audioMode {
                        // === AUDIO VISUALIZER MODE ===
                        let vizH = visualizer?.height(atX: x, y: y) ?? 0

                        if vizH < 0.02 { continue }

                        let isEQ = visualizer?.isEQBar(atX: x, y: y) ?? false

                        // EQ bars get taller range, ambient is subtler
                        let heightMult: Float = isEQ ? 3.0 : 1.5
                        let cubeH = vizH * Float(maxCubeH) * heightMult

                        let px = Float(baseSX)
                        let lift = cubeH * 0.25
                        let py = Float(baseSY) + lift

                        // Hue shift: tall cubes shift warm
                        let paletteCount = palette.count
                        let hueShift = Int(vizH * 2.5)
                        let dynIdx = max(0, min(paletteCount - 1, anim.colorIndex - hueShift))
                        let dynFaces = palette[dynIdx]

                        // EQ bars: brighter and more vivid; ambient: softer
                        let bright: Float = isEQ
                            ? 0.6 + vizH * 0.4
                            : 0.5 + vizH * 0.3

                        let glow = max(vizH - 1.0, 0) * (isEQ ? 2.0 : 1.5)
                        let tr = min(dynFaces.top.x * bright + glow * 0.15, 1.0)
                        let tg = min(dynFaces.top.y * bright + glow * 0.1, 1.0)
                        let tb = min(dynFaces.top.z * bright + glow * 0.05, 1.0)
                        let lr = min(dynFaces.left.x * bright + glow * 0.1, 1.0)
                        let lg = min(dynFaces.left.y * bright + glow * 0.06, 1.0)
                        let lb = min(dynFaces.left.z * bright + glow * 0.03, 1.0)
                        let rr = min(dynFaces.right.x * bright + glow * 0.06, 1.0)
                        let rg = min(dynFaces.right.y * bright + glow * 0.04, 1.0)
                        let rb = min(dynFaces.right.z * bright + glow * 0.02, 1.0)

                        instances.append(CubeInstance(
                            posHeightScale: SIMD4<Float>(px, py, cubeH * bScale, Float(tileW) * bScale),
                            topColor: SIMD4<Float>(SIMD3<Float>(tr, tg, tb), 1.0),
                            leftColor: SIMD4<Float>(SIMD3<Float>(lr, lg, lb), depth),
                            rightColor: SIMD4<Float>(SIMD3<Float>(rr, rg, rb), 0)
                        ))
                    } else {
                        // === GAME OF LIFE MODE ===
                        let eqRange = eqRangeMax - eqRangeMin
                        let eqPos = eqRange > 0 ? (Float(x - y) - eqRangeMin) / eqRange : 0.5
                        let bandE = audio.bandEnergy(at: eqPos)

                        let bob = sin(globalTime * 0.12 + anim.bobPhase) * 2.0
                        let breathe = sin(globalTime * 0.08 + anim.bobPhase * 0.7) * 0.5

                        let heightMult: Float = 1.0 + bandE * 1.2
                        let cubeH = Float(maxCubeH + breathe) * heightMult

                        let px = Float(baseSX)
                        let audioLift = CGFloat(bandE) * maxCubeH * 0.3
                        let py = Float(baseSY + bob + audioLift)

                        // Brighten with age + glow from band energy
                        let ageFactor = min(Float(anim.age) / 180.0, 1.0)
                        let bright = 1.0 + ageFactor * 0.15 + bandE * 0.2
                        let top = SIMD3<Float>(min(faces.top.x * bright, 1),
                                               min(faces.top.y * bright, 1),
                                               min(faces.top.z * bright, 1))
                        let left = SIMD3<Float>(min(faces.left.x * bright, 1),
                                                min(faces.left.y * bright, 1),
                                                min(faces.left.z * bright, 1))
                        let right = SIMD3<Float>(min(faces.right.x * bright, 1),
                                                 min(faces.right.y * bright, 1),
                                                 min(faces.right.z * bright, 1))

                        instances.append(CubeInstance(
                            posHeightScale: SIMD4<Float>(px, py, cubeH * bScale, Float(tileW) * bScale),
                            topColor: SIMD4<Float>(top, 1.0),
                            leftColor: SIMD4<Float>(left, depth),
                            rightColor: SIMD4<Float>(right, 0)
                        ))
                    }

                case .dying:
                    let t = anim.progress

                    if t < 0.35 {
                        // Vibration phase
                        let vibT = t / 0.35
                        let intensity = vibT * 3.5
                        let wobX = CGFloat.random(in: -intensity...intensity)
                        let wobY = CGFloat.random(in: -intensity...intensity)

                        let px = Float(baseSX + wobX)
                        let py = Float(baseSY + wobY)

                        // Tint toward red
                        let vf = Float(vibT)
                        let top = SIMD3<Float>(min(faces.top.x + vf * 0.15, 1),
                                               faces.top.y * (1 - vf * 0.2),
                                               faces.top.z * (1 - vf * 0.3))
                        let left = SIMD3<Float>(min(faces.left.x + vf * 0.1, 1),
                                                faces.left.y * (1 - vf * 0.2),
                                                faces.left.z * (1 - vf * 0.3))
                        let right = SIMD3<Float>(min(faces.right.x + vf * 0.08, 1),
                                                  faces.right.y * (1 - vf * 0.2),
                                                  faces.right.z * (1 - vf * 0.3))

                        instances.append(CubeInstance(
                            posHeightScale: SIMD4<Float>(px, py, Float(maxCubeH) * bScale, Float(tileW) * bScale),
                            topColor: SIMD4<Float>(top, 1.0),
                            leftColor: SIMD4<Float>(left, depth),
                            rightColor: SIMD4<Float>(right, 0)
                        ))
                    } else {
                        // Falling phase
                        let fallT = (t - 0.35) / 0.65
                        let eased = easeInCubic(fallT)
                        let fallDist = eased * maxCubeH * 3.0
                        let alpha = Float(1.0 - eased)
                        let shrink = 1.0 - eased * 0.4
                        let cubeH = Float(maxCubeH * shrink)

                        let tumbleX = sin(fallT * 0.8) * (1.0 - fallT) * 3.0

                        let px = Float(baseSX + tumbleX)
                        let py = Float(baseSY - fallDist)

                        // Fade toward background
                        let ef = Float(eased * 0.5)
                        let top = SIMD3<Float>(faces.top.x * (1 - ef), faces.top.y * (1 - ef), faces.top.z * (1 - ef))
                        let left = SIMD3<Float>(faces.left.x * (1 - ef), faces.left.y * (1 - ef), faces.left.z * (1 - ef))
                        let right = SIMD3<Float>(faces.right.x * (1 - ef), faces.right.y * (1 - ef), faces.right.z * (1 - ef))

                        instances.append(CubeInstance(
                            posHeightScale: SIMD4<Float>(px, py, cubeH * bScale, Float(tileW * shrink) * bScale),
                            topColor: SIMD4<Float>(top, alpha),
                            leftColor: SIMD4<Float>(left, depth),
                            rightColor: SIMD4<Float>(right, 0)
                        ))
                    }

                case .empty:
                    break
                }
            }
        }

        renderer.updateInstances(instances)
        mtkView?.draw()
    }

    // MARK: - Easing

    private func easeOutBack(_ t: CGFloat) -> CGFloat {
        let c1: CGFloat = 1.70158
        let c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }

    private func easeInCubic(_ t: CGFloat) -> CGFloat {
        return t * t * t
    }

    // MARK: - Control

    func triggerBounce() {
        bounceTime = 0
    }

    func reset() {
        engine.randomize()
        for x in 0..<engine.width {
            for y in 0..<engine.height {
                if engine.cells[x][y].alive {
                    anims[x][y].state = .alive
                    anims[x][y].colorIndex = engine.cells[x][y].colorIndex
                    anims[x][y].bobPhase = CGFloat.random(in: 0...(.pi * 2))
                    anims[x][y].age = 0
                } else {
                    anims[x][y].state = .empty
                }
            }
        }
        // Precompute fresh batch
        diffQueue.removeAll()
        diffQueue = engine.precompute(steps: precomputeBatchSize)
    }

    func pause() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    func stop() {
        isStopped = true
        pause()
        mtkView?.isPaused = true
        mtkView?.delegate = nil
    }

    func resume() {
        guard displayTimer == nil else { return }
        startTimer()
    }

    func applyPreferences() {
        gameTickEvery = LivingGlassPreferences.gameSpeed
        initGrid()
    }

    func resize(to size: NSSize) {
        initGrid()
    }

    deinit {
        displayTimer?.invalidate()
    }
}
