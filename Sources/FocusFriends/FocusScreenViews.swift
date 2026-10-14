import AppKit

/// I colori della schermata del focus (la carta, l'inchiostro e il pennarello sono quelli di `Paper`).
enum FocusPalette {
    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }
    static let dialFace = rgb(255, 253, 240)
    static let track = rgb(232, 216, 190)
    static let leaf = rgb(122, 154, 90)
    static let tomato = rgb(224, 116, 66)
    static let tomatoLight = rgb(236, 138, 86)
    static let rest = rgb(122, 154, 90)
    static let chipOn = rgb(246, 190, 120)
    static let postit = rgb(255, 240, 160)
    static let postitEdge = rgb(190, 170, 90)
    static let postitShadow = rgb(210, 190, 140)
    static let postitFold = rgb(232, 212, 120)
    static let postitHint = rgb(150, 130, 80)
    static let danger = rgb(176, 70, 52)
    static let dangerFill = rgb(255, 230, 222)
    static let dangerEdge = rgb(214, 150, 130)
    static let hole = rgb(150, 128, 100)
    static let holeInner = rgb(210, 190, 160)
}

/// Il pomodoro con il quadrante: l'arco dice quanta parte della fase è passata, al centro il tempo che manca.
final class FocusTomatoView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    static let size = NSSize(width: 300, height: 218)

    var progress: Double = 0 { didSet { needsDisplay = true } }
    var big = "" { didSet { needsDisplay = true } }
    var small = "" { didSet { needsDisplay = true } }
    var ring: NSColor = Paper.accent { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let ctx = NSGraphicsContext.current
        ctx?.saveGraphicsState()
        defer { ctx?.restoreGraphicsState() }
        let t = NSAffineTransform()
        t.translateX(by: bounds.midX, yBy: 116)
        t.scale(by: 0.935)
        t.concat()

        // Il corpo
        let body = NSBezierPath(ovalIn: NSRect(x: -120, y: -96, width: 240, height: 200))
        FocusPalette.tomato.setFill()
        body.fill()
        Paper.ink.setStroke()
        body.lineWidth = 2
        body.stroke()
        FocusPalette.tomatoLight.setFill()
        NSBezierPath(ovalIn: NSRect(x: -108, y: -84, width: 204, height: 144)).fill()

        // Le foglie
        let leaves: [[NSPoint]] = [
            [NSPoint(x: -44, y: -84), NSPoint(x: -16, y: -100), NSPoint(x: -2, y: -84)],
            [NSPoint(x: 44, y: -84), NSPoint(x: 16, y: -100), NSPoint(x: 2, y: -84)],
            [NSPoint(x: -10, y: -86), NSPoint(x: 0, y: -118), NSPoint(x: 10, y: -86)],
        ]
        for points in leaves {
            let path = NSBezierPath()
            path.move(to: points[0])
            path.line(to: points[1])
            path.line(to: points[2])
            path.close()
            FocusPalette.leaf.setFill()
            path.fill()
            Paper.ink.setStroke()
            path.lineWidth = 1.6
            path.lineJoinStyle = .round
            path.stroke()
        }

        // Il quadrante
        let r: CGFloat = 62
        let face = NSBezierPath(ovalIn: NSRect(x: -r - 12, y: -r - 6, width: 2 * r + 24, height: 2 * r + 24))
        FocusPalette.dialFace.setFill()
        face.fill()
        Paper.ink.setStroke()
        face.lineWidth = 2
        face.stroke()

        let centerY: CGFloat = 6
        let track = NSBezierPath(ovalIn: NSRect(x: -r, y: centerY - r, width: 2 * r, height: 2 * r))
        FocusPalette.track.setStroke()
        track.lineWidth = 9
        track.stroke()

        let fraction = CGFloat(min(max(progress, 0), 1))
        if fraction > 0.002 {
            let arc = NSBezierPath()
            let steps = max(Int(fraction * 120), 2)
            for i in 0...steps {
                let angle = -CGFloat.pi / 2 + fraction * 2 * .pi * CGFloat(i) / CGFloat(steps)
                let p = NSPoint(x: r * cos(angle), y: centerY + r * sin(angle))
                if i == 0 { arc.move(to: p) } else { arc.line(to: p) }
            }
            ring.setStroke()
            arc.lineWidth = 9
            arc.lineCapStyle = .round
            arc.stroke()
        }
        let end = -CGFloat.pi / 2 + fraction * 2 * .pi
        let knob = NSBezierPath(ovalIn: NSRect(x: r * cos(end) - 7, y: centerY + r * sin(end) - 7, width: 14, height: 14))
        FocusPalette.dialFace.setFill()
        knob.fill()
        ring.setStroke()
        knob.lineWidth = 3
        knob.stroke()

        // Il tempo
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        (big as NSString).draw(in: NSRect(x: -60, y: -30, width: 120, height: 48),
                               withAttributes: [.font: Paper.markerFont(40), .foregroundColor: Paper.ink, .paragraphStyle: para])
        (small as NSString).draw(in: NSRect(x: -60, y: 24, width: 120, height: 16),
                                 withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: Paper.inkLight,
                                                  .paragraphStyle: para])
    }
}

/// Il foglietto delle note: le note scritte finora e, in fondo, la riga per scriverne un'altra.
final class PostItView: NSView {
    override var isFlipped: Bool { true }

    static let visibleNotes = 4
    private static let rowHeight: CGFloat = 18
    private static let top: CGFloat = 38

    /// L'altezza del foglietto per questo numero di note.
    static func height(noteCount: Int) -> CGFloat {
        let shown = min(noteCount, visibleNotes)
        return top + CGFloat(shown) * rowHeight + 4 + 18 + 12
    }

    let field = NSTextField()
    var onSubmit: ((String) -> Void)?
    private var notes: [String] = []
    private var olderCount = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 11)
        field.textColor = Paper.ink
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.placeholderAttributedString = NSAttributedString(
            string: "scrivi una nota…",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: FocusPalette.postitHint])
        field.target = self
        field.action = #selector(submit)
        addSubview(field)
    }

    required init?(coder: NSCoder) { nil }

    func setNotes(_ all: [String]) {
        olderCount = max(all.count - Self.visibleNotes, 0)
        notes = Array(all.suffix(Self.visibleNotes))
        let inputY = Self.top + CGFloat(notes.count) * Self.rowHeight + 4
        field.frame = NSRect(x: 30, y: inputY - 9, width: bounds.width - 30 - 12, height: 18)
        needsDisplay = true
    }

    @objc private func submit() {
        let text = field.stringValue
        field.stringValue = ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSubmit?(text)
    }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width - 4, h = bounds.height - 5
        let sheet = NSRect(x: 0, y: 0, width: w, height: h)
        FocusPalette.postitShadow.setFill()
        NSBezierPath(roundedRect: sheet.offsetBy(dx: 3, dy: 4), xRadius: 6, yRadius: 6).fill()
        let shape = NSBezierPath(roundedRect: sheet.insetBy(dx: 0.6, dy: 0.6), xRadius: 6, yRadius: 6)
        FocusPalette.postit.setFill()
        shape.fill()
        FocusPalette.postitEdge.setStroke()
        shape.lineWidth = 1.2
        shape.stroke()
        // L'angolo piegato
        let fold = NSBezierPath()
        fold.move(to: NSPoint(x: w - 16, y: h))
        fold.line(to: NSPoint(x: w, y: h - 16))
        fold.line(to: NSPoint(x: w, y: h))
        fold.close()
        FocusPalette.postitFold.setFill()
        fold.fill()

        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        func text(_ s: String, x: CGFloat, centerY: CGFloat, font: NSFont, color: NSColor, width: CGFloat) {
            let size = (s as NSString).size(withAttributes: [.font: font])
            (s as NSString).draw(in: NSRect(x: x, y: centerY - size.height / 2, width: width, height: size.height),
                                 withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
        }
        text("Note", x: 12, centerY: 16, font: Paper.markerFont(17), color: Paper.ink, width: 100)
        if olderCount > 0 {
            let more = "+\(olderCount) sopra"
            let p = NSMutableParagraphStyle()
            p.alignment = .right
            (more as NSString).draw(in: NSRect(x: w - 100, y: 9, width: 88, height: 14),
                                    withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: FocusPalette.postitHint,
                                                     .paragraphStyle: p])
        }
        for (i, note) in notes.enumerated() {
            let y = Self.top + CGFloat(i) * Self.rowHeight
            text("•  \(note)", x: 12, centerY: y, font: NSFont.systemFont(ofSize: 11), color: Paper.ink, width: w - 24)
        }
        let inputY = Self.top + CGFloat(notes.count) * Self.rowHeight + 4
        text("+", x: 12, centerY: inputY, font: NSFont.systemFont(ofSize: 12, weight: .medium), color: FocusPalette.postitHint, width: 14)
    }
}

/// I disegni condivisi dalle schermate del focus e della pausa.
enum FocusDraw {
    enum Icon { case plus, stop, skip, play, none }

    /// Il pulsante "adesivo": contorno scuro, ombra dura in basso a destra, che si schiaccia quando lo premi.
    /// `rect` include i 4 punti dell'ombra a destra e in basso.
    static func sticker(in rect: NSRect, fill: NSColor, label: String, textColor: NSColor, icon: Icon,
                        pressed: Bool, hovered: Bool, font: NSFont = Paper.markerFont(18)) {
        let shadow: CGFloat = pressed ? 1.5 : 4
        let lift: CGFloat = pressed ? 2.5 : 0
        let body = NSRect(x: rect.minX + lift, y: rect.minY + lift, width: rect.width - 4, height: rect.height - 4)
        let radius = body.height / 2
        Paper.ink.setFill()
        NSBezierPath(roundedRect: body.offsetBy(dx: shadow, dy: shadow), xRadius: radius, yRadius: radius).fill()
        let shape = NSBezierPath(roundedRect: body.insetBy(dx: 1.3, dy: 1.3), xRadius: radius, yRadius: radius)
        let base = fill
        (hovered && !pressed ? base.blended(withFraction: 0.12, of: .white) ?? base : base).setFill()
        shape.fill()
        Paper.ink.setStroke()
        shape.lineWidth = 2.6
        shape.stroke()

        let cy = body.midY
        let iconX = body.minX + body.height * 0.5 + 4
        textColor.setStroke()
        textColor.setFill()
        switch icon {
        case .plus:
            let p = NSBezierPath()
            p.lineWidth = 3
            p.lineCapStyle = .round
            p.move(to: NSPoint(x: iconX - 6, y: cy)); p.line(to: NSPoint(x: iconX + 6, y: cy))
            p.move(to: NSPoint(x: iconX, y: cy - 6)); p.line(to: NSPoint(x: iconX, y: cy + 6))
            p.stroke()
        case .stop:
            NSBezierPath(roundedRect: NSRect(x: iconX - 5, y: cy - 5, width: 10, height: 10), xRadius: 1.5, yRadius: 1.5).fill()
        case .skip:
            let tri = NSBezierPath()
            tri.move(to: NSPoint(x: iconX - 5, y: cy - 6)); tri.line(to: NSPoint(x: iconX + 5, y: cy)); tri.line(to: NSPoint(x: iconX - 5, y: cy + 6))
            tri.close()
            tri.fill()
            let bar = NSBezierPath()
            bar.lineWidth = 2.4
            bar.lineCapStyle = .round
            bar.move(to: NSPoint(x: iconX + 7.5, y: cy - 6)); bar.line(to: NSPoint(x: iconX + 7.5, y: cy + 6))
            bar.stroke()
        case .play:
            let tri = NSBezierPath()
            tri.move(to: NSPoint(x: iconX - 5, y: cy - 7)); tri.line(to: NSPoint(x: iconX + 6, y: cy)); tri.line(to: NSPoint(x: iconX - 5, y: cy + 7))
            tri.close()
            tri.fill()
        case .none:
            break
        }
        let labelX = icon == .none ? body.minX : iconX + 12
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let size = (label as NSString).size(withAttributes: [.font: font])
        (label as NSString).draw(in: NSRect(x: labelX, y: cy - size.height / 2, width: body.maxX - labelX - 8, height: size.height),
                                 withAttributes: [.font: font, .foregroundColor: textColor, .paragraphStyle: para])
    }

    /// Il cestino a tratto.
    static func trash(centerX cx: CGFloat, centerY cy: CGFloat, color: NSColor) {
        color.setStroke()
        let can = NSBezierPath(roundedRect: NSRect(x: cx - 6, y: cy - 3, width: 12, height: 12), xRadius: 2, yRadius: 2)
        can.lineWidth = 1.6
        can.stroke()
        let lid = NSBezierPath()
        lid.lineWidth = 1.8
        lid.lineCapStyle = .round
        lid.move(to: NSPoint(x: cx - 8, y: cy - 3)); lid.line(to: NSPoint(x: cx + 8, y: cy - 3))
        lid.move(to: NSPoint(x: cx - 3, y: cy - 6)); lid.line(to: NSPoint(x: cx + 3, y: cy - 6))
        lid.stroke()
        let ribs = NSBezierPath()
        ribs.lineWidth = 1.2
        ribs.lineCapStyle = .round
        ribs.move(to: NSPoint(x: cx - 2, y: cy + 1)); ribs.line(to: NSPoint(x: cx - 2, y: cy + 6))
        ribs.move(to: NSPoint(x: cx + 2, y: cy + 1)); ribs.line(to: NSPoint(x: cx + 2, y: cy + 6))
        ribs.stroke()
    }

    /// I fori della spirale in cima al quaderno.
    static func spiralHoles(in width: CGFloat, top: CGFloat) {
        let count = 9
        let spacing = (width - 56) / CGFloat(count - 1)
        for i in 0..<count {
            let cx = 28 + CGFloat(i) * spacing
            let hole = NSBezierPath(ovalIn: NSRect(x: cx - 7, y: top + 8, width: 14, height: 14))
            FocusPalette.hole.setFill()
            hole.fill()
            Paper.ink.setStroke()
            hole.lineWidth = 1
            hole.stroke()
            FocusPalette.holeInner.setFill()
            NSBezierPath(ovalIn: NSRect(x: cx - 3, y: top + 11, width: 4, height: 4)).fill()
        }
    }
}

/// I quattro puntini del ciclo dei focus, con la scritta accanto («Focus 2 di 4»).
final class CycleDotsView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var done = 0
    /// Il puntino dopo gli ultimi fatti ha il contorno: è quello che si sta facendo.
    var highlightsNext = false
    var text = ""

    override func draw(_ dirtyRect: NSRect) {
        let size: CGFloat = 10, gap: CGFloat = 6
        let total = BreakCycle.focusesPerCycle
        for i in 0..<total {
            let rect = NSRect(x: CGFloat(i) * (size + gap) + 1, y: bounds.midY - size / 2, width: size, height: size)
            let dot = NSBezierPath(ovalIn: rect)
            if i < done {
                Paper.accent.setFill()
                dot.fill()
            } else if highlightsNext && i == done {
                FocusPalette.dialFace.setFill()
                dot.fill()
                Paper.accent.setStroke()
                dot.lineWidth = 2
                dot.stroke()
            } else {
                FocusPalette.track.setFill()
                dot.fill()
            }
        }
        let x = CGFloat(total) * (size + gap) + 4
        (text as NSString).draw(in: NSRect(x: x, y: bounds.midY - 8, width: bounds.width - x, height: 16),
                                withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: Paper.inkLight])
    }
}
