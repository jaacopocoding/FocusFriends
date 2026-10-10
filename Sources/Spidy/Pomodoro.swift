import AppKit

/// Timer pomodoro: una fase di focus, poi una pausa. Il conto alla rovescia sta sotto Spidy.
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
    /// Quanto resta visibile dopo che il mouse esce da Spidy.
    private static let hoverLinger: TimeInterval = 1
    private static let curtainDuration: TimeInterval = 0.35

    private static let chatterWhileFocusing: ClosedRange<TimeInterval> = 240...480
    private static let chatterNormally: ClosedRange<TimeInterval> = 40...110

    private let spidy: SpidyWindow
    private let speaker: Speaker
    private var window: TimerWindow?
    private var ticker: Timer?
    private var phaseStart = Date()
    private var endDate = Date()
    private var isShown = false
    private var hoverUntil = Date.distantPast
    /// Quanto ho dovuto alzare Spidy per fare spazio al timer sotto di lui.
    private var shiftedUp: CGFloat = 0

    private(set) var phase: Phase?
    private(set) var breakMinutes = 5

    init(spidy: SpidyWindow, speaker: Speaker) {
        self.spidy = spidy
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
        updateStage()   // senza timer il personaggio sta allo stadio finale

        if let window {
            spidy.removeChildWindow(window)
            window.orderOut(nil)
        }
        window = nil
        isShown = false
        restoreSpidyHeight()
    }

    // MARK: - Andamento

    private func begin(_ phase: Phase, minutes: Int) {
        self.phase = phase
        phaseStart = Date()
        endDate = phaseStart.addingTimeInterval(Double(minutes) * Self.secondsPerMinute)
        speaker.interval = phase == .focus ? Self.chatterWhileFocusing : Self.chatterNormally

        if window == nil { window = TimerWindow() }
        window?.timerView.label = phase.label
        window?.timerView.time = remainingText

        updateStage()

        // Spidy si alza subito (se serve) e resta lì per tutta la sessione: così la posizione
        // non cambia quando l'orologio compare e scompare.
        ensureRoomBelowSpidy()
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
        if !spidy.isVisible { spidy.orderFrontRegardless() }

        switch finished {
        case .focus:
            let minutes = breakMinutes
            begin(.rest, minutes: minutes)
            speaker.say("Focus finito! Ti sei meritato \(minutes) minuti di pausa.")
        case .rest:
            stop()
            speaker.say("Pausa finita! Pronto per un altro giro?")
        }
    }

    // MARK: - Crescita

    /// Per i personaggi che crescono (Bonsy): durante il focus lo stadio avanza con il tempo,
    /// in tutti gli altri momenti sta allo stadio finale.
    private func updateStage() {
        let pet = spidy.pet
        guard pet.growsWithTimer else { return }
        guard phase == .focus else {
            spidy.setStage(pet.finalStage)
            return
        }
        let total = endDate.timeIntervalSince(phaseStart)
        let progress = total > 0 ? Date().timeIntervalSince(phaseStart) / total : 1
        spidy.setStage(pet.stage(forProgress: progress))
    }

    // MARK: - Quando mostrare l'orologio

    /// Visibile: nei primi minuti di ogni fase, negli ultimi minuti, e finché il mouse sta su Spidy.
    private func evaluateVisibility() {
        guard phase != nil, window != nil else { return }
        let now = Date()
        let minute = Self.secondsPerMinute

        if spidy.isVisible, spidy.artFrame.contains(NSEvent.mouseLocation) {
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

    /// Posizione dell'orologio a grandezza piena: centrato appena sotto i piedi di Spidy.
    private func fullFrame() -> NSRect {
        let size = TimerWindow.size
        let screen = (spidy.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let anchor = spidy.frame
        var x = anchor.midX - size.width / 2
        x = min(max(x, screen.minX + 4), screen.maxX - size.width - 4)
        return NSRect(x: x, y: anchor.minY - size.height + 4, width: size.width, height: size.height)
    }

    /// Stessa finestra ma alta una riga, attaccata in alto: la tendina chiusa.
    private func collapsed(_ frame: NSRect) -> NSRect {
        NSRect(x: frame.minX, y: frame.maxY - 1, width: frame.width, height: 1)
    }

    private func reveal() {
        guard let window, !isShown, spidy.isVisible else { return }
        ensureRoomBelowSpidy()
        let target = fullFrame()
        isShown = true

        window.setFrame(collapsed(target), display: false)
        // Figlio di Spidy: se lo trascini, l'orologio lo segue.
        spidy.addChildWindow(window, ordered: .above)
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
            self.spidy.removeChildWindow(window)
            window.orderOut(nil)
        })
    }

    // MARK: - Spazio sotto Spidy

    /// Se sotto Spidy non c'è posto (sta sul fondo, sopra il Dock) lo alzo, e lo riabbasso a fine sessione.
    private func ensureRoomBelowSpidy() {
        let screen = (spidy.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let needed = TimerWindow.size.height - 4
        let room = spidy.frame.minY - screen.minY
        guard room < needed else { return }

        var frame = spidy.frame
        frame.origin.y += needed - room
        shiftedUp += needed - room
        spidy.setFrame(frame, display: true, animate: true)
    }

    private func restoreSpidyHeight() {
        guard shiftedUp > 0 else { return }
        let floor = (spidy.screen ?? NSScreen.main)?.visibleFrame.minY ?? 0
        var frame = spidy.frame
        frame.origin.y = max(frame.origin.y - shiftedUp, floor)
        shiftedUp = 0
        spidy.setFrame(frame, display: true, animate: true)
    }
}
