import AppKit

/// Gli elementi grafici in comune delle schede (scheda della materia, statistiche): carta color crema,
/// inchiostro scuro e il carattere "pennarello" del fumetto.
enum Paper {
    static let paper = NSColor(calibratedRed: 1.0, green: 0.965, blue: 0.87, alpha: 1)
    static let paperEdge = NSColor(calibratedRed: 0.55, green: 0.40, blue: 0.25, alpha: 0.45)
    static let ink = NSColor(calibratedRed: 0.16, green: 0.10, blue: 0.06, alpha: 1)
    static let inkLight = NSColor(calibratedRed: 0.40, green: 0.30, blue: 0.20, alpha: 1)
    static let accent = NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.22, alpha: 1)
    static let accentPressed = NSColor(calibratedRed: 0.72, green: 0.38, blue: 0.16, alpha: 1)
    static let track = NSColor(calibratedRed: 0.55, green: 0.40, blue: 0.25, alpha: 0.13)

    /// I colori delle materie: uno per ognuna, sempre lo stesso per lo stesso nome.
    static let subjectColors: [NSColor] = [
        NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.22, alpha: 1),   // terracotta
        NSColor(calibratedRed: 0.44, green: 0.62, blue: 0.40, alpha: 1),   // salvia
        NSColor(calibratedRed: 0.86, green: 0.67, blue: 0.22, alpha: 1),   // senape
        NSColor(calibratedRed: 0.28, green: 0.55, blue: 0.58, alpha: 1),   // verde acqua
        NSColor(calibratedRed: 0.62, green: 0.38, blue: 0.55, alpha: 1),   // prugna
        NSColor(calibratedRed: 0.80, green: 0.45, blue: 0.50, alpha: 1),   // rosa antico
        NSColor(calibratedRed: 0.36, green: 0.47, blue: 0.70, alpha: 1),   // azzurro polvere
        NSColor(calibratedRed: 0.55, green: 0.50, blue: 0.78, alpha: 1),   // lavanda
    ]

    static func color(forSubject subject: String) -> NSColor {
        // Una somma semplice e stabile: Swift cambia l'hash delle stringhe a ogni avvio.
        let sum = subject.lowercased().unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return subjectColors[abs(sum) % subjectColors.count]
    }

    /// Un'icona di sistema (SF Symbols) con il colore dato, per i disegni a mano.
    static func symbolImage(_ name: String, size: CGFloat, color: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    static func markerFont(_ size: CGFloat) -> NSFont {
        NSFont(name: "MarkerFelt-Wide", size: size) ?? NSFont.systemFont(ofSize: size - 2, weight: .bold)
    }
}

/// Il pulsante principale: una pillola color terracotta con la scritta bianca.
final class PillButton: NSButton {
    init(title: String, width: CGFloat = 150, height: CGFloat = 38) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        self.title = title
        isBordered = false
        setButtonType(.momentaryPushIn)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: height).isActive = true
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        (isHighlighted ? Paper.accentPressed : Paper.accent).setFill()
        shape.fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: Paper.markerFont(17), .foregroundColor: NSColor.white]
        let text = title as NSString
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
    }
}

/// Un pulsante secondario: solo testo, sottolineato quando ci si passa sopra.
final class TextButton: NSButton {
    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        setButtonType(.momentaryPushIn)
        translatesAutoresizingMaskIntoConstraints = false
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: Paper.inkLight,
        ])
    }

    required init?(coder: NSCoder) { nil }
}

/// Una "etichetta" cliccabile (le materie recenti).
final class ChipButton: NSButton {
    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        setButtonType(.momentaryPushIn)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 26).isActive = true
        let width = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width + 24
        widthAnchor.constraint(equalToConstant: min(max(width, 44), 200)).isActive = true
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        (isHighlighted ? Paper.accent.withAlphaComponent(0.35) : Paper.color(forSubject: title).withAlphaComponent(0.18)).setFill()
        shape.fill()
        Paper.color(forSubject: title).withAlphaComponent(0.7).setStroke()
        shape.lineWidth = 1
        shape.stroke()
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byTruncatingTail
        (title as NSString).draw(
            in: NSRect(x: 8, y: bounds.midY - 8, width: bounds.width - 16, height: 17),
            withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: Paper.ink, .paragraphStyle: para]
        )
    }
}

/// La scheda color carta, con bordo e angoli arrotondati.
final class PaperCardView: NSView {
    var cornerRadius: CGFloat = 20

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: cornerRadius, yRadius: cornerRadius)
        Paper.paper.setFill()
        shape.fill()
        Paper.paperEdge.setStroke()
        shape.lineWidth = 1.5
        shape.stroke()
    }
}

/// Un pannello senza bordi che può ricevere la tastiera (serve per scrivere la materia).
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    /// Chiamata quando si preme Esc.
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

// MARK: - "Com'è andata?"

extension FocusRating {
    /// Il colore della faccia: salvia, senape, rosa antico (gli stessi toni delle materie).
    var color: NSColor {
        switch self {
        case .good: return NSColor(calibratedRed: 0.52, green: 0.70, blue: 0.45, alpha: 1)
        case .soso: return NSColor(calibratedRed: 0.90, green: 0.73, blue: 0.30, alpha: 1)
        case .poor: return NSColor(calibratedRed: 0.84, green: 0.52, blue: 0.54, alpha: 1)
        }
    }
}

/// Le tre facce disegnate a mano nello stile dell'app: un sorriso, una linea, una smorfia con gli occhi chiusi.
enum FaceIcon {
    /// `flipped`: la vista in cui si disegna ha l'origine in alto (le statistiche) o in basso (i pulsanti).
    static func draw(_ rating: FocusRating, in rect: NSRect, flipped: Bool, emphasized: Bool = false) {
        let r = min(rect.width, rect.height) / 2
        let c = NSPoint(x: rect.midX, y: rect.midY)
        let up: CGFloat = flipped ? -1 : 1        // "in alto" sullo schermo
        let line = max(1.2, r * 0.11)

        let face = NSBezierPath(ovalIn: NSRect(x: c.x - r + line / 2, y: c.y - r + line / 2, width: 2 * r - line, height: 2 * r - line))
        rating.color.setFill()
        face.fill()
        Paper.ink.withAlphaComponent(emphasized ? 1 : 0.8).setStroke()
        face.lineWidth = line
        face.stroke()

        Paper.ink.setStroke()
        Paper.ink.setFill()
        let eyeY = c.y + up * r * 0.22
        let eyeDX = r * 0.36
        switch rating {
        case .good, .soso:
            for dx in [-eyeDX, eyeDX] {
                let d = r * 0.17
                NSBezierPath(ovalIn: NSRect(x: c.x + dx - d / 2, y: eyeY - d / 2, width: d, height: d)).fill()
            }
        case .poor:
            // occhi chiusi, stanchi
            for dx in [-eyeDX, eyeDX] {
                let eye = NSBezierPath()
                eye.move(to: NSPoint(x: c.x + dx - r * 0.15, y: eyeY))
                eye.line(to: NSPoint(x: c.x + dx + r * 0.15, y: eyeY))
                eye.lineWidth = line
                eye.lineCapStyle = .round
                eye.stroke()
            }
        }
        let mouth = NSBezierPath()
        mouth.lineWidth = line
        mouth.lineCapStyle = .round
        switch rating {
        case .good:
            mouth.move(to: NSPoint(x: c.x - r * 0.42, y: c.y - up * r * 0.22))
            mouth.curve(to: NSPoint(x: c.x + r * 0.42, y: c.y - up * r * 0.22),
                        controlPoint1: NSPoint(x: c.x - r * 0.25, y: c.y - up * r * 0.62),
                        controlPoint2: NSPoint(x: c.x + r * 0.25, y: c.y - up * r * 0.62))
        case .soso:
            mouth.move(to: NSPoint(x: c.x - r * 0.34, y: c.y - up * r * 0.38))
            mouth.line(to: NSPoint(x: c.x + r * 0.34, y: c.y - up * r * 0.38))
        case .poor:
            mouth.move(to: NSPoint(x: c.x - r * 0.34, y: c.y - up * r * 0.5))
            mouth.curve(to: NSPoint(x: c.x + r * 0.34, y: c.y - up * r * 0.5),
                        controlPoint1: NSPoint(x: c.x - r * 0.18, y: c.y - up * r * 0.28),
                        controlPoint2: NSPoint(x: c.x + r * 0.18, y: c.y - up * r * 0.28))
        }
        mouth.stroke()
    }
}

/// Il pulsante di una faccia, con il nome sotto. Si ingrandisce un poco passandoci sopra.
final class RatingButton: NSButton {
    let rating: FocusRating
    private var isHovered = false

    init(rating: FocusRating) {
        self.rating = rating
        super.init(frame: NSRect(x: 0, y: 0, width: 96, height: 84))
        isBordered = false
        setButtonType(.momentaryPushIn)
        title = rating.title
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 96).isActive = true
        heightAnchor.constraint(equalToConstant: 84).isActive = true
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { false }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let size: CGFloat = isHighlighted ? 46 : (isHovered ? 54 : 50)
        let box = NSRect(x: bounds.midX - size / 2, y: bounds.maxY - 6 - 54 + (54 - size) / 2, width: size, height: size)
        FaceIcon.draw(rating, in: box, flipped: false, emphasized: isHovered)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        (title as NSString).draw(
            in: NSRect(x: 0, y: 4, width: bounds.width, height: 18),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: isHovered ? .semibold : .regular),
                .foregroundColor: isHovered ? Paper.ink : Paper.inkLight,
                .paragraphStyle: para,
            ]
        )
    }
}

// MARK: - Torna al menu

/// "‹ Menu" nella barra del titolo di una finestra: chiude la finestra e riapre la scheda del menu.
final class BackToMenuAccessory: NSTitlebarAccessoryViewController {
    private let onBack: () -> Void

    init(onBack: @escaping () -> Void) {
        self.onBack = onBack
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .left
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let button = NSButton(title: " Menu", target: self, action: #selector(pressed))
        button.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        button.contentTintColor = Paper.inkLight
        button.toolTip = "Torna al menu"
        button.setAccessibilityLabel("Torna al menu")
        button.frame = NSRect(x: 6, y: 0, width: 78, height: 26)
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 90, height: 26))
        box.addSubview(button)
        view = box
    }

    @objc private func pressed() { onBack() }
}
