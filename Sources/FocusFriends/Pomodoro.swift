import AppKit

/// Timer pomodoro: una fase di focus, poi una pausa. Il conto alla rovescia sta sotto il personaggio.
final class Pomodoro {
    enum Phase {
        case focus
        case rest

        var label: String { self == .focus ? "FOCUS" : "PAUSA" }
    }

    /// Secondi in un "minuto" del timer.
    private static let secondsPerMinute: TimeInterval = 60

    /// Per quanto l'orologio resta visibile dall'inizio di ogni fase.
    private static let introMinutes: TimeInterval = 2
    /// Quando mancano meno di tanti minuti l'orologio resta sempre visibile.
    private static let alwaysVisibleMinutes: TimeInterval = 5
    /// Quanto resta visibile dopo che il mouse esce dal personaggio.
    private static let hoverLinger: TimeInterval = 1
    private static let curtainDuration: TimeInterval = 0.35
    /// Allo scadere del focus: per quanti secondi resta il pulsante «+5 minuti» prima che parta la pausa.
    private static let graceSeconds: TimeInterval = 10
    /// Quanti minuti aggiunge il pulsante.
    static let extensionMinutes = 5
    /// Fra due tick (ogni 0,2 s) non passa mai tanto: se è successo, il Mac ha dormito (o l'app è rimasta ferma) e
    /// quel tempo non è studio.
    private static let sleepGapSeconds: TimeInterval = 10


    private let petWindow: PetWindow
    private let speaker: Speaker
    private var window: TimerWindow?
    private var ticker: Timer?
    private var curtainTimer: Timer?
    private var phaseStart = Date()
    /// Il focus è fermo (dal pulsante «Ferma» della schermata del focus): il conto alla rovescia non scorre.
    private(set) var isFocusPaused = false
    /// Quanto è rimasto fermo il focus in corso: va tolto dal tempo trascorso. (`endDate` si sposta insieme.)
    private var pausedTotal: TimeInterval = 0
    private var lastTick = Date()
    private var endDate = Date()
    private var isShown = false
    private var hoverUntil = Date.distantPast
    /// Quanto ho dovuto alzare il personaggio per fare spazio al timer sotto di lui.
    private var shiftedUp: CGFloat = 0

    private(set) var phase: Phase? {
        didSet {
            let was = oldValue == .focus, now = phase == .focus
            if was != now { onFocusActiveChanged?(now) }
        }
    }
    /// Chiamata quando comincia o finisce un focus (compresi i secondi del «+5 minuti»): per il suono ambiente.
    var onFocusActiveChanged: ((Bool) -> Void)?
    private(set) var breakMinutes = 5
    /// La materia del focus in corso (nil = nessuna, o non è un focus).
    private(set) var subject: String?
    /// La voce di «Da fare» da cui è partito il focus in corso (solo in memoria: se l'app si chiude si perde).
    private var todoID: UUID?
    private var plannedFocusMinutes = 0
    /// Le note scritte durante il focus in corso: finiscono nella sessione.
    private(set) var notes: [String] = []
    /// L'ultimo focus finito: quanti minuti, su quale materia e quale sessione (per la schermata della pausa).
    private(set) var lastFocus: (minutes: Int, subject: String?, sessionID: UUID?)?
    /// Sta eliminando il focus: la sessione non va registrata.
    private var discarding = false
    /// Il ciclo dei quattro focus: dopo il quarto la pausa è lunga.
    private var cycle = BreakCycle()
    /// La pausa in corso è la lunga (per la schermata della pausa).
    private(set) var isLongBreak = false
    /// Quanti focus del ciclo sono fatti (0...4), per «focus 2 di 4»; nil se la pausa lunga è spenta.
    /// Durante la pausa lunga sono tutti e quattro.
    var cycleDone: Int? {
        guard BreakCycle.isEnabled else { return nil }
        return isLongBreak ? BreakCycle.focusesPerCycle : cycle.done(at: Date())
    }
    /// Il personaggio con cui è stato avviato il focus in corso.
    private var focusPet: String?
    private let log: SessionLog
    /// Finché c'è, il tempo è scaduto e il pulsante «+5 minuti» è sullo schermo: a questo istante parte la pausa.
    private var graceUntil: Date?
    /// Quante volte hai aggiunto minuti al focus in corso.
    private var extensions = 0
    private let extendPrompt = ExtendPrompt()
    /// Chiamata quando un focus finisce davvero (non se lo fermi): il porcellino mangia la carota.
    var onFocusCompleted: (() -> Void)?
    /// Chiamata con la sessione appena salvata quando un focus finisce davvero ("com'è andata?").
    /// Il focus è finito ed è stato registrato; `todoID` è la voce di «Da fare» da cui era partito (nil se non partiva da una).
    var onFocusRecorded: ((StudySession, _ todoID: UUID?) -> Void)?
    /// Chiamata quando il timer si ferma o ne parte uno nuovo: la scheda "com'è andata?" non serve più.
    var onTimerReset: (() -> Void)?

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

    /// Il tempo davvero passato in questa fase, senza i momenti in cui è stata ferma.
    private var activeElapsed: TimeInterval { Date().timeIntervalSince(phaseStart) - pausedTotal }
    /// La durata della fase (prevista più i minuti aggiunti), senza i momenti in cui è stata ferma.
    private var activeTotal: TimeInterval { endDate.timeIntervalSince(phaseStart) - pausedTotal }

    // MARK: - Comandi

    func startFocus(minutes: Int, subject: String? = nil, todoID: UUID? = nil) {
        onTimerReset?()
        recordFocus(completed: false)     // se ce n'era uno in corso, finisce qui
        endGrace()
        extensions = 0
        lastFocus = nil
        notes = []
        self.subject = Subject.clean(subject)
        self.todoID = todoID
        plannedFocusMinutes = minutes
        focusPet = petWindow.pet.id
        begin(.focus, minutes: minutes)
        log.beginInProgress(start: phaseStart, plannedMinutes: minutes, subject: self.subject, pet: focusPet)
        if let subject = self.subject {
            speaker.say("Focus di \(minutes) minuti su \(subject): si parte!")
        } else {
            speaker.say("Focus di \(minutes) minuti: si parte!")
        }
    }

    /// Avvia subito una pausa e ricorda la durata per quelle automatiche dopo il focus.
    func startBreak(minutes: Int) {
        recordFocus(completed: false)
        endGrace()
        extensions = 0
        lastFocus = nil
        subject = nil
        todoID = nil
        breakMinutes = minutes
        begin(.rest, minutes: minutes)
        speaker.say("Pausa di \(minutes) minuti: stacca un attimo.")
    }

    /// Se un focus è in corso lo mette nel registro (completo o interrotto) e toglie il segno "in corso".
    /// Ritorna la sessione salvata, se era lunga abbastanza da contare.
    @discardableResult
    private func recordFocus(completed: Bool) -> StudySession? {
        guard phase == .focus else { return nil }
        if discarding {
            log.finishInProgress()
            return nil
        }
        // Se il tempo era già scaduto (il pulsante «+5 minuti» era sullo schermo) il focus è completo.
        let completed = completed || graceUntil != nil
        let planned = plannedFocusMinutes
        let elapsed = completed
            ? Int(activeTotal)
            : min(Int(activeElapsed), planned * Int(Self.secondsPerMinute))
        let session = log.add(start: phaseStart, seconds: elapsed, plannedMinutes: planned,
                              completed: completed, subject: subject, pet: focusPet, notes: notes)
        log.finishInProgress()
        return session
    }

    /// Per la chiusura dell'app: un focus ancora in corso viene salvato come interrotto.
    func recordInterruptedFocusOnQuit() {
        recordFocus(completed: false)
    }

    func stop() {
        onTimerReset?()
        recordFocus(completed: false)
        endGrace()
        extensions = 0
        lastFocus = nil
        isFocusPaused = false
        isLongBreak = false
        pausedTotal = 0
        notes = []
        subject = nil
        todoID = nil
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
        let wasPaused = isFocusPaused
        isFocusPaused = false
        pausedTotal = 0
        isLongBreak = false
        self.phase = phase
        if wasPaused, phase == .focus { onFocusActiveChanged?(true) }
        phaseStart = Date()
        lastTick = phaseStart      // il primo tick non deve vedere come "salto" il tempo passato da un'altra fase
        endDate = phaseStart.addingTimeInterval(Double(minutes) * Self.secondsPerMinute)
        refreshChatter()

        if window == nil { window = TimerWindow() }
        window?.timerView.label = phase.label
        window?.timerView.time = remainingText

        updateStage()

        // Il personaggio si alza subito (se serve) e resta lì per tutta la sessione: così la posizione
        // non cambia quando l'orologio compare e scompare.
        ensureRoomBelowPet()
        snapClockToPet()      // l'orologio segue il personaggio (e il suo "piano" quando cambia l'immagine)
        evaluateVisibility()

        ticker?.invalidate()
        // Modalità .common: il timer continua a scorrere anche mentre un menu è aperto.
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        let now = Date()
        let gap = now.timeIntervalSince(lastTick)
        if isFocusPaused {
            // Il tempo non scorre: la fine si sposta in avanti insieme all'orologio.
            endDate = endDate.addingTimeInterval(gap)
            pausedTotal += gap
        } else if phase == .focus, graceUntil == nil, gap > Self.sleepGapSeconds {
            // Il Mac ha dormito durante il focus: come se fosse stato fermo. Altrimenti, al risveglio, il tempo
            // risulterebbe scaduto e le ore di sonno finirebbero nel registro come studio completato.
            endDate = endDate.addingTimeInterval(gap)
            pausedTotal += gap
            log.updateInProgressPause(seconds: Int(pausedTotal), since: nil)
        }
        lastTick = now
        if endDate.timeIntervalSinceNow <= 0 {
            // Il focus è scaduto: qualche secondo per aggiungere minuti, poi finisce e parte la pausa.
            if phase == .focus {
                guard let until = graceUntil else {
                    beginGrace()
                    return
                }
                if Date() >= until {
                    finish()
                } else {
                    window?.timerView.time = remainingText
                }
                return
            }
            finish()
            return
        }
        if phase == .focus { log.heartbeat() }
        window?.timerView.time = remainingText
        updateStage()
        evaluateVisibility()
    }

    // MARK: - Dalla schermata del focus

    /// Quanta parte della fase in corso è passata (0...1).
    var phaseProgress: Double {
        let total = activeTotal
        guard phase != nil, total > 0 else { return 0 }
        return min(max(activeElapsed / total, 0), 1)
    }

    /// "09:00 – 09:50": da quando a quando dura la fase in corso.
    var phaseRangeText: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "\(f.string(from: phaseStart)) – \(f.string(from: endDate))"
    }

    /// I minuti previsti del focus in corso (con quelli aggiunti).
    var focusMinutes: Int { plannedFocusMinutes }

    /// Aggiunge `minutes` alla fase in corso: al focus (anche prima che scada) o alla pausa.
    func addMinutes(_ minutes: Int = Pomodoro.extensionMinutes) {
        switch phase {
        case .focus?:
            if graceUntil != nil {
                extendFocus()
            } else {
                extensions += 1
                plannedFocusMinutes += minutes
                endDate = endDate.addingTimeInterval(Double(minutes) * Self.secondsPerMinute)
                log.beginInProgress(start: phaseStart, plannedMinutes: plannedFocusMinutes, subject: subject, pet: focusPet, notes: notes)
                window?.timerView.time = remainingText
                updateStage()
                evaluateVisibility()
            }
        case .rest?:
            endDate = endDate.addingTimeInterval(Double(minutes) * Self.secondsPerMinute)
            window?.timerView.time = remainingText
        case nil:
            break
        }
    }

    /// «Ferma» / «Riprendi» della schermata del focus: il conto alla rovescia si ferma e il focus resta aperto.
    /// Se il tempo è già scaduto (i secondi del «+5 minuti») non c'è niente da fermare: il focus si chiude.
    func toggleFocusPause() {
        guard phase == .focus else { return }
        if isFocusPaused {
            let now = Date()
            let gap = now.timeIntervalSince(lastTick)
            endDate = endDate.addingTimeInterval(gap)
            pausedTotal += gap
            lastTick = now
            isFocusPaused = false
            log.updateInProgressPause(seconds: Int(pausedTotal), since: nil)
            window?.timerView.label = Phase.focus.label
            window?.timerView.time = remainingText
            onFocusActiveChanged?(true)
            speaker.say("Si riparte!")
        } else if graceUntil != nil {
            stop()
        } else {
            lastTick = Date()
            isFocusPaused = true
            log.updateInProgressPause(seconds: Int(pausedTotal), since: lastTick)
            window?.timerView.label = "FERMO"
            onFocusActiveChanged?(false)
            speaker.say("Timer fermo. Riprendi quando sei pronto.")
        }
    }

    /// Una nota scritta durante il focus (si salva subito, così non si perde).
    func addNote(_ text: String) {
        guard phase == .focus, let clean = FocusNotes.clean(text), notes.count < FocusNotes.maxCount else { return }
        notes.append(clean)
        log.updateInProgressNotes(notes)
    }

    /// Elimina il focus in corso: non viene registrato (niente minuti, niente piantina).
    func discardFocus() {
        guard phase == .focus else { return }
        discarding = true
        stop()
        discarding = false
        speaker.say("Focus eliminato: non resta traccia.")
    }

    // MARK: - «+5 minuti»

    /// Il tempo è scaduto: suona, e per qualche secondo c'è il pulsante per aggiungere minuti.
    private func beginGrace() {
        graceUntil = Date().addingTimeInterval(Self.graceSeconds)
        NSSound(named: NSSound.Name("Glass"))?.play()
        if !petWindow.isVisible { petWindow.orderFrontRegardless() }
        speaker.dismissNow()
        window?.timerView.time = remainingText
        extendPrompt.show(near: petWindow, seconds: Self.graceSeconds, extraMinutes: Self.extensionMinutes) { [weak self] in
            self?.extendFocus()
        }
    }

    private func endGrace() {
        graceUntil = nil
        extendPrompt.hide()
    }

    /// Il pulsante: altri minuti a partire da adesso, e il focus continua.
    private func extendFocus() {
        guard phase == .focus, graceUntil != nil else { return }
        extensions += 1
        plannedFocusMinutes += Self.extensionMinutes
        endDate = Date().addingTimeInterval(Double(Self.extensionMinutes) * Self.secondsPerMinute)
        endGrace()
        log.beginInProgress(start: phaseStart, plannedMinutes: plannedFocusMinutes, subject: subject, pet: focusPet, notes: notes)
        window?.timerView.time = remainingText
        updateStage()
        evaluateVisibility()
        let variants = [
            "Altri \(Self.extensionMinutes) minuti: finisci con calma l'esercizio.",
            "Va bene, \(Self.extensionMinutes) minuti in più. Io resto qui.",
            "Ancora \(Self.extensionMinutes) minuti: ce la fai.",
        ]
        speaker.say(variants.randomElement() ?? variants[0])
    }

    private func finish() {
        guard let finished = phase else { return }
        // Se è finito il tempo del focus il suono è già partito (all'inizio dei secondi di attesa).
        if graceUntil == nil { NSSound(named: NSSound.Name("Glass"))?.play() }
        endGrace()
        if !petWindow.isVisible { petWindow.orderFrontRegardless() }

        switch finished {
        case .focus:
            let longBreak = BreakCycle.isEnabled && cycle.focusCompleted(at: Date())
            if !BreakCycle.isEnabled { cycle.reset() }
            let breakLength = longBreak ? max(BreakCycle.longBreakMinutes, breakMinutes) : breakMinutes
            let studied = plannedFocusMinutes
            let finishedSubject = subject
            let finishedTodo = todoID
            let recorded = recordFocus(completed: true)
            lastFocus = (studied, finishedSubject, recorded?.id)
            notes = []
            subject = nil
            todoID = nil
            // Cosa è successo nel giardino: i punti guadagnati con questo focus (e quanto manca al prossimo).
            var gardenLine = "Il giardino cresce."
            if recorded != nil {
                let today = Date()
                let before = GardenPoints.weightedMinutes(sessions: log.sessions.filter { $0.id != recorded?.id }, now: today)
                let after = GardenPoints.weightedMinutes(sessions: log.sessions, now: today)
                let streak = StudyStreak.analyze(sessions: log.sessions, now: today)
                gardenLine = GardenPoints.finishLine(beforeMinutes: before, afterMinutes: after,
                                                     factor: GardenPoints.multiplierToday(streak))
            }
            begin(.rest, minutes: breakLength)
            isLongBreak = longBreak
            speaker.say(Self.focusFinishedMessage(subject: finishedSubject, studiedMinutes: studied, breakMinutes: breakLength,
                                                  garden: gardenLine, longBreak: longBreak))
            onFocusCompleted?()
            if let recorded { onFocusRecorded?(recorded, finishedTodo) }
        case .rest:
            stop()
            speaker.say("Pausa finita! Pronto per un altro giro?")
        }
    }

    /// "Hai studiato Anatomia per 50 minuti. Che bel lavoro!", con qualche variante. `garden` dice cosa è successo
    /// nel giardino (vedi GardenPoints.finishLine).
    static func focusFinishedMessage(subject: String?, studiedMinutes: Int, breakMinutes: Int, garden: String,
                                     longBreak: Bool = false) -> String {
        if longBreak {
            let about = subject.map { " su \($0)" } ?? ""
            let variants = [
                "Quattro focus di fila\(about): che costanza! \(garden) Ti sei guadagnato una pausa lunga, \(breakMinutes) minuti.",
                "Il quarto focus\(about) è andato! \(garden) Pausa lunga: \(breakMinutes) minuti per respirare davvero.",
            ]
            return variants.randomElement() ?? variants[0]
        }
        guard let subject else {
            return "Focus finito! \(garden) Ti sei meritato \(breakMinutes) minuti di pausa."
        }
        let variants = [
            "Hai studiato \(subject) per \(studiedMinutes) minuti. Che bel lavoro! \(garden) Ora \(breakMinutes) minuti di pausa.",
            "\(subject): \(studiedMinutes) minuti di concentrazione. Ottimo lavoro. \(garden) Ora \(breakMinutes) minuti di pausa.",
            "Ben fatto! \(studiedMinutes) minuti su \(subject). \(garden) Respira: \(breakMinutes) minuti di pausa.",
        ]
        return variants.randomElement() ?? variants[0]
    }

    // MARK: - Crescita

    /// Per i personaggi che crescono: durante il focus lo stadio avanza con il tempo,
    /// in tutti gli altri momenti sta allo stadio finale.
    private func updateStage() {
        let pet = petWindow.pet
        // Chi ha le immagini di crescita del focus (Ciccio): durante il focus prendono il suo posto.
        if !pet.focusGrowthResources.isEmpty {
            if phase == .focus {
                let total = activeTotal
                let progress = total > 0 && extensions == 0 ? activeElapsed / total : 1
                petWindow.showFocusGrowth(stage: pet.focusGrowthStage(forProgress: progress))
            } else {
                petWindow.endFocusGrowth()
            }
            return
        }
        guard pet.growsWithTimer else { return }
        guard phase == .focus else {
            petWindow.setStage(pet.finalStage)
            return
        }
        let total = activeTotal
        // Dopo un «+5 minuti» resta allo stadio finale: la pianta non deve tornare indietro.
        let progress = total > 0 && extensions == 0 ? activeElapsed / total : 1
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
        let wanted = activeElapsed < Self.introMinutes * minute
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
    /// Quando il personaggio mostra le immagini di crescita (la carota, il nido) l'orologio sta un po' più in basso,
    /// così non copre le zampe e le ombre.
    private var clockDrop: CGFloat { petWindow.isShowingFocusGrowth ? 12 : 0 }

    private func fullFrame() -> NSRect {
        let size = TimerWindow.size
        let screen = (petWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let anchor = petWindow.frame
        var x = anchor.midX - size.width / 2
        x = min(max(x, screen.minX + 4), screen.maxX - size.width - 4)
        return NSRect(x: x, y: petWindow.feetY - size.height + 4 - clockDrop, width: size.width, height: size.height)
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
        let needed = TimerWindow.size.height - 4 + clockDrop
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
