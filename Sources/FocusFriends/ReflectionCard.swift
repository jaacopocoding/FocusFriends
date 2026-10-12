import AppKit

/// "Com'è andata?": la scheda che compare a fine focus. Un tocco su una faccia salva e chiude; la riga
/// "cosa hai fatto" è facoltativa. Non ruba la tastiera (a fine focus potresti stare scrivendo altrove) e non
/// blocca niente: se la ignori la sessione resta com'è, e la scheda sparisce da sola a fine pausa.
final class ReflectionCard: NSObject {
    private static let width: CGFloat = 400
    private static let enabledKey = "askHowItWent"

    /// Si può spegnere dal menu.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Una parolina del personaggio per ogni risposta.
    static func reply(for rating: FocusRating) -> String {
        let variants: [FocusRating: [String]] = [
            .good: ["Che bello! Segnato nel diario.", "Così si fa! Ne sono contento.", "Bene! Ora una pausa vera."],
            .soso: ["Capita. L'importante è esserci stati.", "Va bene così: un passo alla volta.", "Segnato. Ci riproviamo dopo la pausa."],
            .poor: ["Capita a tutti. Una pausa vera e poi si riparte.", "Nessun problema: oggi la testa era altrove.", "Grazie di averlo detto. Riposati un po'."],
        ]
        return variants[rating]?.randomElement() ?? "Segnato!"
    }

    private let log: SessionLog
    private var panel: KeyablePanel?
    private var field: NSTextField?
    private var sessionID: UUID?
    private var completion: ((FocusRating?) -> Void)?

    init(log: SessionLog = .shared) {
        self.log = log
    }

    var isShowing: Bool { panel != nil }

    /// `completion` riceve il voto scelto (nil se hai scritto solo la nota o hai saltato).
    func ask(session: StudySession, near petWindow: NSWindow?, completion: ((FocusRating?) -> Void)? = nil) {
        dismiss()
        sessionID = session.id
        self.completion = completion

        let card = PaperCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.appearance = NSAppearance(named: .aqua)

        let title = NSTextField(labelWithString: "Com'è andata?")
        title.font = Paper.markerFont(24)
        title.textColor = Paper.ink

        let minutes = (session.seconds + 30) / 60
        let subtitle = NSTextField(labelWithString: [session.subject, "\(minutes) minuti"].compactMap { $0 }.joined(separator: " · "))
        subtitle.font = NSFont.systemFont(ofSize: 13)
        subtitle.textColor = Paper.inkLight
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.widthAnchor.constraint(lessThanOrEqualToConstant: Self.width - 56).isActive = true

        let buttons = FocusRating.allCases.map { rating -> RatingButton in
            let button = RatingButton(rating: rating)
            button.target = self
            button.action = #selector(ratingPressed(_:))
            return button
        }
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        let rowBox = NSView()
        rowBox.translatesAutoresizingMaskIntoConstraints = false
        rowBox.addSubview(row)
        NSLayoutConstraint.activate([
            rowBox.widthAnchor.constraint(equalToConstant: Self.width - 56),
            row.centerXAnchor.constraint(equalTo: rowBox.centerXAnchor),
            row.topAnchor.constraint(equalTo: rowBox.topAnchor),
            row.bottomAnchor.constraint(equalTo: rowBox.bottomAnchor),
        ])

        let field = NSTextField()
        field.placeholderString = "Cosa hai fatto? (facoltativo)"
        field.font = NSFont.systemFont(ofSize: 14)
        field.bezelStyle = .roundedBezel
        field.controlSize = .large
        field.focusRingType = .none
        field.target = self
        field.action = #selector(donePressed)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: Self.width - 56).isActive = true
        self.field = field

        let skip = TextButton(title: "Salta")
        skip.target = self
        skip.action = #selector(skipPressed)
        let done = PillButton(title: "Fatto", width: 110, height: 34)
        done.target = self
        done.action = #selector(donePressed)
        done.keyEquivalent = "\r"
        let bottom = NSStackView(views: [skip, done])
        bottom.orientation = .horizontal
        bottom.spacing = 18
        bottom.alignment = .centerY

        let stack = NSStackView(views: [title, subtitle, rowBox, field, bottom])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(2, after: title)
        stack.setCustomSpacing(8, after: subtitle)
        stack.setCustomSpacing(8, after: rowBox)
        stack.setCustomSpacing(16, after: field)
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 28, bottom: 18, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: Self.width),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            bottom.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -28),
        ])
        card.layoutSubtreeIfNeeded()
        let size = card.fittingSize

        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true     // i pulsanti non prendono la tastiera: solo il campo, se ci clicchi
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = card
        panel.appearance = NSAppearance(named: .aqua)
        panel.onCancel = { [weak self] in self?.skipPressed() }

        // Accanto al personaggio (a sinistra, o a destra se non c'è posto), senza coprirlo.
        let screen = (petWindow?.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        var origin = NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
        if let pet = petWindow {
            var x = pet.frame.minX - size.width - 12
            if x < screen.minX + 8 { x = pet.frame.maxX + 12 }
            origin = NSPoint(x: x, y: pet.frame.minY)
        }
        origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
        origin.y = min(max(origin.y, screen.minY + 8), screen.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
        panel.alphaValue = 0
        panel.orderFrontRegardless()            // senza attivare l'app né prendere la tastiera
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 1
        }
        self.panel = panel
    }

    /// La scheda disegnata in un'immagine (per le anteprime).
    var contentView: NSView? { panel?.contentView }

    /// Chiude senza salvare (fine pausa, nuovo focus).
    func dismiss() {
        close(save: false, rating: nil)
    }

    @objc private func ratingPressed(_ sender: RatingButton) {
        close(save: true, rating: sender.rating)
    }

    @objc private func donePressed() {
        close(save: true, rating: nil)
    }

    @objc private func skipPressed() {
        close(save: false, rating: nil)
    }

    private func close(save: Bool, rating: FocusRating?) {
        guard let panel else { return }
        self.panel = nil
        let note = SessionNote.clean(field?.stringValue)
        field = nil
        let done = completion
        completion = nil
        if save, let id = sessionID, rating != nil || note != nil {
            log.setReflection(id: id, rating: rating, note: note)
        }
        sessionID = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
        if save { done?(rating) }
    }
}
