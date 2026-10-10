import AppKit

/// Fa comparire ogni tanto un fumetto con una frase sopra la testa di Spidy.
final class Speaker {
    private let spidy: NSWindow
    private var bubble: BubbleWindow?
    private var nextTimer: Timer?
    private var hideTimer: Timer?
    private var lastQuote: String?

    init(spidy: NSWindow) {
        self.spidy = spidy
    }

    /// Prima frase dopo qualche secondo, poi a intervalli casuali.
    func start() {
        scheduleNext(after: 5)
    }

    func stop() {
        nextTimer?.invalidate()
        hideTimer?.invalidate()
        dismissBubble(animated: false)
    }

    /// Pesca una frase a caso, diversa dall'ultima.
    func sayRandom() {
        // Rilegge il file a ogni frase: le modifiche si vedono subito, senza riavviare.
        let quotes = Quotes.load()
        let choices = quotes.count > 1 ? quotes.filter { $0 != lastQuote } : quotes
        say(choices.randomElement() ?? Quotes.fallback)
    }

    func say(_ text: String) {
        lastQuote = text
        nextTimer?.invalidate()
        hideTimer?.invalidate()
        dismissBubble(animated: false)

        let window = BubbleWindow()
        let size = BubbleView.size(for: text)
        let anchor = spidy.frame
        let screen = (spidy.screen ?? NSScreen.main)?.visibleFrame ?? .zero

        // Fumetto sopra la testa, spostato a sinistra così la codina resta verso destra.
        var x = anchor.midX - size.width + 30
        x = min(max(x, screen.minX + 6), screen.maxX - size.width - 6)
        var y = anchor.maxY - 4
        y = min(y, screen.maxY - size.height - 4)

        window.bubbleView.text = text
        window.bubbleView.tailX = min(max(anchor.midX - x, BubbleView.minTailInset), size.width - BubbleView.minTailInset)
        window.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
        window.alphaValue = 0

        // Figlia di Spidy: se lo trascini, il fumetto lo segue.
        spidy.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            window.animator().alphaValue = 1
        }
        bubble = window

        let visibleFor = max(4.5, 2.5 + Double(text.count) * 0.06)
        hideTimer = Timer.scheduledTimer(withTimeInterval: visibleFor, repeats: false) { [weak self] _ in
            self?.dismissBubble(animated: true)
            self?.scheduleNext(after: .random(in: 40...110))
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
        let remove = { [spidy] in
            spidy.removeChildWindow(window)
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
