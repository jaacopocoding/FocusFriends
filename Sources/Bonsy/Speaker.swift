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
        let anchor = petWindow.frame
        let screen = (petWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero

        // Fumetto sopra la testa: la punta della codina (fissa nell'immagine) va sopra il personaggio.
        var x = anchor.midX - size.width * BubbleView.tailTipFraction
        x = min(max(x, screen.minX + 6), screen.maxX - size.width - 6)
        var y = petWindow.headTopY - 6
        y = min(y, screen.maxY - size.height - 4)

        window.bubbleView.text = text
        window.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
        window.alphaValue = 0

        // Figlia della finestra del personaggio: se lo trascini, il fumetto lo segue.
        petWindow.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            window.animator().alphaValue = 1
        }
        bubble = window

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

    private func dismissBubble(animated: Bool) {
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
