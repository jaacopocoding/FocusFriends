import AppKit

/// Fa comparire ogni tanto un fumetto con una frase sopra la testa del personaggio.
final class Speaker {
    private let petWindow: PetWindow
    private var bubble: BubbleWindow?
    private var nextTimer: Timer?
    private var hideTimer: Timer?
    /// Le frasi escono a mazzo: tutte, in ordine casuale, prima che una si ripeta.
    private var deck = PhraseDeck()

    /// C'è un fumetto sullo schermo in questo momento.
    var isSpeaking: Bool { bubble != nil }

    /// Pausa (in secondi) tra una frase spontanea e la successiva; nil = non parla di sua iniziativa.
    var interval: ClosedRange<TimeInterval>? = Chattiness.current.interval(whileFocusing: false)

    init(petWindow: PetWindow) {
        self.petWindow = petWindow
        // Quando cambia il disegno (cresce, o torna il seme) il fumetto si adegua subito, senza aspettare il prossimo tick.
        petWindow.onArtChanged = { [weak self] in self?.followNow() }
    }

    /// Prima frase dopo qualche secondo, poi a intervalli casuali (salvo "Mai").
    func start() {
        if interval != nil { scheduleNext(after: 5) }
    }

    /// Dopo un cambio di frequenza: riparte il conto con il nuovo intervallo, oppure tace.
    /// Se c'è un fumetto sullo schermo ci pensa lui a riprogrammare quando sparisce.
    func reschedule() {
        nextTimer?.invalidate()
        nextTimer = nil
        guard let range = interval, bubble == nil else { return }
        scheduleNext(after: .random(in: range))
    }

    /// Toglie subito il fumetto (per "Mai": il silenzio parte subito).
    func dismissNow() {
        hideTimer?.invalidate()
        hideTimer = nil
        dismissBubble(animated: true)
    }

    func stop() {
        nextTimer?.invalidate()
        hideTimer?.invalidate()
        dismissBubble(animated: false)
    }

    /// Dice la prossima frase del mazzo.
    func sayRandom() {
        // Rilegge il file a ogni frase: le modifiche si vedono subito, senza riavviare.
        let quotes = Quotes.load(for: petWindow.pet)
        say(deck.draw(from: quotes) ?? petWindow.pet.fallbackQuote)
    }

    func say(_ text: String) {
        nextTimer?.invalidate()
        hideTimer?.invalidate()
        dismissBubble(animated: false)

        let window = BubbleWindow()
        let size = BubbleView.size(for: text)
        bubbleSize = size
        heightAbovePet = nil
        lastFollow = Date()

        window.bubbleView.text = text
        window.setFrame(NSRect(origin: bubbleOrigin(dt: nil), size: size), display: true)
        window.alphaValue = 0

        // Figlia della finestra del personaggio: se lo trascini, il fumetto lo segue.
        petWindow.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            window.animator().alphaValue = 1
        }
        bubble = window
        startFollowing()

        let visibleFor = max(4.5, 2.5 + Double(text.count) * 0.06)
        hideTimer = Timer.scheduledTimer(withTimeInterval: visibleFor, repeats: false) { [weak self] _ in
            self?.dismissBubble(animated: true)
            if let self, let range = self.interval { self.scheduleNext(after: .random(in: range)) }
        }
    }

    private func scheduleNext(after delay: TimeInterval) {
        nextTimer?.invalidate()
        nextTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.sayRandom()
        }
    }

    // MARK: - Posizione del fumetto

    /// Quanto sale il fumetto al massimo ogni secondo di discesa: sale subito, scende piano (se il personaggio
    /// si abbassa, o se un salto finisce, il fumetto non rimbalza).
    private static let descendSpeed: CGFloat = 140

    private var bubbleSize = NSSize.zero
    /// Quanto sta sopra il bordo basso della finestra del personaggio (smussato): così se si sposta la finestra
    /// il fumetto la segue senza ritardi, e conta solo il cambio di altezza del disegno.
    private var heightAbovePet: CGFloat?
    private var followTimer: Timer?
    private var lastFollow = Date()

    /// Dove mettere il fumetto: sopra tutto ciò che si vede del personaggio (anche l'immagine che sta svanendo,
    /// o le ali alzate), con la punta della codina sulla sua testa. Se sopra non c'è posto (il personaggio è
    /// in alto sullo schermo) sta di fianco, mai sopra il disegno.
    private func bubbleOrigin(dt: TimeInterval?) -> NSPoint {
        let anchor = petWindow.frame
        let screen = (petWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let size = bubbleSize

        let wanted = petWindow.visibleTopY - 6 - anchor.minY
        var height = wanted
        if let previous = heightAbovePet, let dt, wanted < previous {
            height = max(wanted, previous - Self.descendSpeed * CGFloat(dt))
        }
        heightAbovePet = height

        var x = anchor.midX - size.width * BubbleView.tailTipFraction
        x = min(max(x, screen.minX + 6), screen.maxX - size.width - 6)
        let y = anchor.minY + height
        if y + size.height <= screen.maxY - 4 {
            return NSPoint(x: x, y: y)
        }
        // Di fianco, dal lato con più spazio, all'altezza più alta che lo schermo permette.
        let onLeft = anchor.midX > screen.midX
        var sideX = onLeft ? anchor.minX - size.width - 2 : anchor.maxX + 2
        sideX = min(max(sideX, screen.minX + 6), screen.maxX - size.width - 6)
        return NSPoint(x: sideX, y: max(screen.maxY - size.height - 4, screen.minY))
    }

    private func startFollowing() {
        followTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.followNow() }
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
    }

    private func followNow() {
        guard let window = bubble else { return }
        let now = Date()
        let dt = min(now.timeIntervalSince(lastFollow), 0.1)
        lastFollow = now
        let origin = bubbleOrigin(dt: dt)
        if abs(origin.x - window.frame.minX) > 0.25 || abs(origin.y - window.frame.minY) > 0.25 {
            window.setFrameOrigin(origin)
        }
    }

    private func dismissBubble(animated: Bool) {
        followTimer?.invalidate()
        followTimer = nil
        guard let window = bubble else { return }
        bubble = nil
        let remove = { [petWindow] in
            petWindow.removeChildWindow(window)
            window.orderOut(nil)
        }
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                window.animator().alphaValue = 0
            }, completionHandler: remove)
        } else {
            remove()
        }
    }
}
