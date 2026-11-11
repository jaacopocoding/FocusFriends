import AppKit

/// Il giro guidato della prima apertura (dopo la scheda del nome e del compagno, o da «Fai il giro» nel menu).
/// Il compagno freme e dice «Cliccami!!!»; un clic su di lui apre la scheda, che si scurisce tranne una parte alla volta,
/// e un fumetto accanto spiega quella parte (per il giardino, le statistiche e l'album, con l'immagine di com'è fatto).
/// Finché il giro va, la scheda non si chiude con un clic fuori e non risponde ai clic. «Salta» o Esc lo chiudono.
final class GuidedTour {
    struct Step {
        var section: CardSection
        var text: String
        /// L'immagine di com'è fatto (le risorse `benvenuto_*.png`), se c'è.
        var image: String?
    }

    static let callText = "Cliccami!!!"
    static let steps: [Step] = [
        Step(section: .durations, text: "Qui scegli la durata del focus. Il timer parte appena tocchi i minuti."),
        Step(section: .today, text: "Il tempo di studio di oggi, i focus fatti e i giorni di fila."),
        Step(section: .garden, text: "Il giardino: un'isola per ogni compagno da decorare come preferisci. Più studi, più decori!", image: "benvenuto_giardino"),
        Step(section: .stats, text: "Le statistiche: guarda quanto studi ogni giorno e per materia.", image: "benvenuto_statistiche"),
        Step(section: .album, text: "L'album raccoglie le figurine che trovi studiando. La barra indica quanto manca alla prossima.", image: "benvenuto_album"),
        Step(section: .avatars, text: "I compagni da sbloccare. La barra indica quanto manca al prossimo."),
        Step(section: .settings, text: "Qui sotto: da fare, suoni, musica e altre impostazioni."),
        Step(section: .durations, text: "Fine del giro. Scegli la durata e inizia il primo focus."),
    ]
    static let finishedText = "Buono studio."
    static let skippedText = "Il giro si può rivedere dal menu."

    private let card: MenuCard
    private let petWindow: PetWindow
    private let speaker: Speaker
    private var step = -1
    private var tip: NSPanel?
    private var peek: NSPanel?
    private(set) var isRunning = false

    init(card: MenuCard, petWindow: PetWindow, speaker: Speaker) {
        self.card = card
        self.petWindow = petWindow
        self.speaker = speaker
    }

    /// Il compagno comincia a chiamare. Anche aprire la scheda in un altro modo (dall'icona in alto) fa partire il giro.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        step = -1
        card.close()
        speaker.stop()
        speaker.hold(Self.callText)
        petWindow.onCallClick = { [weak self] in self?.openCard() }
        card.onShow = { [weak self] in self?.openCard() }
    }

    private func openCard() {
        guard isRunning, step < 0 else { return }
        petWindow.onCallClick = nil
        card.onShow = nil
        speaker.dismissNow()
        if !card.isShowing { card.show(anchor: .beside(petWindow)) }
        card.isPinned = true
        card.onClose = { [weak self] in self?.finish(started: false, cardClosed: true) }
        step = 0
        // la scheda appare in un attimo: il primo passo appena è al suo posto
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.isRunning else { return }
            self.show(step: 0)
        }
    }

    private func show(step index: Int) {
        guard isRunning, index < Self.steps.count, let cardFrame = card.frame, let target = card.screenRect(of: Self.steps[index].section) else {
            finish(started: false, cardClosed: false)
            return
        }
        step = index
        let item = Self.steps[index]
        let isLast = index == Self.steps.count - 1
        card.setSpotlight(item.section, active: true)

        // Il fumetto sta dal lato della scheda lontano dal compagno (se non c'è posto, dall'altro).
        let screen = (NSScreen.screens.first { $0.frame.intersects(cardFrame) } ?? NSScreen.main)?.visibleFrame ?? cardFrame
        let view = TourTipView(text: item.text, count: isLast ? nil : "\(index + 1) di \(Self.steps.count)",
                               next: isLast ? "Inizia il primo focus" : "Avanti")
        view.onNext = { [weak self] in
            guard let self else { return }
            if isLast { self.finish(started: true, cardClosed: false) } else { self.show(step: index + 1) }
        }
        view.onSkip = { [weak self] in self?.finish(started: false, cardClosed: false) }
        let size = view.fittingSize
        let petOnRight = petWindow.frame.midX > cardFrame.midX
        var onLeft = petOnRight
        if onLeft, cardFrame.minX - size.width - 8 < screen.minX { onLeft = false }
        if !onLeft, cardFrame.maxX + size.width + 8 > screen.maxX { onLeft = true }
        let x = onLeft ? cardFrame.minX - size.width - 4 : cardFrame.maxX + 4
        let top = min(max(target.midY + 30, screen.minY + size.height + 8), screen.maxY - 8)
        view.tailOnRight = onLeft
        view.tailY = min(max(top - target.midY, 22), size.height - 22)
        let tipFrame = NSRect(x: x, y: top - size.height, width: size.width, height: size.height)

        let panel = tip ?? Self.makePanel()
        panel.contentView = view
        panel.setFrame(tipFrame, display: true)
        if tip == nil {
            tip = panel
            panel.alphaValue = 0
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        }

        // L'immagine di com'è fatto, sopra il fumetto (o sotto, se sopra non c'è posto).
        peek?.orderOut(nil)
        peek = nil
        if let name = item.image, let image = Bundle.main.url(forResource: name, withExtension: "png").flatMap({ NSImage(contentsOf: $0) }) {
            // larga quanto c'è posto da quel lato, così non copre mai la scheda
            let room = onLeft ? tipFrame.maxX - 10 - (screen.minX + 8) : screen.maxX - 8 - (tipFrame.minX + 10)
            let width = min(item.section == .stats ? 300 : 420, max(room, 220))
            let size = NSSize(width: width, height: (width * image.size.height / image.size.width).rounded())
            var origin = NSPoint(x: onLeft ? tipFrame.maxX - size.width - 10 : tipFrame.minX + 10, y: tipFrame.maxY + 12)
            if origin.y + size.height > screen.maxY - 8 { origin.y = tipFrame.minY - 12 - size.height }
            origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
            origin.y = max(origin.y, screen.minY + 8)
            let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
            imageView.image = image
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.wantsLayer = true
            imageView.layer?.cornerRadius = 14
            imageView.layer?.masksToBounds = true
            let panel = Self.makePanel()
            panel.hasShadow = true
            panel.contentView = imageView
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
            panel.alphaValue = 0
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 1 }
            peek = panel
        }
    }

    /// Fine del giro: dall'ultimo passo (`started`), da «Salta», o perché la scheda si è chiusa (Esc).
    private func finish(started: Bool, cardClosed: Bool) {
        guard isRunning else { return }
        isRunning = false
        step = -1
        petWindow.onCallClick = nil
        card.onShow = nil
        card.onClose = nil
        tip?.orderOut(nil)
        tip = nil
        peek?.orderOut(nil)
        peek = nil
        card.setSpotlight(nil, active: false)
        card.isPinned = false
        if started {
            card.makeKey()
            speaker.say(Self.finishedText)
        } else {
            if !cardClosed { card.close() }
            speaker.say(Self.skippedText)
        }
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }
}

/// Il fumetto del giro: il testo, e sotto «Salta», a che passo si è e «Avanti». La punta indica la parte illuminata della scheda.
private final class TourTipView: NSView {
    override var isFlipped: Bool { true }
    var onNext: (() -> Void)?
    var onSkip: (() -> Void)?
    /// Da che lato esce la punta, e a che altezza (dall'alto).
    var tailOnRight = true { didSet { updateInsets() } }
    var tailY: CGFloat = 30 { didSet { needsDisplay = true } }

    private static let bodyWidth: CGFloat = 300
    private static let tail: CGFloat = 10
    private let stack: NSStackView
    private var leading: NSLayoutConstraint?

    init(text: String, count: String?, next: String) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: 14)
        label.textColor = Paper.ink
        label.preferredMaxLayoutWidth = Self.bodyWidth - 30
        let skip = TextButton(title: "Salta")
        let counter = NSTextField(labelWithString: count ?? "")
        counter.font = NSFont.systemFont(ofSize: 11.5)
        counter.textColor = Paper.inkLight
        counter.alignment = .center
        let nextWidth = ceil((next as NSString).size(withAttributes: [.font: Paper.markerFont(17)]).width) + 36
        let go = PillButton(title: next, width: nextWidth, height: 34)
        let row = NSStackView(views: [skip, counter, go])
        row.orientation = .horizontal
        row.distribution = .equalSpacing
        row.alignment = .centerY
        stack = NSStackView(views: [label, row])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        super.init(frame: .zero)
        addSubview(stack)
        row.widthAnchor.constraint(equalToConstant: Self.bodyWidth - 30).isActive = true
        label.widthAnchor.constraint(equalToConstant: Self.bodyWidth - 30).isActive = true
        stack.topAnchor.constraint(equalTo: topAnchor, constant: 13).isActive = true
        stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12).isActive = true
        widthAnchor.constraint(equalToConstant: Self.bodyWidth + Self.tail).isActive = true
        updateInsets()
        skip.target = self
        skip.action = #selector(skipPressed)
        go.target = self
        go.action = #selector(nextPressed)
        go.keyEquivalent = "\r"
    }

    required init?(coder: NSCoder) { nil }

    private func updateInsets() {
        leading?.isActive = false
        leading = stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15 + (tailOnRight ? 0 : Self.tail))
        leading?.isActive = true
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let body = NSRect(x: tailOnRight ? 1 : Self.tail + 1, y: 1, width: Self.bodyWidth - 2, height: bounds.height - 2)
        let shape = NSBezierPath(roundedRect: body, xRadius: 16, yRadius: 16)
        let y = min(max(tailY, 22), bounds.height - 22)
        let tail = NSBezierPath()
        if tailOnRight {
            tail.move(to: NSPoint(x: body.maxX - 1, y: y - 8))
            tail.line(to: NSPoint(x: body.maxX + Self.tail - 1, y: y))
            tail.line(to: NSPoint(x: body.maxX - 1, y: y + 8))
        } else {
            tail.move(to: NSPoint(x: body.minX + 1, y: y - 8))
            tail.line(to: NSPoint(x: body.minX - Self.tail + 1, y: y))
            tail.line(to: NSPoint(x: body.minX + 1, y: y + 8))
        }
        let fill = NSColor(calibratedRed: 1, green: 0.99, blue: 0.97, alpha: 1)
        fill.setFill()
        shape.fill()
        Paper.ink.setStroke()
        shape.lineWidth = 2
        shape.stroke()
        // la punta: riempita sopra il bordo, poi i suoi due lati
        tail.close()
        tail.fill()
        let sides = NSBezierPath()
        sides.move(to: NSPoint(x: tailOnRight ? body.maxX - 1 : body.minX + 1, y: y - 8))
        sides.line(to: NSPoint(x: tailOnRight ? body.maxX + Self.tail - 1 : body.minX - Self.tail + 1, y: y))
        sides.line(to: NSPoint(x: tailOnRight ? body.maxX - 1 : body.minX + 1, y: y + 8))
        sides.lineWidth = 2
        sides.lineJoinStyle = .round
        sides.stroke()
    }

    @objc private func nextPressed() { onNext?() }
    @objc private func skipPressed() { onSkip?() }
}
