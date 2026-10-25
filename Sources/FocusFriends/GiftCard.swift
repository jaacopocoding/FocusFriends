import AppKit

/// La figurina trovata a fine focus: compare accanto al compagno, si gira e resta qualche secondo (con la luce che passa se è rara o
/// leggendaria). Non cattura i clic. Il fumetto della frase di fine focus non ci va sopra (vedi `Speaker.obstacles`).
final class GiftCard {
    static let size = NSSize(width: 112, height: 138)
    private static let duration: TimeInterval = 6.5

    private var window: OverlayWindow?
    private var view: GiftCardView?
    private var ticker: Timer?
    private var startedAt = Date()
    private weak var pet: PetWindow?

    /// Dove sta sullo schermo, se c'è.
    var frame: NSRect? { window?.frame }

    func show(drop: GardenDrop, near pet: PetWindow) {
        hide()
        guard let item = GardenCatalog.item(withID: drop.item) else { return }
        self.pet = pet
        startedAt = Date()
        let look = Sticker.Look(item: item, number: GardenCatalog.number(of: item.id) ?? 0, found: true, copies: drop.copies, isNew: drop.isNew)
        let view = GiftCardView(frame: NSRect(origin: .zero, size: Self.size), look: look)
        let panel = OverlayWindow(content: view)
        panel.setContentSize(Self.size)
        panel.setFrameOrigin(origin(for: pet))
        panel.alphaValue = 0
        pet.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        window = panel
        self.view = view
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        tick()
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
        guard let window, let view, let pet else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed >= Self.duration {
            hide()
            return
        }
        // Compare con una girata (0,45 s), resta, e sparisce nell'ultimo mezzo secondo.
        let appear = min(elapsed / 0.45, 1)
        view.turn = CGFloat(1 - pow(1 - appear, 3))
        view.shine = CGFloat(elapsed.truncatingRemainder(dividingBy: 1.8) / 1.8)
        let fade = min((Self.duration - elapsed) / 0.5, 1)
        window.alphaValue = CGFloat(min(appear * 2, 1) * max(fade, 0))
        view.needsDisplay = true
        let target = origin(for: pet)
        if abs(target.x - window.frame.minX) > 0.25 || abs(target.y - window.frame.minY) > 0.25 { window.setFrameOrigin(target) }
    }

    /// Di fianco al compagno, dal lato con più spazio, con il fondo all'altezza dei suoi piedi.
    private func origin(for pet: PetWindow) -> NSPoint {
        let size = Self.size
        let screen = (pet.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let onRight = pet.frame.midX < screen.midX
        var x = onRight ? pet.frame.maxX + 4 : pet.frame.minX - size.width - 4
        x = min(max(x, screen.minX + 6), screen.maxX - size.width - 6)
        var y = pet.feetY + 6
        y = min(max(y, screen.minY + 6), screen.maxY - size.height - 6)
        return NSPoint(x: x, y: y)
    }
}

/// La figurina, che si gira (`turn` da 0 a 1) con la luce che passa (`shine`).
private final class GiftCardView: NSView {
    override var isFlipped: Bool { true }
    var turn: CGFloat = 0
    var shine: CGFloat = 0
    private let look: Sticker.Look

    init(frame: NSRect, look: Sticker.Look) {
        self.look = look
        super.init(frame: frame)
        wantsLayer = false
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let rarity = look.item.rarity
        let card = bounds.insetBy(dx: 8, dy: 8)
        NSGraphicsContext.saveGraphicsState()
        // Una girata: la figurina si allarga dal centro (e un filo più in grande a metà, come un rimbalzo).
        let pop = 1 + 0.08 * sin(turn * .pi)
        let transform = NSAffineTransform()
        transform.translateX(by: bounds.midX, yBy: bounds.midY)
        transform.scaleX(by: max(turn, 0.02) * pop, yBy: pop)
        transform.translateX(by: -bounds.midX, yBy: -bounds.midY)
        transform.concat()
        // L'alone: oro per il leggendario, argento per il raro.
        if rarity >= .rare {
            let color = Sticker.color(for: rarity).withAlphaComponent(rarity == .legendary ? 0.34 : 0.22)
            color.setFill()
            NSBezierPath(roundedRect: card.insetBy(dx: -5, dy: -5), xRadius: 16, yRadius: 16).fill()
        }
        Sticker.draw(look, in: card, shine: rarity >= .rare ? shine : nil)
        NSGraphicsContext.restoreGraphicsState()
    }
}
