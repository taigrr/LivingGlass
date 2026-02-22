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
    let precomputeQueue = DispatchQueue(label: "com.taigrr.livingglass.precompute", qos: .utility)

    // Metal
    var mtkView: MTKView!
    var renderer: MetalRenderer?

    // Grid origin for centering
    var originX: CGFloat = 0
    var originY: CGFloat = 0

    // Bounce effect on space switch
    var bounceTime: CGFloat = -1  // <0 means no bounce active

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
        mtkView.frame = bounds
    }

    // MARK: - Grid Setup

    private func initGrid() {
        let screenW = bounds.width
        let screenH = bounds.height

        let targetTilesAcross = CGFloat(LivingGlassPreferences.tileCount)
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

    private func renderFrame() {
        frameCount += 1
        globalTime += 1.0 / 60.0

        if frameCount % gameTickEvery == 0 {
            applyNextDiff()
            refillIfNeeded()
        }

        updateAnimations()
        buildAndRender()
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
        guard diffQueue.count < refillThreshold && !isPrecomputing else { return }
        isPrecomputing = true
        precomputeQueue.async { [weak self] in
            guard let self = self else { return }
            let diffs = self.engine.precompute(steps: self.precomputeBatchSize)
            DispatchQueue.main.async {
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
        for x in 0..<engine.width {
            for y in 0..<engine.height {
                switch anims[x][y].state {
                case .spawning:
                    anims[x][y].progress += 0.02
                    if anims[x][y].progress >= 1.0 {
                        anims[x][y].state = .alive
                        anims[x][y].progress = 0
                        anims[x][y].age = 0
                    }
                case .alive:
                    anims[x][y].age += 1
                case .dying:
                    anims[x][y].progress += 0.015
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

    private func buildAndRender() {
        guard let renderer = renderer else { return }

        let halfW = tileW / 2
        let halfH = tileH / 2
        let w = engine.width, h = engine.height
        let palette = MetalRenderer.faceColors
        let bScale = Float(bounceScale)

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
                    let bob = sin(globalTime * 0.12 + anim.bobPhase) * 2.0
                    let breathe = sin(globalTime * 0.08 + anim.bobPhase * 0.7) * 0.5
                    let cubeH = Float(maxCubeH + breathe)

                    let px = Float(baseSX)
                    let py = Float(baseSY + bob)

                    // Brighten with age
                    let ageFactor = min(Float(anim.age) / 180.0, 1.0)
                    let bright = 1.0 + ageFactor * 0.15
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
        mtkView.draw()
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
