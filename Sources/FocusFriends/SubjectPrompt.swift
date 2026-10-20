import AppKit

/// "Cosa studi adesso?": la scheda che compare quando si avvia un focus, per scrivere la materia
/// (o toccare una di quelle usate di recente). Si può anche saltare.
final class SubjectPrompt: NSObject {
    enum Choice {
        case start(subject: String?)
        case cancel
        /// La freccia: torna alla scheda del menu.
        case back
    }

    private static let width: CGFloat = 400
    private static let chipsPerRow = 3

    private var panel: KeyablePanel?
    private var field: NSTextField?
    private var completion: ((Choice) -> Void)?

    var isShowing: Bool { panel != nil }

    func ask(minutes: Int, recent: [String], prefill: String? = nil, lastNote: (subject: String?, note: String)? = nil, near petWindow: NSWindow?,
             completion: @escaping (Choice) -> Void) {
        // Se è già aperta: la porto davanti e basta.
        if let panel {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }
        self.completion = completion

        let card = PaperCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.appearance = NSAppearance(named: .aqua)   // carta chiara: anche il campo di testo, in modalità scura

        let title = NSTextField(labelWithString: "Cosa studi adesso?")
        title.font = Paper.markerFont(26)
        title.textColor = Paper.ink

        let subtitle = NSTextField(labelWithString: "Focus da \(minutes) minuti")
        subtitle.font = NSFont.systemFont(ofSize: 13)
        subtitle.textColor = Paper.inkLight

        let field = NSTextField()
        field.placeholderString = "La materia, per esempio Anatomia"
        if let prefill { field.stringValue = prefill }
        field.font = NSFont.systemFont(ofSize: 15)
        field.bezelStyle = .roundedBezel
        field.controlSize = .large
        field.focusRingType = .none
        field.target = self
        field.action = #selector(startPressed)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: Self.width - 56).isActive = true
        self.field = field

        // La freccia a sinistra del titolo: torna al menu senza chiudere tutto.
        let back = NSButton(image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Torna al menu") ?? NSImage(),
                            target: self, action: #selector(backPressed))
        back.isBordered = false
        back.imagePosition = .imageOnly
        back.contentTintColor = Paper.inkLight
        back.toolTip = "Torna al menu"
        back.translatesAutoresizingMaskIntoConstraints = false
        back.widthAnchor.constraint(equalToConstant: 26).isActive = true
        back.heightAnchor.constraint(equalToConstant: 26).isActive = true
        let titleRow = NSStackView(views: [back, title])
        titleRow.orientation = .horizontal
        titleRow.spacing = 4
        titleRow.alignment = .centerY

        var views: [NSView] = [titleRow, subtitle, field]
        if !recent.isEmpty {
            let hint = NSTextField(labelWithString: "Tocca una materia recente per iniziare subito")
            hint.font = NSFont.systemFont(ofSize: 12)
            hint.textColor = Paper.inkLight
            views.append(hint)
            for rowStart in stride(from: 0, to: min(recent.count, 6), by: Self.chipsPerRow) {
                let rowItems = recent[rowStart..<min(rowStart + Self.chipsPerRow, min(recent.count, 6))]
                let chips: [NSView] = rowItems.map { name in
                    let chip = ChipButton(title: name)
                    chip.target = self
                    chip.action = #selector(chipPressed(_:))
                    return chip
                }
                let row = NSStackView(views: chips)
                row.orientation = .horizontal
                row.spacing = 8
                views.append(row)
            }
        }

        if let lastNote {
            // "L'ultima volta su Anatomia: nervi cranici": il filo con la volta prima.
            let text = (lastNote.subject.map { "L'ultima volta su \($0): " } ?? "L'ultima volta: ") + lastNote.note
            let label = NSTextField(labelWithString: text)
            label.font = NSFont.systemFont(ofSize: 12)
            label.textColor = Paper.inkLight
            label.lineBreakMode = .byTruncatingTail
            label.widthAnchor.constraint(lessThanOrEqualToConstant: Self.width - 56).isActive = true
            views.append(label)
        }

        let skip = TextButton(title: "Senza materia")
        skip.target = self
        skip.action = #selector(skipPressed)
        let start = PillButton(title: "Inizia", width: 130, height: 36)
        start.target = self
        start.action = #selector(startPressed)
        start.keyEquivalent = "\r"
        let buttons = NSStackView(views: [skip, start])
        buttons.orientation = .horizontal
        buttons.spacing = 18
        buttons.alignment = .centerY
        views.append(buttons)

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(2, after: titleRow)
        stack.setCustomSpacing(16, after: subtitle)
        stack.setCustomSpacing(14, after: field)
        stack.setCustomSpacing(18, after: views[views.count - 2])
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 28, bottom: 20, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: Self.width),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            buttons.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -28),
        ])
        card.layoutSubtreeIfNeeded()
        let size = card.fittingSize

        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = card
        panel.appearance = NSAppearance(named: .aqua)
        panel.onCancel = { [weak self] in self?.finish(.cancel) }

        let screen = (petWindow?.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        panel.setFrameOrigin(NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2 + 60))
        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }
        self.panel = panel
    }

    @objc private func startPressed() {
        finish(.start(subject: Subject.clean(field?.stringValue)))
    }

    @objc private func backPressed() {
        finish(.back)
    }

    @objc private func skipPressed() {
        finish(.start(subject: nil))
    }

    @objc private func chipPressed(_ sender: NSButton) {
        finish(.start(subject: Subject.clean(sender.title)))
    }

    private func finish(_ choice: Choice) {
        guard let panel else { return }
        self.panel = nil
        field = nil
        let done = completion
        completion = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
        done?(choice)
    }
}
