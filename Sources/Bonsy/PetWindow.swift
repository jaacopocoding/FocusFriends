import AppKit

/// Finestra trasparente, senza bordi, sempre sopra le altre, visibile su tutti gli Spaces.
/// Mostra il personaggio scelto (Spidy, Bonsy...) e, se ha più stadi, quello attuale.
final class PetWindow: NSWindow {
    private static let margin: CGFloat = 24

    private(set) var pet: Pet
    private let petView: PetView
    /// Sta venendo sollevato col mouse (solo per i personaggi con un disegno "sollevato").
    private(set) var isPicked = false
    private var restSize = NSSize.zero
    /// Cosa sta facendo in relazione al timer (lo imposta Pomodoro, lo anima Walker).
    var activity: PetActivity = .none

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
        // Si può trascinare dove si vuole. Chi ha il disegno "sollevato" gestisce il trascinamento da sé,
        // perché la finestra cambia dimensione mentre la si sposta.
        isMovableByWindowBackground = pet.pickedResource == nil
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = view
        view.configure(for: pet)
        view.setStage(pet.restStage, animated: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Appoggia i piedi del personaggio sopra il Dock, nell'angolo in basso a destra.
    /// (Sotto i piedi la finestra può avere dello spazio vuoto, ad esempio per le foglie di una carota.)
    func placeOnGround() {
        guard let screen = NSScreen.main else { return }
        let ground = screen.visibleFrame
        setFrameOrigin(NSPoint(x: ground.maxX - pet.size.width - Self.margin, y: ground.minY - petView.feetHeight))
    }

    /// Altezza dei piedi del personaggio, in coordinate schermo.
    var feetY: CGFloat { frame.minY + petView.feetHeight }

    /// Cambia personaggio: la finestra si ridimensiona tenendo fermi i piedi (centro del lato basso).
    func apply(_ newPet: Pet) {
        guard newPet != pet else { return }
        endPick()
        isMovableByWindowBackground = newPet.pickedResource == nil
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

    // MARK: - Sollevamento col mouse

    /// Comincia a sollevarlo: mostra il disegno "sollevato" e ridimensiona la finestra.
    func beginPick() {
        guard !isPicked, pet.pickedResource != nil else { return }
        isPicked = true
        restSize = frame.size
        petView.setPicked(true)
        movePicked()
    }

    /// Tiene il cursore sul punto di presa del disegno.
    func movePicked() {
        guard isPicked else { return }
        let mouse = NSEvent.mouseLocation
        let size = pet.pickedSize
        let origin = NSPoint(x: mouse.x - pet.pickedGrab.x * size.width, y: mouse.y - pet.pickedGrab.y * size.height)
        setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// Lo rimette giù: dimensione normale, con i piedi (centro del lato basso) dove si trova.
    func endPick() {
        guard isPicked else { return }
        isPicked = false
        petView.setPicked(false)
        let anchor = NSPoint(x: frame.midX, y: frame.minY)
        setFrame(
            NSRect(x: anchor.x - restSize.width / 2, y: anchor.y, width: restSize.width, height: restSize.height),
            display: true
        )
    }

    /// Mostra gli "Zzz" sopra la testa (quando dorme).
    func setSleepMarks(_ on: Bool) {
        petView.showsSleepMarks = on
    }

    /// Per chi ha le immagini rivolte a destra: specchia l'immagine quando va a sinistra.
    func setFacing(right: Bool) {
        petView.mirrored = !right && pet.facesRight
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

    /// Gli "Zzz" che salgono sopra la testa mentre dorme.
    var showsSleepMarks = false {
        didSet {
            guard showsSleepMarks != oldValue else { return }
            sleepTimer?.invalidate()
            sleepTimer = nil
            if showsSleepMarks {
                sleepStart = Date()
                let timer = Timer(timeInterval: 1.0 / 15, repeats: true) { [weak self] _ in self?.needsDisplay = true }
                RunLoop.main.add(timer, forMode: .common)
                sleepTimer = timer
            }
            needsDisplay = true
        }
    }
    private var sleepTimer: Timer?
    private var sleepStart = Date()

    /// Disegna l'immagine specchiata in orizzontale (il personaggio va verso sinistra).
    var mirrored = false {
        didSet { if mirrored != oldValue { needsDisplay = true } }
    }

    private var stage = 0
    private var fadingFrom: Int?
    private var fadeStart = Date()
    private var fadeTimer: Timer?
    private static let fadeDuration: TimeInterval = 0.8

    // Sollevamento col mouse
    private var pickedImage: NSImage?
    private var pickedGrab = CGPoint(x: 0.5, y: 0.5)
    private var isPickedUp = false
    private var dragStart: NSPoint?
    private var wobbleTimer: Timer?
    private var wobbleStart = Date()

    private var hasPickedPose: Bool { pickedImage != nil }

    /// Chi ha il disegno "sollevato" gestisce il trascinamento da sé (vedi mouseDragged).
    override var mouseDownCanMoveWindow: Bool { !hasPickedPose }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard hasPickedPose else { super.mouseDown(with: event); return }
        dragStart = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard hasPickedPose, let petWindow = window as? PetWindow, let start = dragStart else {
            super.mouseDragged(with: event)
            return
        }
        let mouse = NSEvent.mouseLocation
        if !petWindow.isPicked {
            // Un semplice click non è un sollevamento: serve un piccolo spostamento.
            guard hypot(mouse.x - start.x, mouse.y - start.y) > 3 else { return }
            petWindow.beginPick()
        }
        petWindow.movePicked()
    }

    override func mouseUp(with event: NSEvent) {
        guard hasPickedPose else { super.mouseUp(with: event); return }
        dragStart = nil
        (window as? PetWindow)?.endPick()
    }

    /// Mostra o toglie il disegno "sollevato", che trema leggermente finché è in aria.
    func setPicked(_ picked: Bool) {
        guard picked != isPickedUp else { return }
        isPickedUp = picked
        wobbleTimer?.invalidate()
        wobbleTimer = nil
        if picked {
            wobbleStart = Date()
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.needsDisplay = true }
            RunLoop.main.add(timer, forMode: .common)
            wobbleTimer = timer
        }
        needsDisplay = true
    }

    func configure(for pet: Pet) {
        images = pet.imageResources.compactMap { name in
            Bundle.main.url(forResource: name, withExtension: "png").flatMap { NSImage(contentsOf: $0) }
        }
        topFractions = images.map { $0.opaqueTopFraction }
        mirrored = false
        pickedImage = pet.pickedResource.flatMap { name in
            Bundle.main.url(forResource: name, withExtension: "png").flatMap { NSImage(contentsOf: $0) }
        }
        pickedGrab = pet.pickedGrab
        setPicked(false)
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

    /// Altezza dei piedi (la linea di terra del disegno) dal bordo basso della vista.
    var feetHeight: CGFloat {
        let rect = imageRect
        return rect.minY + groundFraction * rect.height
    }

    /// Altezza (in coordinate vista, dal basso) a cui arriva il disegno dello stadio attuale.
    var artTop: CGFloat {
        if isPickedUp { return bounds.height }
        let rect = imageRect
        guard stage < topFractions.count else { return bounds.height }
        return rect.maxY - topFractions[stage] * rect.height
    }

    /// Il disegno "sollevato", con un leggero tremolio attorno al punto in cui lo tiene il cursore.
    private func drawPicked(_ image: NSImage) {
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let target = NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)

        let t = Date().timeIntervalSince(wobbleStart)
        let angle = sin(t * 2 * .pi * 5) * 2.5   // gradi, 5 oscillazioni al secondo
        let pivot = NSPoint(x: bounds.width * pickedGrab.x, y: bounds.height * pickedGrab.y)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let rotate = NSAffineTransform()
        rotate.translateX(by: pivot.x, yBy: pivot.y)
        rotate.rotate(byDegrees: CGFloat(angle))
        rotate.translateX(by: -pivot.x, yBy: -pivot.y)
        rotate.concat()
        image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
    }

    /// Adatta l'immagine allo spazio mantenendo le proporzioni, appoggiata in basso.
    private var imageRect: NSRect {
        guard let image = images.first else { return bounds }
        let available = NSRect(x: 0, y: 3, width: bounds.width, height: bounds.height - 3)
        let scale = min(available.width / image.size.width, available.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        return NSRect(x: available.midX - size.width / 2, y: available.minY, width: size.width, height: size.height)
    }

    /// Tre lettere "z" che salgono una dopo l'altra sopra la testa e svaniscono.
    private func drawSleepMarks() {
        let t = Date().timeIntervalSince(sleepStart)
        let headX = bounds.width * (mirrored ? 0.2 : 0.8)       // la testa sta a destra (a sinistra se specchiato)
        let baseY = artTop + 2
        let letters: [(text: String, size: CGFloat, dx: CGFloat)] = [("z", 9, 0), ("Z", 12, 7), ("z", 9, 14)]
        let direction: CGFloat = mirrored ? -1 : 1

        for (i, letter) in letters.enumerated() {
            let phase = (t - Double(i) * 0.7).truncatingRemainder(dividingBy: 2.8)
            guard phase >= 0 else { continue }
            let p = CGFloat(phase / 2.8)                          // 0...1
            let alpha = sin(p * .pi)                              // compare, resta, svanisce
            let font = NSFont(name: "MarkerFelt-Wide", size: letter.size) ?? NSFont.systemFont(ofSize: letter.size, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor(calibratedRed: 0.36, green: 0.30, blue: 0.24, alpha: alpha),
            ]
            let point = NSPoint(x: headX + direction * letter.dx, y: baseY + p * 14)
            (letter.text as NSString).draw(at: point, withAttributes: attrs)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if showsSleepMarks { drawSleepMarks() }
        if isPickedUp, let pickedImage {
            drawPicked(pickedImage)
            return
        }
        guard !images.isEmpty else { return }

        // Specchio: tutto il disegno viene ribaltato attorno al centro della vista.
        if mirrored {
            NSGraphicsContext.saveGraphicsState()
            let flip = NSAffineTransform()
            flip.translateX(by: bounds.width, yBy: 0)
            flip.scaleX(by: -1, yBy: 1)
            flip.concat()
        }
        defer { if mirrored { NSGraphicsContext.restoreGraphicsState() } }

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
