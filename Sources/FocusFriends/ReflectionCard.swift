import AppKit

/// "Com'è andata?": la scheda che compare a fine focus. Un tocco su una faccia salva e chiude; la riga
/// "cosa hai fatto" è facoltativa. Non ruba la tastiera (a fine focus potresti stare scrivendo altrove) e non
/// blocca niente: se la ignori la sessione resta com'è, e la scheda sparisce da sola a fine pausa.
///
/// Se il focus era partito da una voce di «Da fare», la scheda ha anche «Hai finito «…»?» con *Fatta* e *Non ancora*;
/// con «Chiedi com'è andata» spento ha solo quella domanda.
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
    private var card: PaperCardView?
    private var field: NSTextField?
    private var sessionID: UUID?
    private var completion: ((FocusRating?) -> Void)?
    /// La domanda «Hai finito?» (se c'è) e cosa fare con la risposta.
    private var todoBox: NSView?
    private var onTodoAnswer: ((Bool) -> Void)?
    /// La scheda ha anche le facce e la nota (se no, ha solo «Hai finito?»).
    private var hasReflection = true

    init(log: SessionLog = .shared) {
        self.log = log
    }

    var isShowing: Bool { panel != nil }
    /// Dove sta la scheda sullo schermo, se c'è (il fumetto non ci si mette sopra).
    var visibleFrame: NSRect? { panel?.frame }

    /// `completion` riceve il voto scelto (nil se hai scritto solo la nota o hai saltato). `todo` è la voce di «Da fare» da cui era partito il
    /// focus (ancora da fare): `onTodoAnswer` riceve `true` per *Fatta* e `false` per *Non ancora*. Con `askHowItWent` falso la scheda ha solo
    /// quella domanda; senza `todo` e con `askHowItWent` falso non compare niente.
    func ask(session: StudySession, near petWindow: NSWindow?, todo: ToDoItem? = nil, askHowItWent: Bool = true,
             onTodoAnswer: ((Bool) -> Void)? = nil, completion: ((FocusRating?) -> Void)? = nil) {
        dismiss()
        guard askHowItWent || todo != nil else { return }
        sessionID = session.id
        self.completion = completion
        self.onTodoAnswer = onTodoAnswer
        hasReflection = askHowItWent

        let card = PaperCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.appearance = NSAppearance(named: .aqua)
        self.card = card

        let title = NSTextField(labelWithString: askHowItWent ? "Com'è andata?" : "Hai finito?")
        title.font = Paper.markerFont(24)
        title.textColor = Paper.ink

        let minutes = (session.seconds + 30) / 60
        let subtitle = NSTextField(labelWithString: [session.subject, "\(minutes) minuti"].compactMap { $0 }.joined(separator: " · "))
        subtitle.font = NSFont.systemFont(ofSize: 13)
        subtitle.textColor = Paper.inkLight
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.widthAnchor.constraint(lessThanOrEqualToConstant: Self.width - 56).isActive = true

        var views: [NSView] = [title, subtitle]
        if let todo {
            let box = makeTodoBox(for: todo)
            todoBox = box
            views.append(box)
        }
        var bottom: NSStackView?
        if askHowItWent {
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
            let buttonsRow = NSStackView(views: [skip, done])
            buttonsRow.orientation = .horizontal
            buttonsRow.spacing = 18
            buttonsRow.alignment = .centerY
            bottom = buttonsRow
            views += [rowBox, field, buttonsRow]
        }

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(2, after: title)
        stack.setCustomSpacing(8, after: subtitle)
        if let field = self.field {
            stack.setCustomSpacing(16, after: field)
        }
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 28, bottom: 18, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        var constraints = [
            card.widthAnchor.constraint(equalToConstant: Self.width),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ]
        if let bottom { constraints.append(bottom.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -28)) }
        NSLayoutConstraint.activate(constraints)
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

    /// «Hai finito «…»?» con *Non ancora* e *Fatta*, in un riquadro color pesca come quello del timer.
    private func makeTodoBox(for item: ToDoItem) -> NSView {
        let inner = Self.width - 56
        let box = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.wantsLayer = true
        box.layer?.cornerRadius = 14
        box.layer?.backgroundColor = Paper.accent.withAlphaComponent(0.12).cgColor
        box.layer?.borderColor = Paper.accent.cgColor
        box.layer?.borderWidth = 1

        let question = NSTextField(wrappingLabelWithString: ToDoReminder.finishedQuestion(for: item))
        question.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        question.textColor = Paper.ink
        question.maximumNumberOfLines = 2
        question.preferredMaxLayoutWidth = inner - 28
        let notYet = TextButton(title: "Non ancora")
        notYet.target = self
        notYet.action = #selector(todoNotYetPressed)
        let finished = PillButton(title: "Fatta", width: 100, height: 32)
        finished.target = self
        finished.action = #selector(todoFinishedPressed)
        let buttons = NSStackView(views: [notYet, finished])
        buttons.orientation = .horizontal
        buttons.spacing = 14
        buttons.alignment = .centerY
        buttons.translatesAutoresizingMaskIntoConstraints = false
        question.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(question)
        box.addSubview(buttons)
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: inner),
            question.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            question.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            question.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            buttons.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            buttons.topAnchor.constraint(equalTo: question.bottomAnchor, constant: 8),
            buttons.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
        ])
        return box
    }

    /// La scheda disegnata in un'immagine (per le anteprime).
    var contentView: NSView? { panel?.contentView }

    /// Chiude senza salvare (fine pausa, nuovo focus).
    func dismiss() {
        close(save: false, rating: nil)
    }

    @objc private func todoFinishedPressed() { answerTodo(finished: true) }
    @objc private func todoNotYetPressed() { answerTodo(finished: false) }

    /// La risposta a «Hai finito?»: si comunica subito, e il riquadro sparisce (la scheda si accorcia); se non c'è altro, si chiude.
    private func answerTodo(finished: Bool) {
        guard let box = todoBox, let panel, let card else { return }
        todoBox = nil
        let answer = onTodoAnswer
        onTodoAnswer = nil
        answer?(finished)
        guard hasReflection else {
            close(save: false, rating: nil)
            return
        }
        box.isHidden = true
        card.layoutSubtreeIfNeeded()
        let size = card.fittingSize
        var frame = panel.frame
        frame.origin.y = frame.maxY - size.height          // il bordo alto resta dov'era
        frame.size = size
        panel.setFrame(frame, display: true, animate: true)
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
        card = nil
        todoBox = nil
        onTodoAnswer = nil
        let note = SessionNote.clean(field?.stringValue)
        field = nil
        let done = completion
        completion = nil
        if save, let id = sessionID, rating != nil || note != nil {
            // Con la sola nota non si cancella un voto già dato (per esempio dalla schermata della pausa).
            let existing = log.sessions.first { $0.id == id }?.rating
            log.setReflection(id: id, rating: rating ?? existing, note: note)
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
