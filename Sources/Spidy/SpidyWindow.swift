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
        contentView = PlaceholderView(frame: NSRect(origin: .zero, size: Self.size))
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

/// Segnaposto dello Step 1: un quadrato rosso arrotondato. Verrà sostituito dal vero Spidy.
final class PlaceholderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.86, green: 0.1, blue: 0.12, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 8), xRadius: 16, yRadius: 16).fill()
    }
}
