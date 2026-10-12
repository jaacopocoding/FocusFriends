import AppKit

/// Il pulsante «+5 minuti» che compare accanto al personaggio quando il focus è finito: se lo tocchi il focus
/// continua, altrimenti (dopo pochi secondi) parte la pausa. Una piccola carta con una barretta che si svuota.
final class ExtendPrompt {
    static let size = NSSize(width: 206, height: 60)

    private var window: NSPanel?
    private var view: ExtendPromptView?
    private var ticker: Timer?
    private weak var pet: PetWindow?
    private var startedAt = Date()
    private var duration: TimeInterval = 10

    var isShowing: Bool { window != nil }

    func show(near pet: PetWindow, seconds: TimeInterval, extraMinutes: Int, onExtend: @escaping () -> Void) {
        hide()
        self.pet = pet
        startedAt = Date()
        duration = seconds

        let view = ExtendPromptView(frame: NSRect(origin: .zero, size: Self.size), extraMinutes: extraMinutes)
        view.onClick = onExtend
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = view
        panel.setFrameOrigin(origin(for: pet))
        panel.alphaValue = 0
        pet.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
        window = panel
        self.view = view

        // Segue il personaggio (che si muove o cambia altezza) e fa scendere la barretta.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func hide() {
        ticker?.invalidate()
        ticker = nil
        guard let window else { return }
        self.window = nil
        view = nil
        pet?.removeChildWindow(window)
        window.orderOut(nil)
    }

    private func tick() {
        guard let window, let pet else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        view?.remaining = max(0, 1 - elapsed / duration)
        let target = origin(for: pet)
        if abs(target.x - window.frame.minX) > 0.25 || abs(target.y - window.frame.minY) > 0.25 {
            window.setFrameOrigin(target)
        }
    }

    /// Sopra la testa del personaggio (tutto ciò che si vede), o di fianco se sopra non c'è posto.
    private func origin(for pet: PetWindow) -> NSPoint {
        let size = Self.size
        let screen = (pet.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        var x = pet.frame.midX - size.width / 2
        x = min(max(x, screen.minX + 6), screen.maxX - size.width - 6)
        let y = pet.visibleTopY + 4
        if y + size.height <= screen.maxY - 4 { return NSPoint(x: x, y: y) }
        let onLeft = pet.frame.midX > screen.midX
        var sideX = onLeft ? pet.frame.minX - size.width - 2 : pet.frame.maxX + 2
        sideX = min(max(sideX, screen.minX + 6), screen.maxX - size.width - 6)
        return NSPoint(x: sideX, y: max(screen.maxY - size.height - 4, screen.minY))
    }

    /// La carta disegnata in un'immagine (per le anteprime).
    var contentView: NSView? { view }
}

private final class ExtendPromptView: NSView {
    var onClick: (() -> Void)?
    /// Quanto resta (1 = tutto, 0 = scaduto).
    var remaining: Double = 1 { didSet { needsDisplay = true } }
    private let extraMinutes: Int
    private var isHovered = false

    init(frame: NSRect, extraMinutes: Int) {
        self.extraMinutes = extraMinutes
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        setAccessibilityRole(.button)
        setAccessibilityLabel("Aggiungi \(extraMinutes) minuti al focus")
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func draw(_ dirtyRect: NSRect) {
        let card = bounds.insetBy(dx: 3, dy: 3)
        let shape = NSBezierPath(roundedRect: card, xRadius: 18, yRadius: 18)
        (isHovered ? NSColor(calibratedRed: 1.0, green: 0.93, blue: 0.80, alpha: 1) : Paper.paper).setFill()
        shape.fill()
        Paper.paperEdge.setStroke()
        shape.lineWidth = 1.5
        shape.stroke()

        // "+5" nel cerchio arancio
        let badge = NSRect(x: card.minX + 10, y: card.minY + 7, width: 36, height: 36)
        Paper.accent.setFill()
        NSBezierPath(ovalIn: badge).fill()
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        ("+\(extraMinutes)" as NSString).draw(in: NSRect(x: badge.minX, y: badge.midY - 12, width: badge.width, height: 24),
                                              withAttributes: [.font: Paper.markerFont(18), .foregroundColor: NSColor.white,
                                                               .paragraphStyle: para])

        let left = badge.maxX + 10
        ("Ancora \(extraMinutes) minuti?" as NSString).draw(
            at: NSPoint(x: left, y: card.minY + 8),
            withAttributes: [.font: NSFont.systemFont(ofSize: 13.5, weight: .semibold), .foregroundColor: Paper.ink])
        ("Tocca per continuare" as NSString).draw(
            at: NSPoint(x: left, y: card.minY + 26),
            withAttributes: [.font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: Paper.inkLight])

        // La barretta in fondo: si svuota in pochi secondi, poi parte la pausa.
        let track = NSRect(x: card.minX + 14, y: card.maxY - 7, width: card.width - 28, height: 3)
        Paper.track.setFill()
        NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
        Paper.accent.setFill()
        NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: track.width * CGFloat(remaining), height: track.height),
                     xRadius: 1.5, yRadius: 1.5).fill()
    }
}
