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
    /// Quanto dura la festa a fine focus.
    private static let celebrationSeconds: TimeInterval = 6

    private static let chatterWhileFocusing: ClosedRange<TimeInterval> = 240...480
    private static let chatterNormally: ClosedRange<TimeInterval> = 40...110

    private let petWindow: PetWindow
    private let speaker: Speaker
    private var window: TimerWindow?
    private var ticker: Timer?
    private var phaseStart = Date()
    private var endDate = Date()
    private var isShown = false
    private var hoverUntil = Date.distantPast
    /// Quanto ho dovuto alzare il personaggio per fare spazio al timer sotto di lui.
    private var shiftedUp: CGFloat = 0

    private(set) var phase: Phase?
    private(set) var breakMinutes = 5

    init(petWindow: PetWindow, speaker: Speaker) {
        self.petWindow = petWindow
        self.speaker = speaker
    }

    var isRunning: Bool { phase != nil }

    /// Tempo rimasto come "MM:SS", arrotondato per eccesso: parte da 30:00 e finisce a 00:01.
    var remainingText: String {
        let seconds = Int(ceil(max(0, endDate.timeIntervalSinceNow)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Comandi

    func startFocus(minutes: Int) {
        begin(.focus, minutes: minutes)
        speaker.say("Focus di \(minutes) minuti: si parte!")
    }

    /// Avvia subito una pausa e ricorda la durata per quelle automatiche dopo il focus.
    func startBreak(minutes: Int) {
        breakMinutes = minutes
        begin(.rest, minutes: minutes)
        speaker.say("Pausa di \(minutes) minuti: stacca un attimo.")
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        phase = nil
        speaker.interval = Self.chatterNormally
        petWindow.activity = .none
        updateStage()   // senza timer il personaggio sta allo stadio finale

        if let window {
            petWindow.removeChildWindow(window)
            window.orderOut(nil)
        }
        window = nil
        isShown = false
        restorePetHeight()
    }

    // MARK: - Andamento

    private func begin(_ phase: Phase, minutes: Int) {
        self.phase = phase
        phaseStart = Date()
        endDate = phaseStart.addingTimeInterval(Double(minutes) * Self.secondsPerMinute)
        speaker.interval = phase == .focus ? Self.chatterWhileFocusing : Self.chatterNormally
        petWindow.activity = phase == .focus ? .sleeping : .none

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
            let minutes = breakMinutes
            begin(.rest, minutes: minutes)
            speaker.say("Focus finito! Ti sei meritato \(minutes) minuti di pausa.")
            celebrateBeforeEating()
        case .rest:
            stop()
            speaker.say("Pausa finita! Pronto per un altro giro?")
        }
    }

    /// Se il personaggio sa festeggiare, lo fa per qualche secondo quando finisce un focus.
    private func celebrateBeforeEating() {
        guard !petWindow.pet.celebrateFrames.isEmpty else { return }
        petWindow.activity = .celebrating
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.celebrationSeconds) { [weak self] in
            guard let self, self.petWindow.activity == .celebrating else { return }
            self.petWindow.activity = .none
        }
    }

    // MARK: - Crescita

    /// Per i personaggi che crescono (Bonsy): durante il focus lo stadio avanza con il tempo,
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

    /// Stessa finestra ma alta una riga, attaccata in alto: la tendina chiusa.
    private func collapsed(_ frame: NSRect) -> NSRect {
        NSRect(x: frame.minX, y: frame.maxY - 1, width: frame.width, height: 1)
    }

    private func reveal() {
        guard let window, !isShown, petWindow.isVisible else { return }
        ensureRoomBelowPet()
        let target = fullFrame()
        isShown = true

        window.setFrame(collapsed(target), display: false)
        // Figlio del personaggio: se lo trascini, l'orologio lo segue.
        petWindow.addChildWindow(window, ordered: .above)
        window.orderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.curtainDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(target, display: true)
        }
    }

    private func conceal() {
        guard let window, isShown else { return }
        isShown = false

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.curtainDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(collapsed(window.frame), display: true)
        }, completionHandler: { [weak self] in
            // Se nel frattempo è stato richiesto di nuovo, non toglierlo.
            guard let self, !self.isShown else { return }
            self.petWindow.removeChildWindow(window)
            window.orderOut(nil)
        })
    }

    // MARK: - Spazio sotto il personaggio

    /// Se sotto il personaggio non c'è posto (sta sul fondo, sopra il Dock) lo alzo, e lo riabbasso a fine sessione.
    private func ensureRoomBelowPet() {
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
