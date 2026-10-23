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

    /// Una frase «di contesto» (il saluto dell'avvio, il riepilogo della settimana) da dire alla prossima occasione, prima delle frasi a caso.
    struct Occasion {
        var text: String
        /// Dice già le scadenze: il promemoria delle scadenze non va ripetuto subito dopo.
        var coversReminder = false
        /// Chiamata quando la frase è stata detta (per ricordarlo).
        var onSaid: (() -> Void)?
    }
    private var queued: [Occasion] = []

    /// Mette una frase in coda: la dice al prossimo momento in cui il compagno parla di sua iniziativa (mai, se le frasi sono su «Mai»).
    func enqueue(_ occasion: Occasion) {
        queued.append(occasion)
    }

    /// Un numero detto a voce (le frasi «quando rendi meglio»), ogni tanto al posto di una frase a caso.
    var insight: (() -> String?)?

    /// Un promemoria da dire al posto di una frase a caso (le scadenze di oggi e domani); nil = niente da ricordare ora.
    var reminder: (() -> String?)?
    /// Ogni quanto, al massimo, un promemoria prende il posto di una frase a caso.
    private static let reminderEvery: TimeInterval = 3 * 3600
    private var lastReminder = Date.distantPast

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
        if !queued.isEmpty {
            let occasion = queued.removeFirst()
            if occasion.coversReminder { markReminderSaid() }
            occasion.onSaid?()
            say(occasion.text)
            return
        }
        if Date().timeIntervalSince(lastReminder) >= Self.reminderEvery, let text = reminder?() {
            lastReminder = Date()
            say(text)
            return
        }
        // Ogni tanto (una volta su sei) un numero dello studio, se ce n'è uno da dire.
        if Int.random(in: 0..<6) == 0, let text = insight?() {
            say(text)
            return
        }
        // Rilegge il file a ogni frase: le modifiche si vedono subito, senza riavviare.
        let quotes = Quotes.load(for: petWindow.pet)
        say(deck.draw(from: quotes) ?? petWindow.pet.fallbackQuote)
    }

    /// Il promemoria delle scadenze è già stato detto adesso: il prossimo non prima di qualche ora.
    func markReminderSaid() {
        lastReminder = Date()
    }

    /// Dice la frase dopo `delay` secondi, ma solo se `unless` non dice di no (per esempio è partito un altro focus) e, se in quel momento
    /// il compagno sta già parlando, aspetta che finisca (qualche secondo alla volta, fino a quattro volte).
    func sayWhenQuiet(_ text: String, after delay: TimeInterval, while stillWanted: @escaping () -> Bool = { true }, tries: Int = 4) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, stillWanted() else { return }
            if self.isSpeaking, tries > 0 {
                self.sayWhenQuiet(text, after: 3, while: stillWanted, tries: tries - 1)
            } else {
                self.say(text)
            }
        }
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
        let placement = bubblePlacement(dt: nil)
        tailOnRight = placement.tailOnRight
        window.bubbleView.tailOnRight = placement.tailOnRight
        window.setFrame(NSRect(origin: placement.origin, size: size), display: true)
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
    /// Quello che il fumetto non deve coprire (la scheda «Com'è andata?»): chi lo mostra lo dice.
    var obstacles: () -> [NSRect] = { [] }
    /// Da che parte sta la codina adesso (si specchia vicino ai bordi dello schermo).
    private var tailOnRight = true
    /// Quanto sta sopra il bordo basso della finestra del personaggio (smussato): così se si sposta la finestra
    /// il fumetto la segue senza ritardi, e conta solo il cambio di altezza del disegno.
    private var heightAbovePet: CGFloat?
    private var followTimer: Timer?
    private var lastFollow = Date()

    /// Dove mettere il fumetto: sopra tutto ciò che si vede del personaggio (anche l'immagine che sta svanendo,
    /// o le ali alzate), con la punta della codina sulla sua testa; vicino ai bordi dello schermo si specchia, di fianco
    /// se sopra non c'è posto, e mai sopra la scheda «Com'è andata?» (la regola è in BubblePlacement).
    private func bubblePlacement(dt: TimeInterval?) -> BubblePlacement.Result {
        let anchor = petWindow.frame
        let screen = (petWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero

        let wanted = petWindow.visibleTopY - BubblePlacement.overlap - anchor.minY
        var height = wanted
        if let previous = heightAbovePet, let dt, wanted < previous {
            // Scende senza rimbalzare (il passo fa ballare il disegno di qualche punto), ma una differenza grande (un disegno molto
            // più basso) si richiude in fretta.
            let speed = max(Self.descendSpeed, (previous - wanted) * 3)
            height = max(wanted, previous - speed * CGFloat(dt))
        }
        heightAbovePet = height
        return BubblePlacement.place(bubble: bubbleSize, anchorX: anchor.midX, topY: anchor.minY + height + BubblePlacement.overlap,
                                     pet: anchor, screen: screen, obstacles: obstacles(), previousTailOnRight: dt == nil ? nil : tailOnRight)
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
        let placement = bubblePlacement(dt: dt)
        if placement.tailOnRight != tailOnRight {
            tailOnRight = placement.tailOnRight
            window.bubbleView.tailOnRight = placement.tailOnRight
        }
        let origin = placement.origin
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
