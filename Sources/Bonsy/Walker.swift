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
    /// Ogni quanto cambia piede, in secondi.
    private static let stepInterval: TimeInterval = 0.22
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

        guard petWindow.pet.walks, petWindow.isVisible else { return }

        // Sta fermo mentre parla o mentre lo trascini col mouse.
        let beingDragged = NSEvent.pressedMouseButtons & 1 != 0 && petWindow.frame.contains(NSEvent.mouseLocation)
        if speaker.isSpeaking || beingDragged {
            petWindow.setPose(0)
            // La passeggiata riprende da dove era: sposto in avanti il termine della fase.
            switch state {
            case .resting(let until): state = .resting(until: until.addingTimeInterval(dt))
            case .walking(let until, let d): state = .walking(until: until.addingTimeInterval(dt), direction: d)
            }
            return
        }

        switch state {
        case .resting(let until):
            petWindow.setPose(0)
            if now >= until {
                state = .walking(until: now.addingTimeInterval(.random(in: 3...8)), direction: chooseDirection())
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
            exactX = x
            petWindow.setFrameOrigin(NSPoint(x: x.rounded(), y: petWindow.frame.origin.y))
            appliedX = petWindow.frame.origin.x

            // Passi alternati: pose 1 e 2.
            stepClock += dt
            petWindow.setPose(Int(stepClock / Self.stepInterval) % 2 == 0 ? 1 : 2)

            if now >= until {
                state = .resting(until: now.addingTimeInterval(.random(in: 4...10)))
                petWindow.setPose(0)
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
