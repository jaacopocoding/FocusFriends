import AppKit

/// Un'immagine del giardino (un oggetto, un compagno) con la parte che si vede davvero e una griglia per capire dove cade un clic.
struct GardenSprite {
    let image: NSImage
    /// La parte che non è trasparente, in coordinate dell'immagine (origine in basso a sinistra).
    let source: NSRect
    /// Una griglia grossolana dei punti disegnati (dall'alto in basso), per capire se un clic cade sull'oggetto
    /// e non sul vuoto dentro il suo rettangolo (un arco, le bandierine).
    let mask: [Bool]
    let columns: Int
    let rows: Int
    var aspect: CGFloat { source.width / max(source.height, 1) }

    /// C'è qualcosa di disegnato in (u, v), dentro la parte visibile (v dall'alto), o a una cella di distanza?
    func isDrawn(u: CGFloat, v: CGFloat) -> Bool {
        guard columns > 0, rows > 0, !mask.isEmpty else { return true }
        let column = Int((u * CGFloat(columns)).rounded(.down)), row = Int((v * CGFloat(rows)).rounded(.down))
        for r in max(row - 1, 0)...min(row + 1, rows - 1) {
            for c in max(column - 1, 0)...min(column + 1, columns - 1) where mask[r * columns + c] { return true }
        }
        return false
    }
}

/// Lo spazio dei colori su cui si disegna: i disegni già pronti (lo sfondo, il terreno, gli oggetti) si preparano nello stesso, così copiarli sullo
/// schermo non obbliga a convertire i colori ad ogni fotogramma (che costava quanto tutto il resto).
enum GardenDisplay {
    static func colorSpace(_ window: NSWindow? = nil) -> CGColorSpace {
        window?.colorSpace?.cgColorSpace ?? NSScreen.main?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
    }

    static func name(_ space: CGColorSpace) -> String { (space.name as String?) ?? "?" }
}

/// La tinta della luce del momento (di notte azzurra, di giorno nessuna: 255, 255, 255), a scalini, per dipingere gli oggetti già tinti.
struct GardenTint: Hashable {
    var red: Int
    var green: Int
    var blue: Int

    static let none = GardenTint(red: 255, green: 255, blue: 255)

    var isNone: Bool { red == 255 && green == 255 && blue == 255 }

    /// Dal colore con cui si moltiplica la scena, arrotondato a scalini di 6 (così non si rifanno gli oggetti ad ogni minuto del tramonto).
    init(multiplier: GardenRGB) {
        func step(_ value: Double) -> Int { min(255, max(0, Int((value / 6).rounded()) * 6)) }
        red = step(multiplier.red); green = step(multiplier.green); blue = step(multiplier.blue)
    }

    init(red: Int, green: Int, blue: Int) {
        self.red = red; self.green = green; self.blue = blue
    }
}

/// Copia un'immagine già pronta in un rettangolo (in una vista capovolta o no), senza interpolare: è il modo più veloce di disegnarla.
enum GardenBlit {
    static func draw(_ image: CGImage, in rect: NSRect, alpha: CGFloat = 1, copy: Bool = false) {
        guard let context = NSGraphicsContext.current else { return }
        let cg = context.cgContext
        cg.saveGState()
        cg.interpolationQuality = .none
        if copy { cg.setBlendMode(.copy) }
        cg.setAlpha(alpha)
        if context.isFlipped {
            cg.translateBy(x: rect.minX, y: rect.maxY)
            cg.scaleBy(x: 1, y: -1)
            cg.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        } else {
            cg.draw(image, in: rect)
        }
        cg.restoreGState()
    }
}

/// Le immagini del giardino, lette e analizzate una volta sola.
enum GardenSprites {
    private static var cache: [String: GardenSprite] = [:]
    private static var scaledCache: [String: CGImage] = [:]
    private static var stripCache: [String: [CGImage]] = [:]

    /// Lo stesso oggetto tagliato in `count` strisce orizzontali (dall'alto), ognuna con un pixel in più sotto perché non si veda lo stacco: serve a
    /// piegarlo nel vento. Anche queste si preparano una volta sola per grandezza.
    static func strips(_ sprite: GardenSprite, resource: String, pixelWidth: Int, pixelHeight: Int, count: Int, tint: GardenTint = .none) -> [(image: CGImage, firstRow: Int)] {
        guard let whole = scaled(sprite, resource: resource, pixelWidth: pixelWidth, pixelHeight: pixelHeight, tint: tint) else { return [] }
        let key = "\(resource)|\(pixelWidth)x\(pixelHeight)|\(count)|\(GardenDisplay.name(GardenDisplay.colorSpace()))|\(tint.red),\(tint.green),\(tint.blue)"
        if let known = stripCache[key] { return known.enumerated().map { ($1, $0 * pixelHeight / count) } }
        var pieces: [CGImage] = []
        for index in 0..<count {
            let firstRow = index * pixelHeight / count
            let lastRow = min((index + 1) * pixelHeight / count + (index == count - 1 ? 0 : 1), pixelHeight)
            guard lastRow > firstRow, let piece = whole.cropping(to: CGRect(x: 0, y: firstRow, width: pixelWidth, height: lastRow - firstRow)) else { return [] }
            pieces.append(piece)
        }
        if stripCache.count > 240 { stripCache.removeAll() }
        stripCache[key] = pieces
        return pieces.enumerated().map { ($1, $0 * pixelHeight / count) }
    }

    /// Un oggetto già alla grandezza in pixel con cui lo si disegna (la sola parte che si vede): disegnarlo ingrandito o rimpicciolito ad ogni
    /// fotogramma, con una buona interpolazione, costa molto più che copiarlo. Si rifà solo se la grandezza cambia (lo zoom).
    static func scaled(_ sprite: GardenSprite, resource: String, pixelWidth: Int, pixelHeight: Int, tint: GardenTint = .none) -> CGImage? {
        let space = GardenDisplay.colorSpace()
        let key = "\(resource)|\(pixelWidth)x\(pixelHeight)|\(GardenDisplay.name(space))|\(tint.red),\(tint.green),\(tint.blue)"
        if let known = scaledCache[key] { return known }
        guard pixelWidth > 0, pixelHeight > 0,
              let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current?.imageInterpolation = .high
        sprite.image.draw(in: NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight), from: sprite.source, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        // la luce: i colori si moltiplicano per la tinta (sono già premoltiplicati: l'opacità resta com'è)
        if !tint.isNone, let data = context.data {
            let pixels = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * pixelHeight)
            let factors = (Int(Double(tint.blue) / 255 * 256), Int(Double(tint.green) / 255 * 256), Int(Double(tint.red) / 255 * 256))   // B, G, R (little endian)
            for row in 0..<pixelHeight {
                var offset = row * context.bytesPerRow
                for _ in 0..<pixelWidth {
                    pixels[offset] = UInt8((Int(pixels[offset]) * factors.0) >> 8)
                    pixels[offset + 1] = UInt8((Int(pixels[offset + 1]) * factors.1) >> 8)
                    pixels[offset + 2] = UInt8((Int(pixels[offset + 2]) * factors.2) >> 8)
                    offset += 4
                }
            }
        }
        guard let image = context.makeImage() else { return nil }
        if scaledCache.count > 600 { scaledCache.removeAll() }
        scaledCache[key] = image
        return image
    }

    private static let lock = NSLock()

    /// Un'immagine del pacchetto, già decodificata (di solito si decodifica al primo disegno, e il primo disegno si nota): così si può preparare in anticipo.
    static func loadImage(_ resource: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    static func sprite(_ resource: String) -> GardenSprite? {
        lock.lock()
        let known = cache[resource]
        lock.unlock()
        if let known { return known }
        guard let image = loadImage(resource) else { return nil }
        let made = analyze(image)
        lock.lock()
        cache[resource] = made
        lock.unlock()
        return made
    }

    /// Cerca i pixel non trasparenti: i compagni hanno un bordo vuoto intorno, e i piedi devono stare dove dice il
    /// prato, non dove finisce l'immagine. Ne ricava anche la griglia dei punti disegnati (per i clic).
    private static func analyze(_ image: NSImage) -> GardenSprite {
        let full = GardenSprite(image: image, source: NSRect(origin: .zero, size: image.size), mask: [], columns: 0, rows: 0)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return full }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return full }
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return full }
        let threshold: UInt8 = 24
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h {
            for x in 0..<w where data[(y * w + x) * 4 + 3] > threshold {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return full }
        let boxW = maxX - minX + 1, boxH = maxY - minY + 1
        // La griglia dei clic: al massimo 64 celle sul lato lungo.
        let long = 64
        let columns = boxW >= boxH ? long : max(1, Int((Double(long) * Double(boxW) / Double(boxH)).rounded()))
        let rows = boxH > boxW ? long : max(1, Int((Double(long) * Double(boxH) / Double(boxW)).rounded()))
        var mask = [Bool](repeating: false, count: columns * rows)
        for y in minY...maxY {
            let row = min((y - minY) * rows / boxH, rows - 1)
            for x in minX...maxX where data[(y * w + x) * 4 + 3] > threshold {
                mask[row * columns + min((x - minX) * columns / boxW, columns - 1)] = true
            }
        }
        // La memoria parte dalla riga in alto: nell'immagine l'origine è in basso.
        let sx = image.size.width / CGFloat(w), sy = image.size.height / CGFloat(h)
        let source = NSRect(x: CGFloat(minX) * sx, y: CGFloat(h - 1 - maxY) * sy, width: CGFloat(boxW) * sx, height: CGFloat(boxH) * sy)
        return GardenSprite(image: image, source: source, mask: mask, columns: columns, rows: rows)
    }
}
