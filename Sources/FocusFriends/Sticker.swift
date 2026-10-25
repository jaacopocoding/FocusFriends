import AppKit

/// Le figurine dell'album del giardino: un cartoncino crema con il numero, il disegno e il nome. La rarità è la finitura del bordo
/// (semplice, argento con un lucido, oro con un luccichio): tutto disegnato qui, niente immagini in più. Una figurina che non hai ancora
/// è una casella con il numero e la sagoma. Si disegna in una vista capovolta (origine in alto), come le altre schede.
enum Sticker {
    struct Look {
        var item: GardenItem
        var number: Int
        var found: Bool
        /// Quante copie si sono trovate e quante sono nel prato.
        var copies: Int
        var isNew: Bool
    }

    static let card = NSColor(calibratedRed: 1, green: 0.99, blue: 0.94, alpha: 1)
    static let silver = NSColor(calibratedRed: 0.58, green: 0.66, blue: 0.77, alpha: 1)
    static let gold = NSColor(calibratedRed: 0.86, green: 0.66, blue: 0.18, alpha: 1)

    static func color(for rarity: GardenRarity) -> NSColor {
        switch rarity {
        case .common: return Paper.paperEdge
        case .rare: return silver
        case .legendary: return gold
        }
    }

    private static let numberFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
    private static let badgeFont = NSFont.systemFont(ofSize: 9.5, weight: .bold)

    private static func text(_ string: String, in rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .center) {
        let para = NSMutableParagraphStyle()
        para.alignment = alignment
        para.lineBreakMode = .byTruncatingTail
        (string as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
    }

    private static var silhouettes: [String: NSImage] = [:]

    /// La sagoma di un oggetto (il suo disegno tutto di un colore), per le figurine ancora da trovare.
    private static func silhouette(of sprite: GardenSprite, key: String) -> NSImage {
        if let known = silhouettes[key] { return known }
        let size = sprite.source.size
        let image = NSImage(size: size, flipped: false) { box in
            sprite.image.draw(in: box, from: sprite.source, operation: .sourceOver, fraction: 1)
            Paper.paperEdge.withAlphaComponent(0.55).set()
            box.fill(using: .sourceAtop)
            return true
        }
        silhouettes[key] = image
        return image
    }

    /// Una striscia di luce in diagonale che attraversa il cartoncino (`position` da 0 a 1).
    private static func drawShine(in rect: NSRect, position: CGFloat, strength: CGFloat) {
        let slant: CGFloat = rect.height * 0.5
        let width = rect.width * 0.28
        let x = rect.minX - slant - width + (rect.width + slant * 2 + width * 2) * position
        let band = NSBezierPath()
        band.move(to: NSPoint(x: x, y: rect.maxY))
        band.line(to: NSPoint(x: x + width, y: rect.maxY))
        band.line(to: NSPoint(x: x + width + slant, y: rect.minY))
        band.line(to: NSPoint(x: x + slant, y: rect.minY))
        band.close()
        NSColor.white.withAlphaComponent(strength).setFill()
        band.fill()
    }

    private static func drawStar(at center: NSPoint, radius: CGFloat, color: NSColor) {
        let star = NSBezierPath()
        let inner = radius * 0.28
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4 - .pi / 2
            let r = i % 2 == 0 ? radius : inner
            let point = NSPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            if i == 0 { star.move(to: point) } else { star.line(to: point) }
        }
        star.close()
        color.setFill()
        star.fill()
    }

    /// Disegna la figurina nel rettangolo. `shine` (da 0 a 1) è dove sta la luce che passa; senza, ce n'è una ferma e leggera.
    static func draw(_ look: Look, in rect: NSRect, shine: CGFloat? = nil) {
        let rarity = look.item.rarity
        let radius = min(rect.width, rect.height) * 0.11
        let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: radius, yRadius: radius)

        if look.found {
            card.setFill()
            shape.fill()
            if rarity == .legendary {
                NSColor(calibratedRed: 1, green: 0.93, blue: 0.70, alpha: 0.55).setFill()
                shape.fill()
            }
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            if rarity >= .rare { drawShine(in: rect, position: shine ?? 0.22, strength: shine == nil ? 0.20 : 0.42) }
            NSGraphicsContext.restoreGraphicsState()
            color(for: rarity).setStroke()
            shape.lineWidth = rarity == .common ? 1.2 : rarity == .rare ? 2.2 : 3
            shape.stroke()
        } else {
            Paper.track.setFill()
            shape.fill()
            Paper.paperEdge.withAlphaComponent(0.7).setStroke()
            shape.lineWidth = 1.2
            shape.setLineDash([4, 3], count: 2, phase: 0)
            shape.stroke()
        }

        // il numero, in alto a sinistra
        text(String(format: "n. %02d", look.number), in: NSRect(x: rect.minX + 8, y: rect.minY + 5, width: 40, height: 12), font: numberFont,
             color: look.found ? Paper.inkLight : Paper.inkLight.withAlphaComponent(0.8), alignment: .left)

        // il disegno (o la sagoma)
        let box = NSRect(x: rect.minX + 8, y: rect.minY + 19, width: rect.width - 16, height: rect.height - 19 - 24)
        if let sprite = GardenSprites.sprite(look.item.resource) {
            let scale = min(box.width / max(sprite.source.width, 1), box.height / max(sprite.source.height, 1))
            let size = NSSize(width: sprite.source.width * scale, height: sprite.source.height * scale)
            let target = NSRect(x: box.midX - size.width / 2, y: box.maxY - size.height, width: size.width, height: size.height)
            if look.found {
                sprite.image.draw(in: target, from: sprite.source, operation: .sourceOver, fraction: 1,
                                  respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            } else {
                silhouette(of: sprite, key: look.item.id).draw(in: target, from: .zero, operation: .sourceOver, fraction: 1,
                                                                respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            }
        }

        // il nome, o la rarità se non ce l'hai
        var nameFont = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        if look.found, (look.item.name as NSString).size(withAttributes: [.font: nameFont]).width > rect.width - 10 {
            nameFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
        }
        if look.found {
            text(look.item.name, in: NSRect(x: rect.minX + 4, y: rect.maxY - 20, width: rect.width - 8, height: 14), font: nameFont, color: Paper.ink)
        } else {
            let tint: NSColor = rarity == .legendary ? NSColor(calibratedRed: 0.62, green: 0.46, blue: 0.08, alpha: 1)
                : rarity == .rare ? NSColor(calibratedRed: 0.38, green: 0.46, blue: 0.58, alpha: 1) : Paper.inkLight
            text(rarity.title, in: NSRect(x: rect.minX + 4, y: rect.maxY - 20, width: rect.width - 8, height: 14),
                 font: NSFont.systemFont(ofSize: 10, weight: .semibold), color: tint)
        }

        guard look.found else { return }
        // il luccichio dell'oro
        if rarity == .legendary {
            drawStar(at: NSPoint(x: rect.maxX - 12, y: rect.minY + 12), radius: 6, color: gold)
            drawStar(at: NSPoint(x: rect.minX + 12, y: rect.maxY - 31), radius: 3.5, color: gold.withAlphaComponent(0.8))
        }
        // le copie
        if look.copies > 1 {
            let label = "×\(look.copies)"
            let width = ceil((label as NSString).size(withAttributes: [.font: badgeFont]).width) + 10
            let badge = NSRect(x: rect.maxX - width - 5, y: rect.maxY - 41, width: width, height: 15)
            Paper.accent.setFill()
            NSBezierPath(roundedRect: badge, xRadius: 7.5, yRadius: 7.5).fill()
            text(label, in: NSRect(x: badge.minX, y: badge.minY + 2, width: badge.width, height: 12), font: badgeFont, color: .white)
        }
        // il nastrino
        if look.isNew {
            let label = "NUOVA"
            let width = ceil((label as NSString).size(withAttributes: [.font: badgeFont]).width) + 10
            let ribbon = NSRect(x: rect.maxX - width - 4, y: rect.minY + 4, width: width, height: 15)
            NSColor(calibratedRed: 0.80, green: 0.25, blue: 0.22, alpha: 1).setFill()
            NSBezierPath(roundedRect: ribbon, xRadius: 4, yRadius: 4).fill()
            text(label, in: NSRect(x: ribbon.minX, y: ribbon.minY + 2, width: ribbon.width, height: 12), font: badgeFont, color: .white)
        }
    }
}
