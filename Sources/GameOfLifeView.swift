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
    let gameTickEvery = 120
    var globalTime: CGFloat = 0

    // Metal
    var mtkView: MTKView!
    var renderer: MetalRenderer?

    // Grid origin for centering
    var originX: CGFloat = 0
    var originY: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true

        // Create MTKView
        mtkView = MTKView(frame: bounds)
        mtkView.autoresizingMask = [.width, .height]
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0x12/255.0, green: 0x11/255.0, blue: 0x17/255.0, alpha: 1)
        mtkView.isPaused = true           // We drive rendering manually
        mtkView.enableSetNeedsDisplay = false
        addSubview(mtkView)

        renderer = MetalRenderer(mtkView: mtkView)
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

        let targetTilesAcross: CGFloat = 20
        tileW = max(floor(screenW / targetTilesAcross), 24)
        tileH = floor(tileW / 4)
        maxCubeH = floor(tileW * 0.55)

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
            let old = engine.cells
            engine.step()
            syncAnimations(old: old)
        }

        updateAnimations()
        buildAndRender()
    }

    private func syncAnimations(old: [[Cell]]) {
        for x in 0..<engine.width {
            for y in 0..<engine.height {
                let was = old[x][y].alive
                let now = engine.cells[x][y].alive

                if !was && now {
                    anims[x][y].state = .spawning
                    anims[x][y].progress = 0
                    anims[x][y].colorIndex = engine.cells[x][y].colorIndex
                    anims[x][y].bobPhase = CGFloat.random(in: 0...(.pi * 2))
                    anims[x][y].age = 0
                } else if was && !now {
                    anims[x][y].state = .dying
                    anims[x][y].progress = 0
                }
            }
        }
    }

    private func updateAnimations() {
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

        // Use drawableSize for pixel-accurate positioning
        let drawableSize = mtkView.drawableSize
        let scaleX = CGFloat(drawableSize.width) / bounds.width
        let scaleY = CGFloat(drawableSize.height) / bounds.height

        var instances: [CubeInstance] = []
        instances.reserveCapacity(w * h / 3)  // rough estimate of visible cells

        // Back-to-front: decreasing (x+y) since Y is flipped
        for y in stride(from: h - 1, through: 0, by: -1) {
            for x in stride(from: w - 1, through: 0, by: -1) {
                let anim = anims[x][y]
                if anim.state == .empty { continue }

                let baseSX = originX + CGFloat(x - y) * halfW
                let baseSY = originY - CGFloat(x + y) * halfH

                let faces = palette[anim.colorIndex]

                switch anim.state {
                case .spawning:
                    let t = anim.progress
                    let eased = easeOutBack(t)
                    let scale = max(eased, 0.01)
                    let cubeH = Float(maxCubeH * scale)
                    let alpha = Float(min(t * 2.5, 1.0))

                    let px = Float(baseSX * scaleX)
                    let py = Float(baseSY * scaleY)

                    instances.append(CubeInstance(
                        posHeightScale: SIMD4<Float>(px, py, cubeH, Float(scale * tileW)),
                        topColor: SIMD4<Float>(faces.top, alpha),
                        leftColor: SIMD4<Float>(faces.left, 0),
                        rightColor: SIMD4<Float>(faces.right, 0)
                    ))

                case .alive:
                    let bob = sin(globalTime * 0.12 + anim.bobPhase) * 2.0
                    let breathe = sin(globalTime * 0.08 + anim.bobPhase * 0.7) * 0.5
                    let cubeH = Float(maxCubeH + breathe)

                    let px = Float(baseSX * scaleX)
                    let py = Float((baseSY + bob) * scaleY)

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
                        posHeightScale: SIMD4<Float>(px, py, cubeH, Float(tileW)),
                        topColor: SIMD4<Float>(top, 1.0),
                        leftColor: SIMD4<Float>(left, 0),
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

                        let px = Float((baseSX + wobX) * scaleX)
                        let py = Float((baseSY + wobY) * scaleY)

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
                            posHeightScale: SIMD4<Float>(px, py, Float(maxCubeH), Float(tileW)),
                            topColor: SIMD4<Float>(top, 1.0),
                            leftColor: SIMD4<Float>(left, 0),
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

                        let px = Float((baseSX + tumbleX) * scaleX)
                        let py = Float((baseSY - fallDist) * scaleY)

                        // Fade toward background
                        let ef = Float(eased * 0.5)
                        let top = SIMD3<Float>(faces.top.x * (1 - ef), faces.top.y * (1 - ef), faces.top.z * (1 - ef))
                        let left = SIMD3<Float>(faces.left.x * (1 - ef), faces.left.y * (1 - ef), faces.left.z * (1 - ef))
                        let right = SIMD3<Float>(faces.right.x * (1 - ef), faces.right.y * (1 - ef), faces.right.z * (1 - ef))

                        instances.append(CubeInstance(
                            posHeightScale: SIMD4<Float>(px, py, cubeH, Float(tileW * shrink)),
                            topColor: SIMD4<Float>(top, alpha),
                            leftColor: SIMD4<Float>(left, 0),
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
    }

    func pause() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    func resume() {
        guard displayTimer == nil else { return }
        startTimer()
    }

    func resize(to size: NSSize) {
        initGrid()
    }

    deinit {
        displayTimer?.invalidate()
    }
}
