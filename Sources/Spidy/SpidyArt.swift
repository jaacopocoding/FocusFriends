import AppKit

enum SpidyPose {
    case idle
    case stepLeft
    case stepRight
}

/// Disegno vettoriale di Spidy in stile "pupazzetto di vinile": forme morbide, sfumature, testa enorme.
/// Il disegno vive in uno spazio 100x100 che viene scalato sul rettangolo richiesto.
enum SpidyArt {
    static let red = NSColor(calibratedRed: 0.90, green: 0.12, blue: 0.14, alpha: 1)
    static let blue = NSColor(calibratedRed: 0.12, green: 0.30, blue: 0.82, alpha: 1)
    static let ink = NSColor(calibratedWhite: 0.06, alpha: 1)

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
        let tilt: CGFloat   // inclinazione della testa, in gradi
        switch pose {
        case .idle:      (leftLift, rightLift, bob, tilt) = (0, 0, 0, 0)
        case .stepLeft:  (leftLift, rightLift, bob, tilt) = (5, 0, 1.2, 3)
        case .stepRight: (leftLift, rightLift, bob, tilt) = (0, 5, 1.2, -3)
        }

        drawGroundShadow()

        // Gambe: restano a terra, si alza solo il piede del passo.
        drawLeg(x: 42, lift: leftLift)
        drawLeg(x: 58, lift: rightLift)

        // Il resto rimbalza leggermente mentre cammina.
        let upper = NSAffineTransform()
        upper.translateX(by: 0, yBy: bob)
        upper.concat()

        // Braccia: quella opposta alla gamba alzata va in avanti.
        drawArm(side: -1, handLift: pose == .stepRight ? 4 : 0)
        drawArm(side: 1, handLift: pose == .stepLeft ? 4 : 0)

        drawTorso()

        // La testa si inclina un po' da una parte e dall'altra, attorno al collo.
        let head = NSAffineTransform()
        head.translateX(by: 50, yBy: 46)
        head.rotate(byDegrees: tilt)
        head.translateX(by: -50, yBy: -46)
        head.concat()
        drawHead()
    }

    // MARK: - Utilità

    private static func shade(_ base: NSColor, light: CGFloat = 0.35, dark: CGFloat = 0.32) -> (light: NSColor, dark: NSColor) {
        (base.highlight(withLevel: light) ?? base, base.shadow(withLevel: dark) ?? base)
    }

    /// Riempie un tracciato con una sfumatura dall'alto verso il basso, più un contorno morbido dello stesso colore scurito.
    private static func fillShaded(_ path: NSBezierPath, _ base: NSColor, radial: Bool = false, edge: CGFloat = 1.2) {
        let (light, dark) = shade(base)
        let gradient = NSGradient(colors: [light, base, dark], atLocations: [0, 0.5, 1], colorSpace: .deviceRGB)!
        if radial {
            gradient.draw(in: path, relativeCenterPosition: NSPoint(x: -0.3, y: 0.4))
        } else {
            gradient.draw(in: path, angle: -80)
        }
        if edge > 0 {
            (base.shadow(withLevel: 0.55) ?? base).withAlphaComponent(0.75).setStroke()
            path.lineWidth = edge
            path.stroke()
        }
    }

    private static func point(_ c: NSPoint, _ rx: CGFloat, _ ry: CGFloat, _ r: CGFloat, _ angle: CGFloat) -> NSPoint {
        NSPoint(x: c.x + r * rx * cos(angle), y: c.y + r * ry * sin(angle))
    }

    // MARK: - Parti del corpo

    private static func drawGroundShadow() {
        NSColor.black.withAlphaComponent(0.18).setFill()
        NSBezierPath(ovalIn: NSRect(x: 24, y: 1, width: 52, height: 8)).fill()
    }

    private static func drawLeg(x: CGFloat, lift: CGFloat) {
        let leg = NSBezierPath(roundedRect: NSRect(x: x - 6, y: 12 + lift, width: 12, height: 18), xRadius: 5.5, yRadius: 5.5)
        fillShaded(leg, blue)

        // Stivaletto rosso, un po' più largo, con la punta in fuori.
        let boot = NSBezierPath(roundedRect: NSRect(x: x - 8.5, y: 4 + lift, width: 17, height: 11), xRadius: 5.5, yRadius: 5.5)
        fillShaded(boot, red)
    }

    private static func drawArm(side: CGFloat, handLift: CGFloat) {
        let shoulder = NSPoint(x: 50 + side * 14, y: 43)
        let elbow = NSPoint(x: 50 + side * 21, y: 37)
        let hand = NSPoint(x: 50 + side * 25, y: 29 + handLift)

        func stroke(_ a: NSPoint, _ b: NSPoint, width: CGFloat, color: NSColor) {
            let path = NSBezierPath()
            path.move(to: a)
            path.line(to: b)
            path.lineCapStyle = .round

            path.lineWidth = width + 1.4
            (color.shadow(withLevel: 0.55) ?? color).setStroke()
            path.stroke()

            path.lineWidth = width
            color.setStroke()
            path.stroke()

            // Riflesso di luce sul lato alto-sinistra
            let hi = NSBezierPath()
            hi.move(to: NSPoint(x: a.x - 1.2, y: a.y + 1.2))
            hi.line(to: NSPoint(x: b.x - 1.2, y: b.y + 1.2))
            hi.lineCapStyle = .round
            hi.lineWidth = width * 0.28
            (color.highlight(withLevel: 0.5) ?? color).withAlphaComponent(0.55).setStroke()
            hi.stroke()
        }

        stroke(shoulder, elbow, width: 9, color: blue)     // parte alta del braccio blu
        stroke(elbow, hand, width: 8, color: red)          // avambraccio rosso
        let glove = NSBezierPath(ovalIn: NSRect(x: hand.x - 4.8, y: hand.y - 4.8, width: 9.6, height: 9.6))
        fillShaded(glove, red)
    }

    private static func drawTorso() {
        let torso = NSBezierPath(roundedRect: NSRect(x: 36, y: 22, width: 28, height: 26), xRadius: 11, yRadius: 11)
        fillShaded(torso, red, edge: 0)

        NSGraphicsContext.saveGraphicsState()
        torso.addClip()
        // Fianchi blu e fascia bassa blu, come nel costume.
        let (light, dark) = shade(blue)
        let side = NSGradient(colors: [light, blue, dark], atLocations: [0, 0.5, 1], colorSpace: .deviceRGB)!
        for flip: CGFloat in [-1, 1] {
            let panel = NSBezierPath()
            panel.move(to: NSPoint(x: 50 + flip * 15, y: 49))
            panel.curve(to: NSPoint(x: 50 + flip * 8.5, y: 31), controlPoint1: NSPoint(x: 50 + flip * 12, y: 44), controlPoint2: NSPoint(x: 50 + flip * 8, y: 38))
            panel.line(to: NSPoint(x: 50 + flip * 8.5, y: 20))
            panel.line(to: NSPoint(x: 50 + flip * 15, y: 20))
            panel.close()
            side.draw(in: panel, angle: -80)
        }
        let belt = NSBezierPath(rect: NSRect(x: 30, y: 20, width: 40, height: 9))
        side.draw(in: belt, angle: -80)
        NSGraphicsContext.restoreGraphicsState()

        (red.shadow(withLevel: 0.55) ?? red).withAlphaComponent(0.75).setStroke()
        torso.lineWidth = 1.2
        torso.stroke()

        drawChestSpider(at: NSPoint(x: 50, y: 35))
    }

    private static func drawChestSpider(at c: NSPoint) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let shrink = NSAffineTransform()
        shrink.translateX(by: c.x, yBy: c.y)
        shrink.scaleX(by: 0.7, yBy: 0.7)
        shrink.translateX(by: -c.x, yBy: -c.y)
        shrink.concat()

        ink.setStroke()
        ink.setFill()
        let legs = NSBezierPath()
        legs.lineWidth = 1.9
        legs.lineCapStyle = .round
        legs.lineJoinStyle = .round
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
        NSBezierPath(ovalIn: NSRect(x: c.x - 2.8, y: c.y - 4.2, width: 5.6, height: 8.4)).fill()
        NSBezierPath(ovalIn: NSRect(x: c.x - 1.8, y: c.y + 3.2, width: 3.6, height: 3.6)).fill()
    }

    private static func drawHead() {
        let center = NSPoint(x: 50, y: 71)
        let rx: CGFloat = 29
        let ry: CGFloat = 26
        let head = NSBezierPath(ovalIn: NSRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2))
        fillShaded(head, red, radial: true, edge: 0)

        // Ragnatela sottile, tagliata sul contorno della testa. Il centro è alto, sopra gli occhi.
        NSGraphicsContext.saveGraphicsState()
        head.addClip()
        let hub = NSPoint(x: 50, y: 83)
        ink.withAlphaComponent(0.9).setStroke()

        let web = NSBezierPath()
        web.lineWidth = 1.0
        web.lineCapStyle = .round
        let spokes = 14
        for i in 0..<spokes {
            let a = CGFloat(i) * 2 * .pi / CGFloat(spokes) + 0.1
            web.move(to: hub)
            web.line(to: point(hub, rx, ry, 1.5, a))
        }
        for r: CGFloat in [0.22, 0.42, 0.64, 0.88] {
            for i in 0..<spokes {
                let a0 = CGFloat(i) * 2 * .pi / CGFloat(spokes) + 0.1
                let a1 = CGFloat(i + 1) * 2 * .pi / CGFloat(spokes) + 0.1
                let mid = point(hub, rx, ry, r * 0.88, (a0 + a1) / 2)
                web.move(to: point(hub, rx, ry, r, a0))
                web.curve(to: point(hub, rx, ry, r, a1), controlPoint1: mid, controlPoint2: mid)
            }
        }
        web.stroke()
        NSGraphicsContext.restoreGraphicsState()

        (red.shadow(withLevel: 0.6) ?? red).setStroke()
        head.lineWidth = 1.6
        head.stroke()

        drawEye(mirrored: false)
        drawEye(mirrored: true)
    }

    private static func drawEye(mirrored: Bool) {
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: mirrored ? 100 - x : x, y: y + 3) }

        // Occhio grande e tondo, inclinato verso il naso: angolo esterno alto, angolo interno basso.
        let eye = NSBezierPath()
        eye.move(to: p(25, 66))
        eye.curve(to: p(48, 52), controlPoint1: p(34, 72), controlPoint2: p(46, 63))
        eye.curve(to: p(25, 66), controlPoint1: p(46, 40), controlPoint2: p(22, 46))
        eye.close()

        let gradient = NSGradient(colors: [NSColor.white, NSColor(calibratedWhite: 0.88, alpha: 1)])!
        gradient.draw(in: eye, angle: -80)

        ink.setStroke()
        eye.lineWidth = 3.4
        eye.lineJoinStyle = .round
        eye.stroke()
    }
}
