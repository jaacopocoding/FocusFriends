import AppKit

/// Finestra trasparente, senza bordi, sempre sopra le altre, visibile su tutti gli Spaces.
/// Mostra il personaggio scelto (Spidy, Bonsy...) e, se ha più stadi, quello attuale.
final class PetWindow: NSWindow {
    private static let margin: CGFloat = 24

    private(set) var pet: Pet
    private let petView: PetView

    init(pet: Pet) {
        self.pet = pet
        let view = PetView(frame: NSRect(origin: .zero, size: pet.size))
        petView = view
        super.init(
            contentRect: NSRect(origin: .zero, size: pet.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true   // si può trascinare dove si vuole
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = view
        view.configure(for: pet)
        view.setStage(pet.restStage, animated: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Appoggia la finestra nell'angolo in basso a destra, sopra il Dock.
    func placeOnGround() {
        guard let screen = NSScreen.main else { return }
        let ground = screen.visibleFrame
        setFrameOrigin(NSPoint(x: ground.maxX - pet.size.width - Self.margin, y: ground.minY))
    }

    /// Cambia personaggio: la finestra si ridimensiona tenendo fermi i piedi (centro del lato basso).
    func apply(_ newPet: Pet) {
        guard newPet != pet else { return }
        let anchor = NSPoint(x: frame.midX, y: frame.minY)
        pet = newPet
        petView.configure(for: newPet)
        petView.setStage(newPet.restStage, animated: false)
        setFrame(
            NSRect(x: anchor.x - newPet.size.width / 2, y: anchor.y, width: newPet.size.width, height: newPet.size.height),
            display: true
        )
    }

    /// Mostra lo stadio di crescita (con una dissolvenza). Per i personaggi fissi non fa nulla.
    func setStage(_ stage: Int) {
        petView.setStage(stage, animated: true)
    }

    /// Cambia posa all'istante (per chi cammina: fermo, passo sinistro, passo destro).
    func setPose(_ pose: Int) {
        petView.setStage(pose, animated: false)
    }

    /// La parte della finestra in cui c'è davvero il disegno (dai piedi alla cima), in coordinate schermo.
    /// Serve a posizionare fumetto e orologio e a capire quando il mouse è "su" il personaggio.
    var artFrame: NSRect {
        let top = petView.artTop
        return NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: max(top, 1))
    }

    var headTopY: CGFloat { artFrame.maxY }
}

private extension NSImage {
    /// Frazione dell'altezza, misurata dall'alto, in cui comincia il disegno visibile.
    var opaqueTopFraction: CGFloat {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0 }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard rep.hasAlpha, let data = rep.bitmapData else { return 0 }
        let spp = rep.samplesPerPixel
        let alphaOffset = rep.bitmapFormat.contains(.alphaFirst) ? 0 : spp - 1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where data[y * rep.bytesPerRow + x * spp + alphaOffset] > 25 {
                return CGFloat(y) / CGFloat(rep.pixelsHigh)
            }
        }
        return 0
    }
}

/// Mostra l'immagine dello stadio attuale appoggiata sul fondo, con una piccola ombra a terra.
final class PetView: NSView {
    private var images: [NSImage] = []
    private var topFractions: [CGFloat] = []
    private var shadowFraction: CGFloat = 0.65
    private var groundFraction: CGFloat = 0

    private var stage = 0
    private var fadingFrom: Int?
    private var fadeStart = Date()
    private var fadeTimer: Timer?
    private static let fadeDuration: TimeInterval = 0.8

    override var mouseDownCanMoveWindow: Bool { true }

    func configure(for pet: Pet) {
        images = pet.imageResources.compactMap { name in
            Bundle.main.url(forResource: name, withExtension: "png").flatMap { NSImage(contentsOf: $0) }
        }
        topFractions = images.map { $0.opaqueTopFraction }
        shadowFraction = pet.shadowWidthFraction
        groundFraction = pet.groundFraction
        fadeTimer?.invalidate()
        fadingFrom = nil
        stage = min(stage, max(images.count - 1, 0))
        needsDisplay = true
    }

    func setStage(_ new: Int, animated: Bool) {
        guard !images.isEmpty else { return }
        let target = min(max(new, 0), images.count - 1)
        guard target != stage else { return }

        if animated {
            fadingFrom = stage
            fadeStart = Date()
            fadeTimer?.invalidate()
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] t in
                guard let self else { t.invalidate(); return }
                if Date().timeIntervalSince(self.fadeStart) >= Self.fadeDuration {
                    self.fadingFrom = nil
                    t.invalidate()
                }
                self.needsDisplay = true
            }
            RunLoop.main.add(timer, forMode: .common)
            fadeTimer = timer
        } else {
            fadingFrom = nil
        }
        stage = target
        needsDisplay = true
    }

    /// Altezza (in coordinate vista, dal basso) a cui arriva il disegno dello stadio attuale.
    var artTop: CGFloat {
        let rect = imageRect
        guard stage < topFractions.count else { return bounds.height }
        return rect.maxY - topFractions[stage] * rect.height
    }

    /// Adatta l'immagine allo spazio mantenendo le proporzioni, appoggiata in basso.
    private var imageRect: NSRect {
        guard let image = images.first else { return bounds }
        let available = NSRect(x: 0, y: 3, width: bounds.width, height: bounds.height - 3)
        let scale = min(available.width / image.size.width, available.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        return NSRect(x: available.midX - size.width / 2, y: available.minY, width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !images.isEmpty else { return }

        let target = imageRect

        // Ombra centrata sulla linea di terra del disegno.
        let shadowWidth = bounds.width * shadowFraction
        let groundY = target.minY + groundFraction * target.height
        NSColor.black.withAlphaComponent(0.16).setFill()
        NSBezierPath(ovalIn: NSRect(x: bounds.midX - shadowWidth / 2, y: groundY - 3.5, width: shadowWidth, height: 7)).fill()

        if let from = fadingFrom, from < images.count {
            let t = min(1, Date().timeIntervalSince(fadeStart) / Self.fadeDuration)
            images[from].draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
            images[stage].draw(in: target, from: .zero, operation: .sourceOver, fraction: CGFloat(t))
        } else {
            images[stage].draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }
}
