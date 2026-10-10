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

final class BubbleView: NSView {
    private static let maxTextWidth: CGFloat = 180
    private static let padding: CGFloat = 12
    private static let tailHeight: CGFloat = 10
    private static let tailHalfWidth: CGFloat = 8
    static let minTailInset: CGFloat = 18

    private static let attributes: [NSAttributedString.Key: Any] = {
        var font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        if let rounded = font.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: rounded, size: 13) {
            font = f
        }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        return [.font: font, .foregroundColor: NSColor(calibratedWhite: 0.1, alpha: 1), .paragraphStyle: style]
    }()

    var text = "" { didSet { needsDisplay = true } }
    /// Ascissa (nella vista) della punta della codina.
    var tailX: CGFloat = 40 { didSet { needsDisplay = true } }

    private static func textSize(for text: String) -> NSSize {
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        return NSSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    static func size(for text: String) -> NSSize {
        let t = textSize(for: text)
        return NSSize(width: max(t.width, 60) + padding * 2, height: t.height + padding * 2 + tailHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let tail = Self.tailHeight
        let body = NSRect(x: 1, y: tail, width: bounds.width - 2, height: bounds.height - tail - 1)
        let outline = NSColor(calibratedWhite: 0.1, alpha: 1)
        let fill = NSColor(calibratedWhite: 0.99, alpha: 1)

        let bubble = NSBezierPath(roundedRect: body, xRadius: 14, yRadius: 14)
        fill.setFill()
        bubble.fill()
        outline.setStroke()
        bubble.lineWidth = 1.5
        bubble.stroke()

        // Codina: copre il tratto del contorno sotto di sé, poi disegna solo i due lati inclinati.
        let hw = Self.tailHalfWidth
        let left = NSPoint(x: tailX - hw, y: tail + 0.8)
        let tip = NSPoint(x: tailX, y: 1)
        let right = NSPoint(x: tailX + hw, y: tail + 0.8)

        let tailFill = NSBezierPath()
        tailFill.move(to: left)
        tailFill.line(to: tip)
        tailFill.line(to: right)
        tailFill.close()
        fill.setFill()
        tailFill.fill()

        let tailEdge = NSBezierPath()
        tailEdge.move(to: left)
        tailEdge.line(to: tip)
        tailEdge.line(to: right)
        tailEdge.lineWidth = 1.5
        tailEdge.lineJoinStyle = .round
        tailEdge.lineCapStyle = .round
        outline.setStroke()
        tailEdge.stroke()

        let textRect = NSRect(
            x: Self.padding,
            y: tail + Self.padding,
            width: bounds.width - Self.padding * 2,
            height: bounds.height - tail - Self.padding * 2
        )
        (text as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: Self.attributes)
    }
}
