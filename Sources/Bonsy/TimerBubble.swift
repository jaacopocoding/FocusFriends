import AppKit

/// Finestra del timer, sotto il personaggio.
final class TimerWindow: OverlayWindow {
    static let size = NSSize(width: 132, height: 76)

    let timerView: TimerView

    init() {
        let view = TimerView(frame: NSRect(origin: .zero, size: Self.size))
        timerView = view
        super.init(content: view)
        setContentSize(Self.size)
    }
}

/// Mini orologio digitale: cassa nera, cifre a sette segmenti inclinate e schermo di carta color crema,
/// la stessa del fumetto.
final class TimerView: NSView {
    private static let digitColor = NSColor(calibratedRed: 0.13, green: 0.12, blue: 0.10, alpha: 1)
    private static let shadowColor = NSColor(calibratedRed: 0.35, green: 0.28, blue: 0.15, alpha: 0.28)

    // Segmenti accesi per ogni cifra: a=alto, b=alto dx, c=basso dx, d=basso, e=basso sx, f=alto sx, g=centro.
    private static let segments: [Character: String] = [
        "0": "abcdef", "1": "bc", "2": "abdeg", "3": "abcdg", "4": "bcfg",
        "5": "acdfg", "6": "acdefg", "7": "abc", "8": "abcdefg", "9": "abcdfg",
    ]

    var label = "FOCUS" { didSet { needsDisplay = true } }
    var time = "00:00" { didSet { if time != oldValue { needsDisplay = true } } }

    /// Il disegno completo, a grandezza piena, indipendentemente dall'altezza attuale della finestra.
    private var full: NSRect { NSRect(origin: .zero, size: TimerWindow.size) }

    override func draw(_ dirtyRect: NSRect) {
        // Ancoro il disegno in alto: quando la finestra è più bassa se ne vede solo la parte alta,
        // e crescendo si "srotola" verso il basso come una tendina.
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let anchor = NSAffineTransform()
        anchor.translateX(by: 0, yBy: bounds.height - full.height)
        anchor.concat()

        drawCase()
        let screen = screenRect
        drawScreen(screen)
        drawLabel(in: screen)
        drawTime(in: screen)
    }

    // MARK: - Cassa e schermo

    private var screenRect: NSRect {
        NSRect(x: 11, y: 10, width: full.width - 22, height: full.height - 25)
    }

    private func drawCase() {
        let body = NSBezierPath(roundedRect: full.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        NSGradient(colors: [NSColor(calibratedWhite: 0.30, alpha: 1), NSColor(calibratedWhite: 0.07, alpha: 1)])!
            .draw(in: body, angle: -90)

        // Piastra superiore, un po' più chiara, come il coperchio dell'orologio.
        let lip = NSBezierPath(
            roundedRect: NSRect(x: 5, y: full.height - 13, width: full.width - 10, height: 9),
            xRadius: 4, yRadius: 4
        )
        NSColor(calibratedWhite: 0.20, alpha: 1).setFill()
        lip.fill()
        NSColor(calibratedWhite: 0.42, alpha: 0.6).setStroke()
        lip.lineWidth = 0.8
        lip.stroke()

        NSColor(calibratedWhite: 0.0, alpha: 0.8).setStroke()
        body.lineWidth = 1.2
        body.stroke()
    }

    private func drawScreen(_ rect: NSRect) {
        let shape = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)

        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        if let image = BubbleView.image {
            // Un pezzo pulito della carta del fumetto (nell'immagine l'origine è in basso a sinistra).
            let source = NSRect(x: 230, y: image.size.height - 300, width: 250, height: 100)
            image.draw(in: rect, from: source, operation: .sourceOver, fraction: 1)
        } else {
            NSColor(calibratedRed: 0.96, green: 0.90, blue: 0.74, alpha: 1).setFill()
            rect.fill()
        }
        // Un velo d'ombra in alto: lo schermo sembra incassato nella cassa.
        NSGradient(colors: [NSColor(calibratedWhite: 0, alpha: 0.28), NSColor(calibratedWhite: 0, alpha: 0)])!
            .draw(in: NSRect(x: rect.minX, y: rect.maxY - 9, width: rect.width, height: 9), angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        NSColor(calibratedWhite: 0.0, alpha: 0.9).setStroke()
        shape.lineWidth = 1
        shape.stroke()
    }

    private func drawLabel(in screen: NSRect) {
        let font = NSFont(name: "MarkerFelt-Wide", size: 8.5) ?? NSFont.systemFont(ofSize: 8, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Self.digitColor.withAlphaComponent(0.8)]
        (label as NSString).draw(at: NSPoint(x: screen.minX + 6, y: screen.maxY - 12), withAttributes: attributes)
    }

    // MARK: - Cifre

    private func drawTime(in screen: NSRect) {
        let digitWidth: CGFloat = 17
        let digitHeight: CGFloat = 25
        let thickness: CGFloat = 3.6
        let colonWidth: CGFloat = 7
        let gap: CGFloat = 3
        let shear: CGFloat = 0.16

        let chars = Array(time)
        let total = chars.reduce(CGFloat(0)) { $0 + ($1 == ":" ? colonWidth : digitWidth) } + gap * CGFloat(chars.count - 1)
        // Le cifre sono inclinate: sposto un po' a sinistra per ricentrare l'insieme.
        var x = screen.midX - total / 2 - digitHeight * shear / 2 + 1
        let y = screen.minY + 5

        for ch in chars {
            if ch == ":" {
                drawColon(x: x, y: y, width: colonWidth, height: digitHeight, thickness: thickness, shear: shear)
                x += colonWidth + gap
            } else {
                drawDigit(ch, x: x, y: y, width: digitWidth, height: digitHeight, thickness: thickness, shear: shear)
                x += digitWidth + gap
            }
        }
    }

    private func slanted(_ points: [NSPoint], baseY: CGFloat, shear: CGFloat, dx: CGFloat = 0, dy: CGFloat = 0) -> NSBezierPath {
        let path = NSBezierPath()
        for (i, p) in points.enumerated() {
            let q = NSPoint(x: p.x + (p.y - baseY) * shear + dx, y: p.y + dy)
            i == 0 ? path.move(to: q) : path.line(to: q)
        }
        path.close()
        return path
    }

    private func paint(_ points: [NSPoint], baseY: CGFloat, shear: CGFloat) {
        // Ombra leggera spostata in basso a destra, poi la cifra.
        Self.shadowColor.setFill()
        slanted(points, baseY: baseY, shear: shear, dx: 1.1, dy: -1.1).fill()
        Self.digitColor.setFill()
        slanted(points, baseY: baseY, shear: shear).fill()
    }

    private func drawDigit(_ ch: Character, x ox: CGFloat, y oy: CGFloat, width w: CGFloat, height h: CGFloat,
                           thickness t: CGFloat, shear: CGFloat) {
        guard let on = Self.segments[ch] else { return }
        let g: CGFloat = 0.5   // piccolo vuoto fra un segmento e l'altro
        let top = oy + h - t / 2, mid = oy + h / 2, bottom = oy + t / 2
        let left = ox + t / 2, right = ox + w - t / 2

        func horizontal(_ yc: CGFloat) -> [NSPoint] {
            let x0 = ox + g, x1 = ox + w - g
            return [NSPoint(x: x0, y: yc), NSPoint(x: x0 + t / 2, y: yc + t / 2), NSPoint(x: x1 - t / 2, y: yc + t / 2),
                    NSPoint(x: x1, y: yc), NSPoint(x: x1 - t / 2, y: yc - t / 2), NSPoint(x: x0 + t / 2, y: yc - t / 2)]
        }
        func vertical(_ xc: CGFloat, from y0: CGFloat, to y1: CGFloat) -> [NSPoint] {
            [NSPoint(x: xc, y: y0 + g), NSPoint(x: xc + t / 2, y: y0 + g + t / 2), NSPoint(x: xc + t / 2, y: y1 - g - t / 2),
             NSPoint(x: xc, y: y1 - g), NSPoint(x: xc - t / 2, y: y1 - g - t / 2), NSPoint(x: xc - t / 2, y: y0 + g + t / 2)]
        }

        let shapes: [Character: [NSPoint]] = [
            "a": horizontal(top),
            "b": vertical(right, from: mid, to: oy + h),
            "c": vertical(right, from: oy, to: mid),
            "d": horizontal(bottom),
            "e": vertical(left, from: oy, to: mid),
            "f": vertical(left, from: mid, to: oy + h),
            "g": horizontal(mid),
        ]
        for key in on {
            if let points = shapes[key] { paint(points, baseY: oy, shear: shear) }
        }
    }

    private func drawColon(x ox: CGFloat, y oy: CGFloat, width w: CGFloat, height h: CGFloat, thickness t: CGFloat, shear: CGFloat) {
        let size = t * 0.95
        let cx = ox + w / 2
        for yc in [oy + h * 0.30, oy + h * 0.70] {
            let points = [
                NSPoint(x: cx - size / 2, y: yc - size / 2), NSPoint(x: cx + size / 2, y: yc - size / 2),
                NSPoint(x: cx + size / 2, y: yc + size / 2), NSPoint(x: cx - size / 2, y: yc + size / 2),
            ]
            paint(points, baseY: oy, shear: shear)
        }
    }
}
