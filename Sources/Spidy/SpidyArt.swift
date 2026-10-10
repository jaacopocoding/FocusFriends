import AppKit

enum SpidyPose {
    case idle
    case stepLeft
    case stepRight
}

/// Disegno vettoriale di Spidy, in uno spazio 100x100 scalato sul rettangolo richiesto.
enum SpidyArt {
    static let red = NSColor(calibratedRed: 0.89, green: 0.12, blue: 0.14, alpha: 1)
    static let blue = NSColor(calibratedRed: 0.14, green: 0.27, blue: 0.64, alpha: 1)
    static let ink = NSColor(calibratedWhite: 0.07, alpha: 1)

    static func draw(_ pose: SpidyPose, in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.scaleX(by: rect.width / 100, yBy: rect.height / 100)
        transform.concat()

        let leftLift: CGFloat
        let rightLift: CGFloat
        let bob: CGFloat
        switch pose {
        case .idle:      (leftLift, rightLift, bob) = (0, 0, 0)
        case .stepLeft:  (leftLift, rightLift, bob) = (6, 0, 1.5)
        case .stepRight: (leftLift, rightLift, bob) = (0, 6, 1.5)
        }

        // Gambe e stivali: restano a terra, solo il piede alzato si muove.
        drawLeg(x: 41, lift: leftLift)
        drawLeg(x: 59, lift: rightLift)

        // Tutto il resto fa un piccolo rimbalzo mentre cammina.
        let upper = NSAffineTransform()
        upper.translateX(by: 0, yBy: bob)
        upper.concat()

        // Braccia (dietro al busto): quella opposta alla gamba alzata va in avanti.
        drawArm(from: NSPoint(x: 36, y: 45), to: NSPoint(x: 25, y: 33 + (pose == .stepRight ? 4 : 0)))
        drawArm(from: NSPoint(x: 64, y: 45), to: NSPoint(x: 75, y: 33 + (pose == .stepLeft ? 4 : 0)))

        drawTorso()
        drawHead()
    }

    // MARK: - Parti del corpo

    private static func limb(from a: NSPoint, to b: NSPoint, width: CGFloat, color: NSColor) {
        let outline = NSBezierPath()
        outline.move(to: a)
        outline.line(to: b)
        outline.lineCapStyle = .round

        outline.lineWidth = width + 3.2
        ink.setStroke()
        outline.stroke()

        outline.lineWidth = width
        color.setStroke()
        outline.stroke()
    }

    private static func drawLeg(x: CGFloat, lift: CGFloat) {
        limb(from: NSPoint(x: x, y: 28), to: NSPoint(x: x, y: 13 + lift), width: 9, color: blue)
        // Stivale
        let boot = NSBezierPath(roundedRect: NSRect(x: x - 7, y: 4 + lift, width: 14, height: 10), xRadius: 4, yRadius: 4)
        red.setFill()
        boot.fill()
        ink.setStroke()
        boot.lineWidth = 2.2
        boot.stroke()
    }

    private static func drawArm(from shoulder: NSPoint, to hand: NSPoint) {
        limb(from: shoulder, to: hand, width: 8, color: red)
        let glove = NSBezierPath(ovalIn: NSRect(x: hand.x - 5, y: hand.y - 5, width: 10, height: 10))
        red.setFill()
        glove.fill()
        ink.setStroke()
        glove.lineWidth = 2.2
        glove.stroke()
    }

    private static func drawTorso() {
        let torso = NSBezierPath(roundedRect: NSRect(x: 35, y: 25, width: 30, height: 25), xRadius: 8, yRadius: 8)
        red.setFill()
        torso.fill()

        // Parte bassa blu
        NSGraphicsContext.saveGraphicsState()
        torso.addClip()
        blue.setFill()
        NSRect(x: 35, y: 25, width: 30, height: 9).fill()
        NSGraphicsContext.restoreGraphicsState()

        ink.setStroke()
        torso.lineWidth = 2.4
        torso.stroke()

        drawChestSpider(at: NSPoint(x: 50, y: 40))
    }

    private static func drawChestSpider(at c: NSPoint) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let shrink = NSAffineTransform()
        shrink.translateX(by: c.x, yBy: c.y)
        shrink.scaleX(by: 0.8, yBy: 0.8)
        shrink.translateX(by: -c.x, yBy: -c.y)
        shrink.concat()

        ink.setStroke()
        ink.setFill()
        let legs = NSBezierPath()
        legs.lineWidth = 1.8
        legs.lineCapStyle = .round
        legs.lineJoinStyle = .round
        // Quattro zampe per lato, con il "ginocchio" verso l'esterno.
        let reach: [(knee: NSPoint, tip: NSPoint)] = [
            (NSPoint(x: 5, y: 7), NSPoint(x: 10, y: 8)),
            (NSPoint(x: 7, y: 2.5), NSPoint(x: 12, y: 3)),
            (NSPoint(x: 7, y: -2.5), NSPoint(x: 11, y: -5)),
            (NSPoint(x: 5, y: -5), NSPoint(x: 8, y: -9)),
        ]
        for side: CGFloat in [-1, 1] {
            for leg in reach {
                legs.move(to: c)
                legs.line(to: NSPoint(x: c.x + side * leg.knee.x, y: c.y + leg.knee.y))
                legs.line(to: NSPoint(x: c.x + side * leg.tip.x, y: c.y + leg.tip.y))
            }
        }
        legs.stroke()
        NSBezierPath(ovalIn: NSRect(x: c.x - 2.6, y: c.y - 4, width: 5.2, height: 8)).fill()
        NSBezierPath(ovalIn: NSRect(x: c.x - 1.7, y: c.y + 3, width: 3.4, height: 3.4)).fill()
    }

    private static func drawHead() {
        let center = NSPoint(x: 50, y: 72)
        let radius: CGFloat = 25
        let head = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))

        red.setFill()
        head.fill()

        // Ragnatela, tagliata sul contorno della testa.
        NSGraphicsContext.saveGraphicsState()
        head.addClip()
        ink.setStroke()

        let web = NSBezierPath()
        web.lineWidth = 1.3
        let spokes = 12
        for i in 0..<spokes {
            let a = CGFloat(i) * 2 * .pi / CGFloat(spokes)
            web.move(to: center)
            web.line(to: point(center, radius + 4, a))
        }
        for r: CGFloat in [9, 17] {
            for i in 0..<spokes {
                let a0 = CGFloat(i) * 2 * .pi / CGFloat(spokes)
                let a1 = CGFloat(i + 1) * 2 * .pi / CGFloat(spokes)
                let mid = point(center, r * 0.85, (a0 + a1) / 2)
                web.move(to: point(center, r, a0))
                web.curve(to: point(center, r, a1), controlPoint1: mid, controlPoint2: mid)
            }
        }
        web.stroke()
        NSGraphicsContext.restoreGraphicsState()

        ink.setStroke()
        head.lineWidth = 3
        head.stroke()

        drawEye(mirrored: false)
        drawEye(mirrored: true)
    }

    private static func drawEye(mirrored: Bool) {
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: mirrored ? 100 - x : x, y: y + 3) }

        // Occhio a mandorla inclinato verso il naso, come nel logo.
        let eye = NSBezierPath()
        eye.move(to: p(25, 73))
        eye.curve(to: p(47, 64), controlPoint1: p(31, 82), controlPoint2: p(42, 74))
        eye.curve(to: p(25, 73), controlPoint1: p(38, 59), controlPoint2: p(28, 65))
        eye.close()

        NSColor.white.setFill()
        eye.fill()
        ink.setStroke()
        eye.lineWidth = 2.6
        eye.lineJoinStyle = .round
        eye.stroke()
    }

    private static func point(_ c: NSPoint, _ r: CGFloat, _ angle: CGFloat) -> NSPoint {
        NSPoint(x: c.x + r * cos(angle), y: c.y + r * sin(angle))
    }
}
