import AppKit

/// Fa camminare per lo schermo i personaggi che camminano (Pet.walks): un po' di passeggiata
/// in una direzione, una pausa, poi di nuovo, rimbalzando ai bordi dello schermo.
/// Muove solo la posizione orizzontale: se lo trascini in alto, cammina a quell'altezza.
final class Walker {
    private enum State {
        case resting(until: Date)
        case walking(until: Date, direction: CGFloat)   // direction: -1 sinistra, +1 destra
    }

    /// Velocità in punti al secondo.
    private static let speed: CGFloat = 42
    /// Ogni quanto cambia fotogramma del passo, in secondi.
    private static let stepInterval: TimeInterval = 0.2
    private static let edgeMargin: CGFloat = 6

    private let petWindow: PetWindow
    private let speaker: Speaker
    private var timer: Timer?
    private var state: State = .resting(until: Date().addingTimeInterval(2))
    private var lastTick = Date()
    private var stepClock: TimeInterval = 0
    /// Posizione orizzontale "esatta": AppKit arrotonda a punti interi, e sommando passi di 1,4 punti
    /// la velocità reale verrebbe falsata. Qui accumulo i decimali.
    private var exactX: CGFloat?
    private var appliedX: CGFloat = 0
    private var activityClock: TimeInterval = 0
    private var wasInActivity = false

    private static let movementKey = "movement"

    /// L'utente può fermare la passeggiata dal menu (In movimento / Fermo). Vale per chi cammina.
    static var isMovementEnabled: Bool {
        get { UserDefaults.standard.object(forKey: movementKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: movementKey) }
    }

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

    private func tick() {
        let now = Date()
        let dt = min(now.timeIntervalSince(lastTick), 0.1)   // dopo uno stop (sleep) non faccio salti
        lastTick = now

        let pet = petWindow.pet
        guard pet.walks, petWindow.isVisible else { return }

        // Sta fermo mentre lo trascini col mouse.
        let beingDragged = petWindow.isPicked
            || (NSEvent.pressedMouseButtons & 1 != 0 && petWindow.frame.contains(NSEvent.mouseLocation))

        // Azioni legate al timer (dorme, festeggia, mangia): restano al loro posto e animano i fotogrammi.
        let activityFrames = pet.frames(for: petWindow.activity)
        if !beingDragged, !activityFrames.isEmpty {
            wasInActivity = true
            activityClock += dt
            let interval: TimeInterval
            switch petWindow.activity {
            case .sleeping: interval = 0.9      // respiro lento
            case .celebrating: interval = 0.14  // salti veloci
            default: interval = 0.28            // mastica
            }
            petWindow.setPose(activityFrames[Int(activityClock / interval) % activityFrames.count])
            return
        }
        if wasInActivity {
            // Finita l'azione: riparte con calma, senza scattare subito.
            wasInActivity = false
            activityClock = 0
            state = .resting(until: now.addingTimeInterval(1.5))
        }

        // "Fermo" dal menu: resta nella posa a riposo (e quando riparte aspetta un attimo prima di muoversi).
        guard Self.isMovementEnabled else {
            petWindow.setPose(pet.restStage)
            state = .resting(until: now.addingTimeInterval(1.5))
            return
        }

        // Sta fermo mentre parla.
        if speaker.isSpeaking || beingDragged {
            petWindow.setPose(speaker.isSpeaking ? (pet.talkFrame ?? pet.restStage) : pet.restStage)
            // La passeggiata riprende da dove era: sposto in avanti il termine della fase.
            switch state {
            case .resting(let until): state = .resting(until: until.addingTimeInterval(dt))
            case .walking(let until, let d): state = .walking(until: until.addingTimeInterval(dt), direction: d)
            }
            return
        }

        switch state {
        case .resting(let until):
            petWindow.setPose(pet.restStage)
            if now >= until {
                let direction = chooseDirection()
                state = .walking(until: now.addingTimeInterval(.random(in: 3...8)), direction: direction)
                petWindow.setFacing(right: direction > 0)
                stepClock = 0
            }

        case .walking(let until, var direction):
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
                state = .resting(until: now.addingTimeInterval(.random(in: 4...10)))
                petWindow.setPose(pet.restStage)
            } else {
                state = .walking(until: until, direction: direction)
            }
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
