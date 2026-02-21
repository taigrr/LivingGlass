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
    // Isometric geometry — shallow angle (4:1 ratio), large tiles
    // Dynamic: computed from screen size in initGrid()
    var tileW: CGFloat = 72
    var tileH: CGFloat = 18
    var maxCubeH: CGFloat = 40

    // Grid & animation
    var engine: GameEngine!
    var anims: [[CellAnim]] = []

    // Render loop
    var displayTimer: Timer?
    var frameCount: Int = 0
    let gameTickEvery = 180         // game steps every 180 render frames (~1 per 3sec at 60fps)
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
        let screenW = bounds.width
        let screenH = bounds.height

        // Scale tile size relative to screen — target ~40 tiles across the screen width
        // This keeps density consistent across resolutions (1080p → 8K)
        let targetTilesAcross: CGFloat = 40
        tileW = max(floor(screenW / targetTilesAcross), 24)
        tileH = floor(tileW / 4)     // shallow isometric angle (4:1 ratio)
        maxCubeH = floor(tileW * 0.55)

        // The isometric diamond for an n×n grid has:
        //   width  = 2n * halfW
        //   height = 2n * halfH
        // To fully cover the screen (including corners), we need the diamond
        // to be larger than the screen diagonal in both iso dimensions.
        // Solve: 2n * halfW >= screenW AND 2n * halfH >= screenH
        // But the diamond is rotated 45°, so corners of the screen may poke out.
        // Over-provision by using the diagonal of the screen as the required coverage.
        let diagonal = sqrt(screenW * screenW + screenH * screenH)
        let nForWidth = Int(ceil(diagonal / tileW)) + 4
        let nForHeight = Int(ceil(diagonal / tileH)) + 4
        let gridSize = max(max(nForWidth, nForHeight), 20)

        engine = GameEngine(width: gridSize, height: gridSize)
        anims = Array(repeating: Array(repeating: CellAnim(), count: gridSize), count: gridSize)

        // Center the grid on screen
        originX = bounds.midX
        let visualHeight = CGFloat(gridSize * 2) * (tileH / 2) + maxCubeH
        originY = bounds.midY + visualHeight / 2

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
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.renderFrame()
        }
        // Add to .common modes so timer fires during menu tracking & modal loops
        RunLoop.current.add(timer, forMode: .common)
        displayTimer = timer
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
                    anims[x][y].progress += 0.0055
                    if anims[x][y].progress >= 1.0 {
                        anims[x][y].state = .alive
                        anims[x][y].progress = 0
                        anims[x][y].age = 0
                    }
                case .alive:
                    anims[x][y].age += 1
                case .dying:
                    anims[x][y].progress += 0.0022
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

        // Draw back-to-front: in macOS Y-up coords, back = higher Y, so draw decreasing (x+y)
        for y in stride(from: h - 1, through: 0, by: -1) {
            for x in stride(from: w - 1, through: 0, by: -1) {
                let anim = anims[x][y]
                if anim.state == .empty { continue }

                let sx = originX + CGFloat(x - y) * halfW
                let sy = originY - CGFloat(x + y) * halfH
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
        let riseOffset = (1.0 - t) * maxCubeH * 1.5  // starts below, rises to position
        let alpha = min(t * 2.5, 1.0)

        ctx.saveGState()
        ctx.setAlpha(alpha)
        drawCube(ctx: ctx, sx: sx, sy: sy - riseOffset, cubeH: cubeH, faces: faces)
        ctx.restoreGState()
    }

    private func drawAlive(ctx: CGContext, sx: CGFloat, sy: CGFloat, anim: CellAnim, faces: CubeFaces) {
        // Gentle idle bob (slowed 10x)
        let bob = sin(globalTime * 0.12 + anim.bobPhase) * 2.0
        // Subtle breathing (cube height oscillation, slowed 10x)
        let breathe = sin(globalTime * 0.08 + anim.bobPhase * 0.7) * 0.5
        drawCube(ctx: ctx, sx: sx, sy: sy + bob, cubeH: maxCubeH + breathe, faces: faces)
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
            let fallDist = eased * maxCubeH * 3.0
            let alpha = 1.0 - eased
            let shrink = 1.0 - eased * 0.4
            let cubeH = maxCubeH * shrink

            // Slight tumble wobble during fall (slowed)
            let tumbleX = sin(fallT * 0.8) * (1.0 - fallT) * 3.0

            ctx.saveGState()
            ctx.setAlpha(alpha)
            drawCube(ctx: ctx, sx: sx + tumbleX, sy: sy - fallDist, cubeH: cubeH, faces: faces)
            ctx.restoreGState()
        }
    }

    // MARK: - Cube Drawing

    private func drawCube(ctx: CGContext, sx: CGFloat, sy: CGFloat, cubeH: CGFloat, faces: CubeFaces) {
        let halfW = tileW / 2
        let halfH = tileH / 2

        guard cubeH > 0.5 else { return }

        // Top face (diamond) — cubeH extends upward (+Y in macOS coords)
        let topN = CGPoint(x: sx, y: sy + halfH + cubeH)
        let topE = CGPoint(x: sx + halfW, y: sy + cubeH)
        let topS = CGPoint(x: sx, y: sy - halfH + cubeH)
        let topW = CGPoint(x: sx - halfW, y: sy + cubeH)

        // Ground-level vertices
        let botS = CGPoint(x: sx, y: sy - halfH)
        let botE = CGPoint(x: sx + halfW, y: sy)
        let botW = CGPoint(x: sx - halfW, y: sy)

        // Left face (west side — visible below top, going down-left)
        ctx.setFillColor(red: faces.leftR, green: faces.leftG, blue: faces.leftB, alpha: 1)
        ctx.beginPath()
        ctx.move(to: topW)
        ctx.addLine(to: topS)
        ctx.addLine(to: botS)
        ctx.addLine(to: botW)
        ctx.closePath()
        ctx.fillPath()

        // Right face (east side — visible below top, going down-right)
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

        // Subtle edge highlight on top face
        ctx.setStrokeColor(red: min(faces.topR + 0.15, 1), green: min(faces.topG + 0.15, 1),
                           blue: min(faces.topB + 0.15, 1), alpha: 0.4)
        ctx.setLineWidth(max(tileW / 40.0, 0.5))
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

    func reset() {
        engine.randomize()
        // Re-sync animation state
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
        needsDisplay = true
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
