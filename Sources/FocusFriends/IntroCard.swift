import AppKit

/// Il bottone-avatar di un compagno: la testa in un cerchio, il nome sotto, un anello se è scelto.
final class CompanionButton: NSButton {
    let pet: Pet
    private let icon: NSImage?
    var isSelected = false { didSet { needsDisplay = true } }

    init(pet: Pet) {
        self.pet = pet
        self.icon = MenuController.menuIcon(for: pet, height: 120)
        super.init(frame: NSRect(x: 0, y: 0, width: 92, height: 104))
        isBordered = false
        setButtonType(.momentaryPushIn)
        title = pet.name
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 92).isActive = true
        heightAnchor.constraint(equalToConstant: 104).isActive = true
    }

    required init?(coder: NSCoder) { nil }

    // I pulsanti di AppKit sono "capovolti" (origine in alto): qui disegno con l'origine in basso.
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let circleBox = NSRect(x: bounds.midX - 34, y: bounds.maxY - 74, width: 68, height: 68)
        let circle = NSBezierPath(ovalIn: circleBox)
        NSColor(calibratedRed: 1.0, green: 0.99, blue: 0.94, alpha: 1).setFill()
        circle.fill()
        if let icon {
            NSGraphicsContext.saveGraphicsState()
            circle.addClip()
            let scale = circleBox.height / icon.size.height * 1.12
            let size = NSSize(width: icon.size.width * scale, height: icon.size.height * scale)
            let focus = pet.iconFocus
            let origin = NSPoint(x: circleBox.midX - size.width * focus, y: circleBox.midY - size.height * 0.52)
            icon.draw(in: NSRect(origin: origin, size: size), from: .zero, operation: .sourceOver, fraction: 1,
                      respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        }
        (isSelected ? Paper.accent : Paper.paperEdge).setStroke()
        circle.lineWidth = isSelected ? 3.5 : 1.5
        circle.stroke()

        let para = NSMutableParagraphStyle()
        para.alignment = .center
        (pet.name as NSString).draw(
            in: NSRect(x: 0, y: 2, width: bounds.width, height: 18),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: isSelected ? .semibold : .regular),
                .foregroundColor: isSelected ? Paper.ink : Paper.inkLight,
                .paragraphStyle: para,
            ]
        )
    }
}

/// La scheda di introduzione, alla prima apertura: come ti chiami e chi ti fa compagnia.
final class IntroCard: NSObject {
    /// 420, o di più se i bottoni dei compagni (92 l'uno, 14 di spazio, 28 di margine per lato) non ci stanno.
    private static let width: CGFloat = {
        let count = CGFloat(Pet.all.count)
        return max(420, count * 92 + (count - 1) * 14 + 56)
    }()

    private var panel: KeyablePanel?
    private var field: NSTextField?
    private var buttons: [CompanionButton] = []
    private var completion: ((_ name: String?, _ pet: Pet) -> Void)?
    private var initialPet = Pet.all[0]

    var isShowing: Bool { panel != nil }

    /// `completion` riceve il nome (o nil) e il compagno scelto. Esc o "Salta" valgono "nessun nome", con il
    /// compagno che c'era.
    func ask(currentPet: Pet, near petWindow: NSWindow?, completion: @escaping (_ name: String?, _ pet: Pet) -> Void) {
        guard panel == nil else { return }
        self.completion = completion
        initialPet = currentPet

        let card = PaperCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.appearance = NSAppearance(named: .aqua)

        let title = NSTextField(labelWithString: "Ciao! Benvenuto in FocusFriends")
        title.font = Paper.markerFont(24)
        title.textColor = Paper.ink

        let question = NSTextField(labelWithString: "Come ti chiami?")
        question.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        question.textColor = Paper.inkLight

        let field = NSTextField()
        field.placeholderString = "Il tuo nome"
        field.font = NSFont.systemFont(ofSize: 15)
        field.bezelStyle = .roundedBezel
        field.controlSize = .large
        field.focusRingType = .none
        field.target = self
        field.action = #selector(startPressed)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: Self.width - 56).isActive = true
        self.field = field

        let companion = NSTextField(labelWithString: "Chi ti fa compagnia?")
        companion.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        companion.textColor = Paper.inkLight

        buttons = Pet.all.map { pet in
            let button = CompanionButton(pet: pet)
            button.isSelected = pet.id == currentPet.id
            button.target = self
            button.action = #selector(companionPressed(_:))
            return button
        }
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.spacing = 14
        row.alignment = .top

        let hint = NSTextField(labelWithString: "Puoi cambiarli quando vuoi dal menu.")
        hint.font = NSFont.systemFont(ofSize: 12)
        hint.textColor = Paper.inkLight

        let skip = TextButton(title: "Salta")
        skip.target = self
        skip.action = #selector(skipPressed)
        let start = PillButton(title: "Iniziamo!", width: 150, height: 38)
        start.target = self
        start.action = #selector(startPressed)
        start.keyEquivalent = "\r"
        let bottom = NSStackView(views: [skip, start])
        bottom.orientation = .horizontal
        bottom.spacing = 18
        bottom.alignment = .centerY

        let stack = NSStackView(views: [title, question, field, companion, row, hint, bottom])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(16, after: title)
        stack.setCustomSpacing(18, after: field)
        stack.setCustomSpacing(4, after: row)
        stack.setCustomSpacing(18, after: hint)
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 20, right: 28)
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
        panel.onCancel = { [weak self] in self?.skipPressed() }

        let screen = (petWindow?.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        panel.setFrameOrigin(NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2 + 50))
        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 1
        }
        self.panel = panel
    }

    /// La scheda disegnata in un'immagine (per le anteprime).
    var contentView: NSView? { panel?.contentView }

    @objc private func companionPressed(_ sender: CompanionButton) {
        for button in buttons { button.isSelected = (button === sender) }
    }

    private var selectedPet: Pet {
        buttons.first(where: { $0.isSelected })?.pet ?? Pet.all[0]
    }

    @objc private func startPressed() {
        finish(name: Profile.clean(field?.stringValue), pet: selectedPet)
    }

    @objc private func skipPressed() {
        // "Salta" (o Esc): nessun nome, e resta il compagno che c'era (anche se ne avevi toccato un altro).
        finish(name: nil, pet: initialPet)
    }

    private func finish(name: String?, pet: Pet) {
        guard let panel else { return }
        self.panel = nil
        field = nil
        buttons = []
        let done = completion
        completion = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
        done?(name, pet)
    }
}
