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
        NSColor(calibratedRed: 0.55, green: 0.45, blue: 0.33, alpha: 1),   // nocciola
    ]

    static func color(forSubject subject: String) -> NSColor {
        // Una somma semplice e stabile: Swift cambia l'hash delle stringhe a ogni avvio.
        let sum = subject.lowercased().unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return subjectColors[abs(sum) % subjectColors.count]
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
