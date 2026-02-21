import AppKit

class GameOfLifeView: NSView {
    let cellSize: CGFloat = 8
    var engine: GameEngine!
    var timer: Timer?
    let tickInterval: TimeInterval = 0.1

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
        layer?.backgroundColor = NSColor(hex: 0x121117).cgColor

        let cols = Int(bounds.width / cellSize)
        let rows = Int(bounds.height / cellSize)
        engine = GameEngine(width: max(cols, 10), height: max(rows, 10))

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

        // Charmtone caviar background
        ctx.setFillColor(NSColor(hex: 0x121117).cgColor)
        ctx.fill(bounds)

        let palette = GameEngine.palette

        for x in 0..<engine.width {
            for y in 0..<engine.height {
                let cell = engine.cells[x][y]

                if cell.alive {
                    let baseColor = palette[cell.colorIndex]
                    // Brighten slightly with age
                    let ageFactor = min(CGFloat(cell.age) / 30.0, 1.0)
                    let brightness = 0.7 + 0.3 * ageFactor
                    let color = baseColor.blended(with: .white, fraction: ageFactor * 0.2)
                        ?? baseColor

                    ctx.setFillColor(color.withAlphaComponent(brightness).cgColor)

                    let rect = CGRect(
                        x: CGFloat(x) * cellSize + 0.5,
                        y: CGFloat(y) * cellSize + 0.5,
                        width: cellSize - 1,
                        height: cellSize - 1
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

                    // Shift toward charmtone caviar as cell dies
                    let dyingColor = baseColor.blended(with: NSColor(hex: 0x121117), fraction: progress * 0.6)
                        ?? baseColor

                    ctx.setFillColor(dyingColor.withAlphaComponent(alpha).cgColor)

                    // Apply jitter
                    let rect = CGRect(
                        x: CGFloat(x) * cellSize + 0.5 + cell.jitterX,
                        y: CGFloat(y) * cellSize + 0.5 + cell.jitterY,
                        width: cellSize - 1,
                        height: cellSize - 1
                    )

                    // Shrink as it dies
                    let shrink = progress * 2.0
                    let shrunkRect = rect.insetBy(dx: shrink, dy: shrink)
                    if shrunkRect.width > 0 && shrunkRect.height > 0 {
                        ctx.fillEllipse(in: shrunkRect)
                    }
                }
            }
        }
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
