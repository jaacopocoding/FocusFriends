import AppKit

/// Finestra trasparente, senza bordi, sempre sopra le altre, visibile su tutti gli Spaces.
final class SpidyWindow: NSWindow {
    static let size = NSSize(width: 96, height: 96)

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = SpidyView(frame: NSRect(origin: .zero, size: Self.size))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Appoggia la finestra sul bordo inferiore dello schermo, sopra il Dock.
    func placeOnGround() {
        guard let screen = NSScreen.main else { return }
        let ground = screen.visibleFrame
        setFrameOrigin(NSPoint(x: ground.midX - Self.size.width / 2, y: ground.minY))
    }
}

/// Mostra Spidy nella finestra. L'animazione della camminata arriva allo Step 3.
final class SpidyView: NSView {
    var pose: SpidyPose = .idle {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        SpidyArt.draw(pose, in: bounds)
    }
}
