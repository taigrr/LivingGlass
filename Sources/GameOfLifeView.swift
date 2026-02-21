import AppKit

// MARK: - Per-Cell Animation State

struct CellAnim {
    enum State { case empty, spawning, alive, dying }

    var state: State = .empty
    var progress: CGFloat = 0       // 0→1 for spawning/dying transitions
    var colorIndex: Int = 0
    var bobPhase: CGFloat = 0       // random offset for idle floating
    var age: Int = 0
}

// MARK: - Precomputed Face Colors

struct CubeFaces {
    let topR: CGFloat, topG: CGFloat, topB: CGFloat
    let leftR: CGFloat, leftG: CGFloat, leftB: CGFloat
    let rightR: CGFloat, rightG: CGFloat, rightB: CGFloat
}

// MARK: - Isometric Game of Life View

class GameOfLifeView: NSView {
    // Isometric geometry
    let tileW: CGFloat = 18
    let tileH: CGFloat = 9
    let maxCubeH: CGFloat = 14

    // Grid & animation
    var engine: GameEngine!
    var anims: [[CellAnim]] = []

    // Render loop
    var displayTimer: Timer?
    var frameCount: Int = 0
    let gameTickEvery = 6           // game steps every 6 render frames (~10/sec at 60fps)
    var globalTime: CGFloat = 0

    // Precomputed
    static let bgColor = NSColor(hex: 0x121117).cgColor
    static let bgNSColor = NSColor(hex: 0x121117)
    static let faceColors: [CubeFaces] = GameEngine.palette.map { color in
        let c = color.usingColorSpace(.sRGB) ?? color
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        return CubeFaces(
            topR: min(r * 1.3, 1), topG: min(g * 1.3, 1), topB: min(b * 1.3, 1),
            leftR: r * 0.7, leftG: g * 0.7, leftB: b * 0.7,
            rightR: r * 0.45, rightG: g * 0.45, rightB: b * 0.45
        )
    }

    // Grid origin for centering
    var originX: CGFloat = 0
    var originY: CGFloat = 0

    override var isOpaque: Bool { true }

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
        layer?.backgroundColor = Self.bgColor
        layer?.drawsAsynchronously = true
        initGrid()
        startTimer()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let scale = window?.backingScaleFactor {
            layer?.contentsScale = scale
        }
    }

    // MARK: - Grid Setup

    private func initGrid() {
        let halfW = tileW / 2
        let halfH = tileH / 2

        // For a square grid of side n, the isometric diamond is:
        //   width  = 2n * halfW = n * tileW
        //   height = 2n * halfH + maxCubeH = n * tileH + maxCubeH
        let n = min(
            Int(bounds.width / tileW),
            Int((bounds.height - maxCubeH) / tileH)
        )
        let gridSize = max(min(n, 90), 10)

        engine = GameEngine(width: gridSize, height: gridSize)
        anims = Array(repeating: Array(repeating: CellAnim(), count: gridSize), count: gridSize)

        // Center the grid
        let w = gridSize, h = gridSize
        originX = bounds.midX - CGFloat(w - h) * halfW / 2
        let visualHeight = CGFloat(w + h) * halfH + maxCubeH + halfH
        originY = bounds.midY - visualHeight / 2 + maxCubeH + halfH

        // Sync initial engine state to animation
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
    }

    // MARK: - Render Loop

    private func startTimer() {
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.renderFrame()
        }
    }

    private func renderFrame() {
        frameCount += 1
        globalTime += 1.0 / 60.0

        // Step game logic at slower rate
        if frameCount % gameTickEvery == 0 {
            let old = engine.cells
            engine.step()
            syncAnimations(old: old)
        }

        updateAnimations()
        needsDisplay = true
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
                    anims[x][y].progress += 0.055
                    if anims[x][y].progress >= 1.0 {
                        anims[x][y].state = .alive
                        anims[x][y].progress = 0
                        anims[x][y].age = 0
                    }
                case .alive:
                    anims[x][y].age += 1
                case .dying:
                    anims[x][y].progress += 0.022
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

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(Self.bgColor)
        ctx.fill(bounds)

        let halfW = tileW / 2
        let halfH = tileH / 2
        let w = engine.width, h = engine.height

        // Draw back-to-front (increasing y, then increasing x)
        for y in 0..<h {
            for x in 0..<w {
                let anim = anims[x][y]
                if anim.state == .empty { continue }

                let sx = originX + CGFloat(x - y) * halfW
                let sy = originY + CGFloat(x + y) * halfH
                let faces = Self.faceColors[anim.colorIndex]

                switch anim.state {
                case .spawning:
                    drawSpawning(ctx: ctx, sx: sx, sy: sy, anim: anim, faces: faces)
                case .alive:
                    drawAlive(ctx: ctx, sx: sx, sy: sy, anim: anim, faces: faces)
                case .dying:
                    drawDying(ctx: ctx, sx: sx, sy: sy, anim: anim, faces: faces)
                case .empty:
                    break
                }
            }
        }
    }

    private func drawSpawning(ctx: CGContext, sx: CGFloat, sy: CGFloat, anim: CellAnim, faces: CubeFaces) {
        let t = anim.progress
        let eased = easeOutBack(t)

        // Cube rises from below and grows to full height
        let cubeH = maxCubeH * max(eased, 0)
        let riseOffset = (1.0 - t) * 20.0  // starts 20px below, rises to position
        let alpha = min(t * 2.5, 1.0)

        ctx.saveGState()
        ctx.setAlpha(alpha)
        drawCube(ctx: ctx, sx: sx, sy: sy + riseOffset, cubeH: cubeH, faces: faces)
        ctx.restoreGState()
    }

    private func drawAlive(ctx: CGContext, sx: CGFloat, sy: CGFloat, anim: CellAnim, faces: CubeFaces) {
        // Gentle idle bob
        let bob = sin(globalTime * 1.2 + anim.bobPhase) * 2.0
        // Subtle breathing (cube height oscillation)
        let breathe = sin(globalTime * 0.8 + anim.bobPhase * 0.7) * 0.5
        drawCube(ctx: ctx, sx: sx, sy: sy - bob, cubeH: maxCubeH + breathe, faces: faces)
    }

    private func drawDying(ctx: CGContext, sx: CGFloat, sy: CGFloat, anim: CellAnim, faces: CubeFaces) {
        let t = anim.progress

        if t < 0.35 {
            // Phase 1: Vibration — cube shakes with increasing intensity
            let vibT = t / 0.35
            let intensity = vibT * 3.5
            let wobX = CGFloat.random(in: -intensity...intensity)
            let wobY = CGFloat.random(in: -intensity...intensity)

            // Tint toward red as it destabilizes
            let tintR = min(faces.topR + vibT * 0.15, 1.0)
            let tinted = CubeFaces(
                topR: tintR, topG: faces.topG * (1 - vibT * 0.2), topB: faces.topB * (1 - vibT * 0.3),
                leftR: min(faces.leftR + vibT * 0.1, 1), leftG: faces.leftG * (1 - vibT * 0.2), leftB: faces.leftB * (1 - vibT * 0.3),
                rightR: min(faces.rightR + vibT * 0.08, 1), rightG: faces.rightG * (1 - vibT * 0.2), rightB: faces.rightB * (1 - vibT * 0.3)
            )

            drawCube(ctx: ctx, sx: sx + wobX, sy: sy + wobY, cubeH: maxCubeH, faces: tinted)

        } else {
            // Phase 2: Fall — cube drops away and fades
            let fallT = (t - 0.35) / 0.65
            let eased = easeInCubic(fallT)
            let fallDist = eased * 80.0
            let alpha = 1.0 - eased
            let shrink = 1.0 - eased * 0.4
            let cubeH = maxCubeH * shrink

            // Slight tumble wobble during fall
            let tumbleX = sin(fallT * 8.0) * (1.0 - fallT) * 2.0

            ctx.saveGState()
            ctx.setAlpha(alpha)
            drawCube(ctx: ctx, sx: sx + tumbleX, sy: sy + fallDist, cubeH: cubeH, faces: faces)
            ctx.restoreGState()
        }
    }

    // MARK: - Cube Drawing

    private func drawCube(ctx: CGContext, sx: CGFloat, sy: CGFloat, cubeH: CGFloat, faces: CubeFaces) {
        let halfW = tileW / 2
        let halfH = tileH / 2

        guard cubeH > 0.5 else { return }

        // Top face (diamond)
        let topN = CGPoint(x: sx, y: sy - halfH - cubeH)
        let topE = CGPoint(x: sx + halfW, y: sy - cubeH)
        let topS = CGPoint(x: sx, y: sy + halfH - cubeH)
        let topW = CGPoint(x: sx - halfW, y: sy - cubeH)

        // Ground-level vertices
        let botS = CGPoint(x: sx, y: sy + halfH)
        let botE = CGPoint(x: sx + halfW, y: sy)
        let botW = CGPoint(x: sx - halfW, y: sy)

        // Left face (west side)
        ctx.setFillColor(red: faces.leftR, green: faces.leftG, blue: faces.leftB, alpha: 1)
        ctx.beginPath()
        ctx.move(to: topW)
        ctx.addLine(to: topS)
        ctx.addLine(to: botS)
        ctx.addLine(to: botW)
        ctx.closePath()
        ctx.fillPath()

        // Right face (east side)
        ctx.setFillColor(red: faces.rightR, green: faces.rightG, blue: faces.rightB, alpha: 1)
        ctx.beginPath()
        ctx.move(to: topS)
        ctx.addLine(to: topE)
        ctx.addLine(to: botE)
        ctx.addLine(to: botS)
        ctx.closePath()
        ctx.fillPath()

        // Top face
        ctx.setFillColor(red: faces.topR, green: faces.topG, blue: faces.topB, alpha: 1)
        ctx.beginPath()
        ctx.move(to: topN)
        ctx.addLine(to: topE)
        ctx.addLine(to: topS)
        ctx.addLine(to: topW)
        ctx.closePath()
        ctx.fillPath()

        // Subtle edge highlight on top face (thin bright line along top-left edges)
        ctx.setStrokeColor(red: min(faces.topR + 0.15, 1), green: min(faces.topG + 0.15, 1),
                           blue: min(faces.topB + 0.15, 1), alpha: 0.4)
        ctx.setLineWidth(0.5)
        ctx.beginPath()
        ctx.move(to: topW)
        ctx.addLine(to: topN)
        ctx.addLine(to: topE)
        ctx.strokePath()
    }

    // MARK: - Easing Functions

    private func easeOutBack(_ t: CGFloat) -> CGFloat {
        let c1: CGFloat = 1.70158
        let c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }

    private func easeInCubic(_ t: CGFloat) -> CGFloat {
        return t * t * t
    }

    // MARK: - Control

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
