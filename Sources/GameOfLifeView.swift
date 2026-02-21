import AppKit

class GameOfLifeView: NSView {
    let cellSize: CGFloat = 8
    var engine: GameEngine!
    var timer: Timer?
    let tickInterval: TimeInterval = 0.1

    // Cache colors to avoid repeated allocation
    private static let bgColor = NSColor(hex: 0x121117).cgColor
    private static let caviarColor = NSColor(hex: 0x121117)

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // Retina support
    override var isOpaque: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let scale = window?.backingScaleFactor {
            let logicalWidth = bounds.width
            let logicalHeight = bounds.height
            let cols = Int(logicalWidth / cellSize)
            let rows = Int(logicalHeight / cellSize)
            if engine == nil || cols != engine.width || rows != engine.height {
                engine = GameEngine(width: max(cols, 10), height: max(rows, 10))
            }
            layer?.contentsScale = scale
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = Self.bgColor
        layer?.drawsAsynchronously = true

        let cols = Int(bounds.width / cellSize)
        let rows = Int(bounds.height / cellSize)
        engine = GameEngine(width: max(cols, 10), height: max(rows, 10))

        startTimer()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        engine.step()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(Self.bgColor)
        ctx.fill(bounds)

        let palette = GameEngine.palette
        let cs = cellSize

        for x in 0..<engine.width {
            for y in 0..<engine.height {
                let cell = engine.cells[x][y]

                if cell.alive {
                    let baseColor = palette[cell.colorIndex]
                    let ageFactor = min(CGFloat(cell.age) / 30.0, 1.0)
                    let brightness = 0.7 + 0.3 * ageFactor
                    let color = baseColor.blended(with: .white, fraction: ageFactor * 0.2)
                        ?? baseColor

                    ctx.setFillColor(color.withAlphaComponent(brightness).cgColor)

                    let rect = CGRect(
                        x: CGFloat(x) * cs + 0.5,
                        y: CGFloat(y) * cs + 0.5,
                        width: cs - 1,
                        height: cs - 1
                    )
                    ctx.fillEllipse(in: rect)

                    // Subtle glow for older cells
                    if cell.age > 8 {
                        let glowAlpha = min(CGFloat(cell.age - 8) / 40.0, 0.25)
                        ctx.setFillColor(color.withAlphaComponent(glowAlpha).cgColor)
                        let glowRect = rect.insetBy(dx: -1.5, dy: -1.5)
                        ctx.fillEllipse(in: glowRect)
                    }

                } else if cell.deathFrame > 0 {
                    let progress = CGFloat(cell.deathFrame) / CGFloat(engine.maxDeathFrames)
                    let alpha = (1.0 - progress) * 0.85
                    let baseColor = palette[cell.colorIndex]

                    let dyingColor = baseColor.blended(with: Self.caviarColor, fraction: progress * 0.6)
                        ?? baseColor

                    ctx.setFillColor(dyingColor.withAlphaComponent(alpha).cgColor)

                    let rect = CGRect(
                        x: CGFloat(x) * cs + 0.5 + cell.jitterX,
                        y: CGFloat(y) * cs + 0.5 + cell.jitterY,
                        width: cs - 1,
                        height: cs - 1
                    )

                    let shrink = progress * 2.0
                    let shrunkRect = rect.insetBy(dx: shrink, dy: shrink)
                    if shrunkRect.width > 0 && shrunkRect.height > 0 {
                        ctx.fillEllipse(in: shrunkRect)
                    }
                }
            }
        }
    }

    func pause() {
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        guard timer == nil else { return }
        startTimer()
    }

    func resize(to size: NSSize) {
        let cols = Int(size.width / cellSize)
        let rows = Int(size.height / cellSize)
        if cols != engine.width || rows != engine.height {
            engine = GameEngine(width: max(cols, 10), height: max(rows, 10))
        }
    }

    deinit {
        timer?.invalidate()
    }
}
