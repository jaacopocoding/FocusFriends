import AppKit

/// Finestra del fumetto: trasparente, non cattura i click.
final class BubbleWindow: NSWindow {
    let bubbleView = BubbleView(frame: .zero)

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = bubbleView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Disegna il fumetto (assets/bubble.png) scalato sul testo, con la frase centrata nell'ovale.
final class BubbleView: NSView {
    // Geometria dell'immagine, misurata da tools/cutout_bubble.py.
    private static let ellipseHeightFraction: CGFloat = 0.837   // l'ovale occupa il 83,7% dell'altezza, il resto è la codina
    private static let ellipseAspect: CGFloat = 1.63            // larghezza / altezza dell'ovale
    /// Posizione orizzontale della punta della codina, come frazione della larghezza.
    static let tailTipFraction: CGFloat = 0.825

    // Parte dell'ovale in cui il testo sta comodo.
    private static let textWidthFraction: CGFloat = 0.65
    private static let textHeightFraction: CGFloat = 0.55

    private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "bubble", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    private static let attributes: [NSAttributedString.Key: Any] = {
        let font = NSFont(name: "MarkerFelt-Wide", size: 14)
            ?? NSFont.systemFont(ofSize: 13, weight: .semibold)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        return [
            .font: font,
            .foregroundColor: NSColor(calibratedRed: 0.14, green: 0.09, blue: 0.05, alpha: 1),
            .paragraphStyle: style,
        ]
    }()

    var text = "" { didSet { needsDisplay = true } }

    private static func textSize(_ text: String, width: CGFloat) -> NSSize {
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        return NSSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    /// Dimensione del fumetto per questa frase: prova varie larghezze del testo e sceglie
    /// quella che dà un ovale con proporzioni più simili a quelle dell'immagine.
    static func size(for text: String) -> NSSize {
        var best: (ellipse: NSSize, score: CGFloat)?
        for wrap in stride(from: 110.0, through: 260.0, by: 10.0) {
            let t = textSize(text, width: wrap)
            let ew = max(t.width / textWidthFraction, 130)
            let eh = max(t.height / textHeightFraction, ew / ellipseAspect * 0.6)
            // Più l'ovale è vicino alle proporzioni dell'immagine, meno viene deformata.
            let score = abs(log((ew / eh) / ellipseAspect)) + (ew * eh) / 400_000
            if best == nil || score < best!.score {
                best = (NSSize(width: ew, height: eh), score)
            }
        }
        let ellipse = best?.ellipse ?? NSSize(width: 180, height: 110)
        return NSSize(width: ceil(ellipse.width), height: ceil(ellipse.height / ellipseHeightFraction))
    }

    override func draw(_ dirtyRect: NSRect) {
        if let image = Self.image {
            image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            NSColor(calibratedRed: 0.97, green: 0.92, blue: 0.80, alpha: 1).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16).fill()
        }

        // Ovale = parte alta della vista. Il testo sta centrato lì dentro.
        let ellipseHeight = bounds.height * Self.ellipseHeightFraction
        let box = NSRect(
            x: bounds.midX - bounds.width * Self.textWidthFraction / 2,
            y: bounds.height - ellipseHeight / 2 - ellipseHeight * Self.textHeightFraction / 2,
            width: bounds.width * Self.textWidthFraction,
            height: ellipseHeight * Self.textHeightFraction
        )
        let used = Self.textSize(text, width: box.width)
        let target = NSRect(x: box.minX, y: box.midY - used.height / 2, width: box.width, height: used.height)
        (text as NSString).draw(with: target, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: Self.attributes)
    }
}
