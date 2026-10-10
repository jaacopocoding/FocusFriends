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

    private static let chatterWhileFocusing: ClosedRange<TimeInterval> = 240...480
    private static let chatterNormally: ClosedRange<TimeInterval> = 40...110

    private let spidy: NSWindow
    private let speaker: Speaker
    private var window: TimerWindow?
    private var ticker: Timer?
    private var endDate = Date()
    /// Quanto ho dovuto alzare Spidy per fare spazio al timer sotto di lui.
    private var shiftedUp: CGFloat = 0

    private(set) var phase: Phase?
    private(set) var breakMinutes = 5

    init(spidy: NSWindow, speaker: Speaker) {
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

        if let window {
            spidy.removeChildWindow(window)
            window.orderOut(nil)
        }
        window = nil
        restoreSpidyHeight()
    }

    // MARK: - Andamento

    private func begin(_ phase: Phase, minutes: Int) {
        self.phase = phase
        endDate = Date().addingTimeInterval(Double(minutes) * Self.secondsPerMinute)
        speaker.interval = phase == .focus ? Self.chatterWhileFocusing : Self.chatterNormally

        showWindowIfNeeded()
        window?.timerView.label = phase.label
        window?.timerView.time = remainingText

        ticker?.invalidate()
        // Modalità .common: il timer continua a scorrere anche mentre un menu è aperto.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        if endDate.timeIntervalSinceNow <= 0 {
            finish()
        } else {
            window?.timerView.time = remainingText
        }
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

    // MARK: - Finestra del timer

    private func showWindowIfNeeded() {
        guard window == nil else { return }
        let timerWindow = TimerWindow()
        let size = TimerWindow.size
        let screen = (spidy.screen ?? NSScreen.main)?.visibleFrame ?? .zero

        // Se sotto Spidy non c'è posto (sta sul fondo, sopra il Dock) lo alzo, e lo riabbasso a fine timer.
        let needed = size.height - 4
        let room = spidy.frame.minY - screen.minY
        if room < needed {
            var frame = spidy.frame
            frame.origin.y += needed - room
            shiftedUp = needed - room
            spidy.setFrame(frame, display: true, animate: true)
        }

        // Appoggiato appena sotto i piedi di Spidy, centrato.
        let anchor = spidy.frame
        var x = anchor.midX - size.width / 2
        x = min(max(x, screen.minX + 4), screen.maxX - size.width - 4)
        let y = anchor.minY - size.height + 4
        timerWindow.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)

        // Figlio di Spidy: se lo trascini, il timer lo segue.
        spidy.addChildWindow(timerWindow, ordered: .above)
        timerWindow.orderFront(nil)
        window = timerWindow
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
