import AppKit

/// Dà vita ai personaggi che camminano (Pet.walks): passeggiate in orizzontale per lo schermo con
/// pause, ogni tanto uno spuntino (la carota) o un pisolino, e le feste a fine focus.
/// Muove solo la posizione orizzontale: se lo trascini in alto, cammina a quell'altezza.
final class Walker {
    private enum State {
        case resting(until: Date)
        case walking(until: Date, direction: CGFloat)    // direction: -1 sinistra, +1 destra
        case eating(until: Date)                         // si ferma a mangiare (per chi ha i fotogrammi)
        case sleeping(start: Date, until: Date)          // dorme (per chi ha i fotogrammi)
    }

    // Camminata
    private static let speed: CGFloat = 42                       // punti al secondo
    private static let stepInterval: TimeInterval = 0.2          // cambio fotogramma del passo
    private static let edgeMargin: CGFloat = 6
    private static let walkDuration: ClosedRange<TimeInterval> = 3...8
    private static let restDuration: ClosedRange<TimeInterval> = 4...10

    // Momenti casuali: dopo una pausa può mangiare, dormire, oppure ripartire.
    private static let eatChance = 0.3
    private static let sleepChance = 0.15
    private static let eatDuration: ClosedRange<TimeInterval> = 6...12
    private static let sleepDuration: ClosedRange<TimeInterval> = 12...30
    private static let chewInterval: TimeInterval = 0.28
    private static let breathInterval: TimeInterval = 0.9
    private static let drowsySeconds: TimeInterval = 1.5         // assopito, prima e dopo il sonno
    private static let afterActivityPause: TimeInterval = 1.5

    private static let movementKey = "movement"

    /// L'utente può fermare la passeggiata dal menu (In movimento / Fermo). Vale per chi cammina.
    static var isMovementEnabled: Bool {
        get { UserDefaults.standard.object(forKey: movementKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: movementKey) }
    }

    private let petWindow: PetWindow
    private let speaker: Speaker
    private var timer: Timer?
    private var state: State = .resting(until: Date().addingTimeInterval(2))
    private var lastTick = Date()
    private var stepClock: TimeInterval = 0
    private var activityClock: TimeInterval = 0
    private var wasInTimerActivity = false
    /// Appena finito di mangiare o dormire: la prossima scelta è per forza una camminata.
    private var justRested = false
    /// Posizione orizzontale "esatta": AppKit arrotonda a punti interi, e sommando passi di 1,4 punti
    /// la velocità reale verrebbe falsata. Qui accumulo i decimali.
    private var exactX: CGFloat?
    private var appliedX: CGFloat = 0

    init(petWindow: PetWindow, speaker: Speaker) {
        self.petWindow = petWindow
        self.speaker = speaker
    }

    func start() {
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Un passo del ciclo

    private func tick() {
        let now = Date()
        let dt = min(now.timeIntervalSince(lastTick), 0.1)   // dopo uno stop (sleep) non faccio salti
        lastTick = now

        let pet = petWindow.pet
        guard pet.walks, petWindow.isVisible else {
            petWindow.setSleepMarks(false)
            return
        }

        let beingDragged = petWindow.isPicked
            || (NSEvent.pressedMouseButtons & 1 != 0 && petWindow.frame.contains(NSEvent.mouseLocation))

        // Mentre lo trascini: posa a riposo, e le fasi in corso restano in attesa.
        if beingDragged {
            petWindow.setPose(pet.restStage)
            petWindow.setSleepMarks(false)
            delayState(by: dt)
            return
        }

        // Festa a fine focus (legata al timer): resta al suo posto e anima i fotogrammi.
        let timerFrames = pet.frames(for: petWindow.activity)
        if !timerFrames.isEmpty {
            wasInTimerActivity = true
            activityClock += dt
            petWindow.setSleepMarks(false)
            petWindow.setPose(timerFrames[Int(activityClock / 0.14) % timerFrames.count])
            return
        }
        if wasInTimerActivity {
            wasInTimerActivity = false
            activityClock = 0
            state = .resting(until: now.addingTimeInterval(Self.afterActivityPause))
        }

        // "Fermo" dal menu: resta nella posa a riposo (e quando riparte aspetta un attimo).
        guard Self.isMovementEnabled else {
            petWindow.setPose(pet.restStage)
            petWindow.setSleepMarks(false)
            state = .resting(until: now.addingTimeInterval(Self.afterActivityPause))
            return
        }

        // Sta fermo mentre parla, ma se mangia o dorme resta nella sua posa.
        if speaker.isSpeaking, !isEatingOrSleeping {
            petWindow.setPose(pet.talkFrame ?? pet.restStage)
            delayState(by: dt)
            return
        }

        switch state {
        case .resting(let until):
            petWindow.setPose(pet.restStage)
            petWindow.setSleepMarks(false)
            if now >= until { chooseNext(now: now, pet: pet) }

        case .walking(let until, let direction):
            walk(now: now, dt: dt, until: until, direction: direction, pet: pet)

        case .eating(let until):
            // Resta dov'è e cicla i fotogrammi della carota.
            stepClock += dt
            let frames = pet.eatFrames
            petWindow.setPose(frames[Int(stepClock / Self.chewInterval) % frames.count])
            if now >= until { finishActivity(now: now, pet: pet) }

        case .sleeping(let start, let until):
            // Assopito, poi respira piano (con gli "Zzz"), poi di nuovo assopito prima di svegliarsi.
            let t = now.timeIntervalSince(start)
            let remaining = until.timeIntervalSince(now)
            if let drowsy = pet.sleepIntroFrame, t < Self.drowsySeconds || remaining < Self.drowsySeconds {
                petWindow.setPose(drowsy)
                petWindow.setSleepMarks(false)
            } else {
                let frames = pet.sleepFrames
                petWindow.setPose(frames[Int((t - Self.drowsySeconds) / Self.breathInterval) % frames.count])
                petWindow.setSleepMarks(true)
            }
            if now >= until { finishActivity(now: now, pet: pet) }
        }
    }

    private var isEatingOrSleeping: Bool {
        switch state {
        case .eating, .sleeping: return true
        default: return false
        }
    }

    /// Sposta in avanti il termine della fase attuale (mentre parla o lo trascini non "consuma" tempo).
    private func delayState(by dt: TimeInterval) {
        switch state {
        case .resting(let until): state = .resting(until: until.addingTimeInterval(dt))
        case .walking(let until, let d): state = .walking(until: until.addingTimeInterval(dt), direction: d)
        case .eating(let until): state = .eating(until: until.addingTimeInterval(dt))
        case .sleeping(let start, let until):
            state = .sleeping(start: start.addingTimeInterval(dt), until: until.addingTimeInterval(dt))
        }
    }

    // MARK: - Scelte

    /// Finita una pausa: a sorte mangia, dorme o riparte. Dopo aver mangiato o dormito riparte per forza.
    private func chooseNext(now: Date, pet: Pet) {
        let roll = Double.random(in: 0..<1)
        let canEat = !pet.eatFrames.isEmpty && !justRested
        let canSleep = !pet.sleepFrames.isEmpty && !justRested

        if canEat && roll < Self.eatChance {
            state = .eating(until: now.addingTimeInterval(.random(in: Self.eatDuration)))
            stepClock = 0
        } else if canSleep && roll >= Self.eatChance && roll < Self.eatChance + Self.sleepChance {
            state = .sleeping(start: now, until: now.addingTimeInterval(.random(in: Self.sleepDuration)))
        } else {
            justRested = false
            let direction = chooseDirection()
            state = .walking(until: now.addingTimeInterval(.random(in: Self.walkDuration)), direction: direction)
            petWindow.setFacing(right: direction > 0)
            stepClock = 0
        }
    }

    private func finishActivity(now: Date, pet: Pet) {
        state = .resting(until: now.addingTimeInterval(Self.afterActivityPause))
        petWindow.setPose(pet.restStage)
        petWindow.setSleepMarks(false)
        justRested = true
    }

    // MARK: - Camminata

    private func walk(now: Date, dt: TimeInterval, until: Date, direction startDirection: CGFloat, pet: Pet) {
        var direction = startDirection
        petWindow.setSleepMarks(false)

        let screen = (petWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let minX = screen.minX + Self.edgeMargin
        let maxX = screen.maxX - petWindow.frame.width - Self.edgeMargin

        // Se qualcun altro ha spostato la finestra (l'utente col mouse), riparto da lì.
        let current = petWindow.frame.origin.x
        if exactX == nil || abs(current - appliedX) > 1.5 { exactX = current }

        var x = exactX! + direction * Self.speed * CGFloat(dt)
        if x <= minX { x = minX; direction = 1 }
        if x >= maxX { x = maxX; direction = -1 }
        petWindow.setFacing(right: direction > 0)
        exactX = x
        petWindow.setFrameOrigin(NSPoint(x: x.rounded(), y: petWindow.frame.origin.y))
        appliedX = petWindow.frame.origin.x

        // Passi: i fotogrammi del cammino si ripetono in ciclo.
        stepClock += dt
        let frames = pet.walkFrames
        petWindow.setPose(frames[Int(stepClock / Self.stepInterval) % frames.count])

        if now >= until {
            state = .resting(until: now.addingTimeInterval(.random(in: Self.restDuration)))
            petWindow.setPose(pet.restStage)
        } else {
            state = .walking(until: until, direction: direction)
        }
    }

    /// Direzione a caso, ma verso il centro se è vicino a un bordo.
    private func chooseDirection() -> CGFloat {
        let screen = (petWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let room = screen.width - petWindow.frame.width
        let position = (petWindow.frame.minX - screen.minX) / max(room, 1)   // 0 = a sinistra, 1 = a destra
        if position < 0.15 { return 1 }
        if position > 0.85 { return -1 }
        return Bool.random() ? 1 : -1
    }
}
