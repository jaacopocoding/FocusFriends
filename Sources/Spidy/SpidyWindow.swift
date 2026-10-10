import AppKit

/// Finestra trasparente, senza bordi, sempre sopra le altre, visibile su tutti gli Spaces.
final class SpidyWindow: NSWindow {
    static let size = NSSize(width: 124, height: 154)
    private static let margin: CGFloat = 32

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
        isMovableByWindowBackground = true   // si può trascinare dove si vuole
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = SpidyView(frame: NSRect(origin: .zero, size: Self.size))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Appoggia la finestra nell'angolo in basso a destra, sopra il Dock.
    func placeOnGround() {
        guard let screen = NSScreen.main else { return }
        let ground = screen.visibleFrame
        setFrameOrigin(NSPoint(x: ground.maxX - Self.size.width - Self.margin, y: ground.minY))
    }
}

/// Mostra l'immagine di Spidy appoggiata sul fondo della finestra, con una piccola ombra a terra.
final class SpidyView: NSView {
    private let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "spidy", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    override var mouseDownCanMoveWindow: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }

        NSColor.black.withAlphaComponent(0.16).setFill()
        NSBezierPath(ovalIn: NSRect(x: bounds.midX - 40, y: 1, width: 80, height: 9)).fill()

        // Adatta l'immagine allo spazio disponibile mantenendo le proporzioni, appoggiata in basso.
        let available = NSRect(x: 0, y: 5, width: bounds.width, height: bounds.height - 5)
        let scale = min(available.width / image.size.width, available.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let target = NSRect(x: available.midX - size.width / 2, y: available.minY, width: size.width, height: size.height)
        image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
    }
}
