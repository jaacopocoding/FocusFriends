import AppKit

/// Timer pomodoro: una fase di focus, poi una pausa. Il conto alla rovescia sta sotto il personaggio.
final class Pomodoro {
    enum Phase {
        case focus
        case rest

        var label: String { self == .focus ? "FOCUS" : "PAUSA" }
    }

    /// Secondi in un "minuto" del timer (60, salvo nei test).
    private static let secondsPerMinute: TimeInterval = 60

    /// Per quanto l'orologio resta visibile dall'inizio di ogni fase.
    private static let introMinutes: TimeInterval = 2
    /// Quando mancano meno di tanti minuti l'orologio resta sempre visibile.
    private static let alwaysVisibleMinutes: TimeInterval = 5
    /// Quanto resta visibile dopo che il mouse esce dal personaggio.
    private static let hoverLinger: TimeInterval = 1
    private static let curtainDuration: TimeInterval = 0.35


    private let petWindow: PetWindow
    private let speaker: Speaker
    private var window: TimerWindow?
    private var ticker: Timer?
    private var curtainTimer: Timer?
    private var phaseStart = Date()
    private var endDate = Date()
    private var isShown = false
    private var hoverUntil = Date.distantPast
    /// Quanto ho dovuto alzare il personaggio per fare spazio al timer sotto di lui.
    private var shiftedUp: CGFloat = 0

    private(set) var phase: Phase?
    private(set) var breakMinutes = 5
    /// La materia del focus in corso (nil = nessuna, o non è un focus).
    private(set) var subject: String?
    private var plannedFocusMinutes = 0
    private let log: SessionLog

    init(petWindow: PetWindow, speaker: Speaker, log: SessionLog = .shared) {
        self.petWindow = petWindow
        self.speaker = speaker
        self.log = log
        // Quando il personaggio viene sollevato o rimesso giù, l'orologio si risistema sotto di lui.
        petWindow.onPickStateChanged = { [weak self] in self?.snapClockToPet() }
    }

    /// Rimette l'orologio (se è visibile) nella posizione piena, sotto il personaggio, senza animazioni.
    private func snapClockToPet() {
        guard let window, isShown else { return }
        window.setFrame(fullFrame(), display: true)
    }

    var isRunning: Bool { phase != nil }

    /// Tempo rimasto come "MM:SS", arrotondato per eccesso: parte da 30:00 e finisce a 00:01.
    var remainingText: String {
        let seconds = Int(ceil(max(0, endDate.timeIntervalSinceNow)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Comandi

    func startFocus(minutes: Int, subject: String? = nil) {
        recordFocus(completed: false)     // se ce n'era uno in corso, finisce qui
        self.subject = Subject.clean(subject)
        plannedFocusMinutes = minutes
        begin(.focus, minutes: minutes)
        log.beginInProgress(start: phaseStart, plannedMinutes: minutes, subject: self.subject)
        if let subject = self.subject {
            speaker.say("Focus di \(minutes) minuti su \(subject): si parte!")
        } else {
            speaker.say("Focus di \(minutes) minuti: si parte!")
        }
    }

    /// Avvia subito una pausa e ricorda la durata per quelle automatiche dopo il focus.
    func startBreak(minutes: Int) {
        recordFocus(completed: false)
        subject = nil
        breakMinutes = minutes
        begin(.rest, minutes: minutes)
        speaker.say("Pausa di \(minutes) minuti: stacca un attimo.")
    }

    /// Se un focus è in corso lo mette nel registro (completo o interrotto) e toglie il segno "in corso".
    /// Ritorna la sessione salvata, se era lunga abbastanza da contare.
    @discardableResult
    private func recordFocus(completed: Bool) -> StudySession? {
        guard phase == .focus else { return nil }
        let planned = plannedFocusMinutes
        let elapsed = completed
            ? Int(endDate.timeIntervalSince(phaseStart))
            : min(Int(Date().timeIntervalSince(phaseStart)), planned * Int(Self.secondsPerMinute))
        let session = log.add(start: phaseStart, seconds: elapsed, plannedMinutes: planned, completed: completed, subject: subject)
        log.finishInProgress()
        return session
    }

    /// Per la chiusura dell'app: un focus ancora in corso viene salvato come interrotto.
    func recordInterruptedFocusOnQuit() {
        recordFocus(completed: false)
    }

    func stop() {
        recordFocus(completed: false)
        subject = nil
        ticker?.invalidate()
        ticker = nil
        curtainTimer?.invalidate()
        curtainTimer = nil
        phase = nil
        refreshChatter()
        updateStage()   // senza timer il personaggio sta allo stadio finale

        if let window {
            petWindow.removeChildWindow(window)
            window.orderOut(nil)
        }
        window = nil
        isShown = false
        restorePetHeight()
    }

    /// Allinea la frequenza delle frasi alla scelta dell'utente e alla fase (durante un focus parla meno).
    func refreshChatter() {
        speaker.interval = Chattiness.current.interval(whileFocusing: phase == .focus)
    }

    // MARK: - Andamento

    private func begin(_ phase: Phase, minutes: Int) {
        self.phase = phase
        phaseStart = Date()
        endDate = phaseStart.addingTimeInterval(Double(minutes) * Self.secondsPerMinute)
        refreshChatter()

        if window == nil { window = TimerWindow() }
        window?.timerView.label = phase.label
        window?.timerView.time = remainingText

        updateStage()

        // Il personaggio si alza subito (se serve) e resta lì per tutta la sessione: così la posizione
        // non cambia quando l'orologio compare e scompare.
        ensureRoomBelowPet()
        evaluateVisibility()

        ticker?.invalidate()
        // Modalità .common: il timer continua a scorrere anche mentre un menu è aperto.
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        if endDate.timeIntervalSinceNow <= 0 {
            finish()
            return
        }
        if phase == .focus { log.heartbeat() }
        window?.timerView.time = remainingText
        updateStage()
        evaluateVisibility()
    }

    private func finish() {
        guard let finished = phase else { return }
        NSSound(named: NSSound.Name("Glass"))?.play()
        if !petWindow.isVisible { petWindow.orderFrontRegardless() }

        switch finished {
        case .focus:
            let breakLength = breakMinutes
            let studied = plannedFocusMinutes
            let finishedSubject = subject
            recordFocus(completed: true)
            subject = nil
            begin(.rest, minutes: breakLength)
            speaker.say(Self.focusFinishedMessage(subject: finishedSubject, studiedMinutes: studied, breakMinutes: breakLength))
        case .rest:
            stop()
            speaker.say("Pausa finita! Pronto per un altro giro?")
        }
    }

    /// "Hai studiato Anatomia per 50 minuti. Che bel lavoro!", con qualche variante.
    static func focusFinishedMessage(subject: String?, studiedMinutes: Int, breakMinutes: Int) -> String {
        guard let subject else {
            return "Focus finito! Ti sei meritato \(breakMinutes) minuti di pausa."
        }
        let variants = [
            "Hai studiato \(subject) per \(studiedMinutes) minuti. Che bel lavoro! Ora \(breakMinutes) minuti di pausa.",
            "\(subject): \(studiedMinutes) minuti di concentrazione. Ottimo lavoro, ti sei meritato \(breakMinutes) minuti di pausa.",
            "Ben fatto! \(studiedMinutes) minuti su \(subject). Respira: \(breakMinutes) minuti di pausa.",
        ]
        return variants.randomElement() ?? variants[0]
    }

    // MARK: - Crescita

    /// Per i personaggi che crescono: durante il focus lo stadio avanza con il tempo,
    /// in tutti gli altri momenti sta allo stadio finale.
    private func updateStage() {
        let pet = petWindow.pet
        guard pet.growsWithTimer else { return }
        guard phase == .focus else {
            petWindow.setStage(pet.finalStage)
            return
        }
        let total = endDate.timeIntervalSince(phaseStart)
        let progress = total > 0 ? Date().timeIntervalSince(phaseStart) / total : 1
        petWindow.setStage(pet.stage(forProgress: progress))
    }

    // MARK: - Quando mostrare l'orologio

    /// Visibile: nei primi minuti di ogni fase, negli ultimi minuti, e finché il mouse sta sul personaggio.
    private func evaluateVisibility() {
        guard phase != nil, window != nil else { return }
        let now = Date()
        let minute = Self.secondsPerMinute

        if petWindow.isVisible, petWindow.artFrame.contains(NSEvent.mouseLocation) {
            hoverUntil = now.addingTimeInterval(Self.hoverLinger)
        }
        let wanted = now.timeIntervalSince(phaseStart) < Self.introMinutes * minute
            || endDate.timeIntervalSince(now) <= Self.alwaysVisibleMinutes * minute
            || now < hoverUntil

        if wanted && !isShown {
            reveal()
        } else if !wanted && isShown {
            conceal()
        }
    }

    // MARK: - Finestra del timer (tendina)

    /// Posizione dell'orologio a grandezza piena: centrato appena sotto i piedi del personaggio.
    private func fullFrame() -> NSRect {
        let size = TimerWindow.size
        let screen = (petWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let anchor = petWindow.frame
        var x = anchor.midX - size.width / 2
        x = min(max(x, screen.minX + 4), screen.maxX - size.width - 4)
        return NSRect(x: x, y: petWindow.feetY - size.height + 4, width: size.width, height: size.height)
    }

    private func reveal() {
        guard let window, !isShown, petWindow.isVisible else { return }
        ensureRoomBelowPet()
        isShown = true

        // La finestra va subito al suo posto, a grandezza piena, ed è figlia del personaggio: così lo
        // segue sempre. A "srotolarsi" è solo il disegno (vedi TimerView.reveal).
        window.setFrame(fullFrame(), display: false)
        if window.timerView.reveal >= 1 { window.timerView.reveal = 0 }   // non è già aperta
        petWindow.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
        animateCurtain(to: 1, easing: { 1 - pow(1 - $0, 3) }, completion: nil)   // si apre decelerando
    }

    private func conceal() {
        guard let window, isShown else { return }
        isShown = false
        animateCurtain(to: 0, easing: { pow($0, 3) }) { [weak self] in
            // Se nel frattempo è stato richiesto di nuovo, non toglierlo.
            guard let self, !self.isShown else { return }
            self.petWindow.removeChildWindow(window)
            window.orderOut(nil)
        }
    }

    /// Porta la tendina a `target` (0 chiusa, 1 aperta) in `curtainDuration` secondi, a partire da dove si trova.
    private func animateCurtain(to target: CGFloat, easing: @escaping (CGFloat) -> CGFloat, completion: (() -> Void)?) {
        curtainTimer?.invalidate()
        guard let view = window?.timerView else { completion?(); return }
        let from = view.reveal
        let started = Date()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] t in
            let p = CGFloat(min(Date().timeIntervalSince(started) / Self.curtainDuration, 1))
            view.reveal = from + (target - from) * easing(p)
            if p >= 1 {
                t.invalidate()
                self?.curtainTimer = nil
                completion?()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        curtainTimer = timer
    }

    // MARK: - Spazio sotto il personaggio

    /// Se sotto il personaggio non c'è posto (sta sul fondo, sopra il Dock) lo alzo, e lo riabbasso a fine sessione.
    private func ensureRoomBelowPet() {
        guard !petWindow.isPicked else { return }   // mentre lo trascini la posizione la decide il mouse
        let screen = (petWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let needed = TimerWindow.size.height - 4
        let room = petWindow.feetY - screen.minY
        guard room < needed else { return }

        var frame = petWindow.frame
        frame.origin.y += needed - room
        shiftedUp += needed - room
        petWindow.setFrame(frame, display: true, animate: true)
    }

    private func restorePetHeight() {
        guard shiftedUp > 0 else { return }
        let floor = (petWindow.screen ?? NSScreen.main)?.visibleFrame.minY ?? 0
        var frame = petWindow.frame
        frame.origin.y = max(frame.origin.y - shiftedUp, floor)
        shiftedUp = 0
        petWindow.setFrame(frame, display: true, animate: true)
    }
}
