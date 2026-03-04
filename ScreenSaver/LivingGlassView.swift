import ScreenSaver
import AppKit
import MetalKit

class LivingGlassView: ScreenSaverView {
    private var gameView: GameOfLifeView?
    private var didSetup = false

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 60.0
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        animationTimeInterval = 1.0 / 60.0
    }

    private func setupIfNeeded() {
        guard !didSetup, bounds.width > 0, bounds.height > 0 else { return }
        didSetup = true

        wantsLayer = true
        layer?.backgroundColor = LivingGlassConstants.backgroundNSColor.cgColor

        let saverBundle = Bundle(for: LivingGlassView.self)
        let gv = GameOfLifeView(frame: bounds, bundle: saverBundle)
        gv.autoresizingMask = [.width, .height]
        addSubview(gv)
        gameView = gv
    }

    override func startAnimation() {
        super.startAnimation()
        setupIfNeeded()
        gameView?.resume()
    }

    override func stopAnimation() {
        super.stopAnimation()
        gameView?.pause()
    }

    override func animateOneFrame() {
        setupIfNeeded()
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        gameView?.frame = bounds
        if bounds.width > 0 && bounds.height > 0 {
            gameView?.resize(to: bounds.size)
        }
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }

    override func draw(_ rect: NSRect) {
        LivingGlassConstants.backgroundNSColor.setFill()
        rect.fill()
    }
}
