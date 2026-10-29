import AppKit
import CoreImage

/// Le figure intere dei compagni per la pagina «Avatar» del menu: a colori per chi c'è; per chi non è ancora sbloccato, una sagoma nera e
/// sfocata (si capisce che c'è qualcuno, ma non chi). Si ricavano dall'immagine con cui il compagno sta fermo e si tengono in memoria.
enum AvatarFigures {
    /// Una sagoma sfocata: è più grande della figura (il bordo sfumato esce un po'), e `padX`/`padY` dicono di quanto, in frazione della figura.
    struct Silhouette {
        let image: NSImage
        let padX: CGFloat
        let padY: CGFloat
    }

    /// Quanto sfocare la sagoma, in frazione del lato più lungo della figura: abbastanza da perdere orecchie, becco e zampe, non da sparire.
    static let blur: CGFloat = 0.065
    /// L'altezza massima, in pixel, con cui si lavora la sagoma.
    private static let silhouetteHeight: CGFloat = 300

    private static var figures: [String: CGImage] = [:]
    private static var images: [String: NSImage] = [:]
    private static var silhouettes: [String: Silhouette] = [:]

    /// La figura intera, ritagliata sul disegno (i piedi toccano il bordo di sotto).
    static func figure(for pet: Pet) -> NSImage? {
        if let cached = images[pet.id] { return cached }
        guard let cg = trimmed(pet) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        images[pet.id] = image
        return image
    }

    /// La sagoma nera e sfocata, da disegnare in un rettangolo allargato della figura (`padX`, `padY`).
    static func silhouette(for pet: Pet) -> Silhouette? {
        if let cached = silhouettes[pet.id] { return cached }
        guard let cg = trimmed(pet) else { return nil }
        let scale = min(1, silhouetteHeight / CGFloat(cg.height))
        let source = CIImage(cgImage: cg).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let width = source.extent.width, height = source.extent.height
        let sigma = max(width, height) * blur
        let pad = ceil(sigma * 3)
        let canvas = source.extent.insetBy(dx: -pad, dy: -pad)
        // nero: si tiene solo la trasparenza del disegno
        guard let black = CIFilter(name: "CIColorMatrix", parameters: [
            kCIInputImageKey: source,
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)])?.outputImage else { return nil }
        let blurred = black.composited(over: CIImage(color: .clear).cropped(to: canvas))
            .applyingGaussianBlur(sigma: Double(sigma)).cropped(to: canvas)
        guard let out = CIContext().createCGImage(blurred, from: canvas) else { return nil }
        let result = Silhouette(image: NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height)),
                                padX: pad / width, padY: pad / height)
        silhouettes[pet.id] = result
        return result
    }

    /// L'immagine di quando sta fermo, senza i margini trasparenti.
    private static func trimmed(_ pet: Pet) -> CGImage? {
        if let cached = figures[pet.id] { return cached }
        guard let url = Bundle.main.url(forResource: pet.iconResource, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drew = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drew else { return nil }
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h {
            for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 20 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY,
              let cropped = image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) else { return nil }
        figures[pet.id] = cropped
        return cropped
    }
}

/// Il palco della pagina «Avatar»: i compagni in fila, quello scelto grande al centro e i vicini più piccoli ai lati. Si scorre trascinando, con
/// due dita sul trackpad, toccando un vicino o con le frecce della scheda. Chi non è sbloccato è una sagoma nera sfocata.
final class AvatarStageView: NSView {
    struct Slot {
        let pet: Pet
        let isUnlocked: Bool
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Quanto distano i centri di due compagni vicini, e quanto è grande lo spazio di una figura (il vicino è più piccolo).
    private static let spacing: CGFloat = 104
    private static let box = NSSize(width: 150, height: 176)

    private(set) var slots: [Slot] = []
    /// Il compagno al centro.
    private(set) var index = 0
    /// Cambia quando si arriva su un altro compagno.
    var onChange: ((Int) -> Void)?

    /// Il punto in cui si trova la fila, in compagni (con la virgola mentre scorre): da 0 all'ultimo.
    private var position: CGFloat = 0
    private var ticker: Timer?
    private var dragOrigin: CGFloat?
    private var dragPosition: CGFloat = 0
    private var dragIndex = 0
    private var didDrag = false
    private var scrollSum: CGFloat = 0
    private var scrolled = false

    deinit { ticker?.invalidate() }

    /// Mette i compagni sul palco; `index` dice chi sta al centro (se è un altro da quello di adesso, la fila scorre).
    func configure(slots: [Slot], index requested: Int) {
        let first = self.slots.isEmpty
        self.slots = slots
        let target = max(0, min(requested, slots.count - 1))
        if first {
            self.index = target
            position = CGFloat(target)
            needsDisplay = true
        } else if target != self.index {
            go(to: target, notify: false)
        } else {
            needsDisplay = true
        }
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func go(to requested: Int, notify: Bool = true) {
        let target = max(0, min(requested, slots.count - 1))
        let changed = target != index
        index = target
        if reduceMotion {
            position = CGFloat(target)
            needsDisplay = true
        } else {
            startTicker()
        }
        if changed && notify { onChange?(target) }
    }

    private func startTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            let gap = CGFloat(self.index) - self.position
            if abs(gap) < 0.003 {
                self.position = CGFloat(self.index)
                self.ticker?.invalidate()
                self.ticker = nil
            } else {
                self.position += gap * 0.22
            }
            self.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    // MARK: - Gesti

    override func mouseDown(with event: NSEvent) {
        dragOrigin = convert(event.locationInWindow, from: nil).x
        dragPosition = position
        dragIndex = index
        didDrag = false
        ticker?.invalidate()
        ticker = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        let dx = convert(event.locationInWindow, from: nil).x - origin
        if abs(dx) > 3 { didDrag = true }
        guard didDrag else { return }
        position = max(-0.25, min(dragPosition - dx / Self.spacing, CGFloat(slots.count - 1) + 0.25))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        dragOrigin = nil
        let x = convert(event.locationInWindow, from: nil).x
        if didDrag {
            // un trascinamento deciso va al vicino; uno piccolo torna dov'era (o va al più vicino)
            let dx = x - origin
            go(to: abs(dx) > 36 ? dragIndex + (dx < 0 ? 1 : -1) : Int(position.rounded()))
        } else if x - bounds.midX < -50 {
            go(to: index - 1)
        } else if x - bounds.midX > 50 {
            go(to: index + 1)
        } else {
            go(to: index)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { super.scrollWheel(with: event); return }
        guard event.hasPreciseScrollingDeltas else {
            go(to: index + (event.scrollingDeltaX < 0 ? 1 : -1))
            return
        }
        if event.phase == .began || event.phase == .mayBegin { scrollSum = 0; scrolled = false }
        if !scrolled {
            scrollSum += event.scrollingDeltaX
            if abs(scrollSum) > 30 {
                scrolled = true
                go(to: index + (scrollSum < 0 ? 1 : -1))
            }
        }
        if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended { scrollSum = 0; scrolled = false }
    }

    // MARK: - Disegno

    override func draw(_ dirtyRect: NSRect) {
        guard !slots.isEmpty else { return }
        let ground = bounds.maxY - 22
        // dal più lontano al più vicino, così quello al centro sta sopra
        for i in slots.indices.sorted(by: { abs(CGFloat($0) - position) > abs(CGFloat($1) - position) }) {
            let d = CGFloat(i) - position
            let distance = abs(d)
            guard distance < 2 else { continue }
            let scale = 1 - 0.4 * min(distance, 1)
            let alpha: CGFloat = distance <= 1 ? 1 - 0.15 * distance : max(0, 2 - distance) * 0.85
            let centerX = bounds.midX + d * Self.spacing
            NSColor(calibratedRed: 0.16, green: 0.10, blue: 0.06, alpha: 0.16 * alpha).setFill()
            NSBezierPath(ovalIn: NSRect(x: centerX - 56 * scale, y: ground - 7 * scale, width: 112 * scale, height: 14 * scale)).fill()
            let size = NSSize(width: Self.box.width * scale, height: Self.box.height * scale)
            drawFigure(slots[i], in: NSRect(x: centerX - size.width / 2, y: ground - size.height, width: size.width, height: size.height), alpha: alpha)
        }
    }

    /// La figura nel suo spazio, coi piedi sul fondo.
    private func drawFigure(_ slot: Slot, in box: NSRect, alpha: CGFloat) {
        guard let figure = AvatarFigures.figure(for: slot.pet) else { return }
        let fit = min(box.width / figure.size.width, box.height / figure.size.height)
        let size = NSSize(width: figure.size.width * fit, height: figure.size.height * fit)
        let rect = NSRect(x: box.midX - size.width / 2, y: box.maxY - size.height, width: size.width, height: size.height)
        if slot.isUnlocked {
            figure.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        } else if let silhouette = AvatarFigures.silhouette(for: slot.pet) {
            silhouette.image.draw(in: rect.insetBy(dx: -rect.width * silhouette.padX, dy: -rect.height * silhouette.padY), from: .zero,
                                  operation: .sourceOver, fraction: alpha * 0.92, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        }
    }
}
