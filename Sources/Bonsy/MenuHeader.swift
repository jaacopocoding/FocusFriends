import AppKit

/// L'intestazione del menu: una piccola scheda color carta (come il fumetto) con la testa del personaggio,
/// il suo nome e cosa sta facendo ("Qui con te", "Focus · 24:10"...).
final class MenuHeaderView: NSView {
    static let size = NSSize(width: 264, height: 62)

    var title = "" { didSet { needsDisplay = true } }
    var status = "" { didSet { needsDisplay = true } }
    var icon: NSImage? { didSet { needsDisplay = true } }
    /// A che punto della larghezza dell'immagine sta il "volto" (0...1): l'avatar si centra lì.
    var iconFocus: CGFloat = 0.5 { didSet { needsDisplay = true } }

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
    }

    required init?(coder: NSCoder) { nil }

    // Colori fissi (carta e inchiostro): la scheda ha lo stesso aspetto in modalità chiara e scura.
    private static let paper = NSColor(calibratedRed: 1.0, green: 0.965, blue: 0.87, alpha: 1)
    private static let paperEdge = NSColor(calibratedRed: 0.55, green: 0.40, blue: 0.25, alpha: 0.40)
    private static let ink = NSColor(calibratedRed: 0.16, green: 0.10, blue: 0.06, alpha: 1)
    private static let inkLight = NSColor(calibratedRed: 0.40, green: 0.30, blue: 0.20, alpha: 1)

    override func draw(_ dirtyRect: NSRect) {
        let card = bounds.insetBy(dx: 8, dy: 5)
        let shape = NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12)
        Self.paper.setFill()
        shape.fill()
        Self.paperEdge.setStroke()
        shape.lineWidth = 1.2
        shape.stroke()

        // La testa del porcellino, a sinistra, dentro un cerchio con bordo (come l'avatar di un contatto).
        let iconBox = NSRect(x: card.minX + 9, y: card.midY - 22, width: 44, height: 44)
        let circle = NSBezierPath(ovalIn: iconBox)
        NSColor(calibratedRed: 1.0, green: 0.99, blue: 0.94, alpha: 1).setFill()
        circle.fill()
        if let icon {
            NSGraphicsContext.saveGraphicsState()
            circle.addClip()
            // L'immagine riempie il cerchio in altezza e viene centrata sul muso (vedi iconFocus).
            let scale = iconBox.height / icon.size.height * 1.12
            let size = NSSize(width: icon.size.width * scale, height: icon.size.height * scale)
            let origin = NSPoint(x: iconBox.midX - size.width * iconFocus, y: iconBox.midY - size.height * 0.52)
            icon.draw(in: NSRect(origin: origin, size: size), from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
        Self.paperEdge.setStroke()
        circle.lineWidth = 1.2
        circle.stroke()

        // Nome (stesso carattere "pennarello" del fumetto) e stato.
        let textX = iconBox.maxX + 11
        let textWidth = card.maxX - textX - 8
        let titleFont = NSFont(name: "MarkerFelt-Wide", size: 15) ?? NSFont.systemFont(ofSize: 14, weight: .semibold)
        (title as NSString).draw(
            in: NSRect(x: textX, y: card.midY + 1, width: textWidth, height: 20),
            withAttributes: [.font: titleFont, .foregroundColor: Self.ink]
        )
        (status as NSString).draw(
            in: NSRect(x: textX, y: card.midY - 19, width: textWidth, height: 16),
            withAttributes: [.font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: Self.inkLight]
        )
    }
}
