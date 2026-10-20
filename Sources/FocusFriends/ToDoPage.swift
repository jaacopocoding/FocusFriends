import AppKit

/// Quello che la pagina «Da fare» della scheda riceve: le voci già raggruppate e un po' di conti.
struct ToDoCardState {
    var sections: [ToDoSection] = []
    var done: [ToDoItem] = []
    var openCount = 0
    var urgentCount = 0
    /// Oggi, «AAAA-MM-GG».
    var today = ""
    /// Le materie usate di recente, per sceglierne una con un tocco.
    var recentSubjects: [String] = []
}

/// Cosa succede quando si tocca qualcosa nella pagina.
struct ToDoPageActions {
    var back: () -> Void
    var add: (_ text: String, _ due: String?, _ subject: String?) -> Void
    var toggle: (UUID) -> Void
    var remove: (UUID) -> Void
    var startFocus: (UUID) -> Void
}

/// Un pulsante disegnato a mano (origine in alto), come quelli della scheda.
private final class ToDoButton: NSButton {
    var drawer: ((NSRect, _ pressed: Bool, _ hovered: Bool) -> Void)?
    var onClick: (() -> Void)?
    private var isHovered = false

    init(frame: NSRect, label: String) {
        super.init(frame: frame)
        isBordered = false
        setButtonType(.momentaryPushIn)
        title = ""
        target = self
        action = #selector(fire)
        setAccessibilityLabel(label)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }
    @objc private func fire() { onClick?() }
    override func draw(_ dirtyRect: NSRect) { drawer?(bounds, isHighlighted, isHovered) }
}

/// Una vista con l'origine in alto (per il foglio che scorre).
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Il campo dove si scrive: una pillola con il bordo della carta.
private final class InputPill: NSView {
    override var isFlipped: Bool { true }
    var isActive = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.white.withAlphaComponent(0.6).setFill()
        shape.fill()
        (isActive ? Paper.accent : Paper.paperEdge).setStroke()
        shape.lineWidth = isActive ? 1.5 : 1
        shape.stroke()
    }
}

/// Una riga della lista: il cerchio per segnarla fatta, il testo, la materia e la scadenza; sotto il mouse compaiono
/// «Inizia un focus» e «Togli».
private final class ToDoRowView: NSView {
    override var isFlipped: Bool { true }

    static let singleHeight: CGFloat = 32
    static let doubleHeight: CGFloat = 42

    private let item: ToDoItem
    private let today: String
    private let check: ToDoButton
    private let play: ToDoButton?
    private let trash: ToDoButton
    private var hovered = false { didSet { play?.isHidden = !hovered; trash.isHidden = !hovered; needsDisplay = true } }

    static func height(for item: ToDoItem) -> CGFloat { item.subject == nil ? singleHeight : doubleHeight }

    init(item: ToDoItem, today: String, width: CGFloat, actions: ToDoPageActions) {
        self.item = item
        self.today = today
        let height = Self.height(for: item)
        check = ToDoButton(frame: NSRect(x: 0, y: 0, width: 32, height: height), label: item.isDone ? "Rimetti da fare" : "Segna come fatta")
        trash = ToDoButton(frame: NSRect(x: width - 28, y: (height - 26) / 2, width: 26, height: 26), label: "Togli dalla lista")
        if item.isDone {
            play = nil
        } else {
            play = ToDoButton(frame: NSRect(x: width - 56, y: (height - 26) / 2, width: 26, height: 26), label: "Inizia un focus")
        }
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let done = item.isDone
        check.drawer = { rect, pressed, hovered in
            let circle = NSRect(x: 3, y: rect.midY - 10, width: 20, height: 20)
            let shape = NSBezierPath(ovalIn: circle.insetBy(dx: 1, dy: 1))
            if done {
                Paper.accent.setFill()
                shape.fill()
                Self.drawSymbol("checkmark", size: 10, color: .white, centeredIn: circle)
            } else {
                (pressed ? Paper.accent.withAlphaComponent(0.25) : NSColor.white.withAlphaComponent(0.6)).setFill()
                shape.fill()
                (hovered || pressed ? Paper.accent : Paper.inkLight).setStroke()
                shape.lineWidth = 1.6
                shape.stroke()
            }
        }
        check.onClick = { actions.toggle(item.id) }
        addSubview(check)

        trash.drawer = { rect, pressed, hovered in
            Self.drawSymbol("xmark", size: 11, color: hovered || pressed ? FocusPalette.danger : Paper.inkLight, centeredIn: rect)
        }
        trash.onClick = { actions.remove(item.id) }
        trash.isHidden = true
        addSubview(trash)

        if let play {
            play.drawer = { rect, pressed, hovered in
                let shape = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
                (pressed ? Paper.accentPressed : hovered ? Paper.accent : Paper.accent.withAlphaComponent(0.85)).setFill()
                shape.fill()
                Self.drawSymbol("play.fill", size: 9, color: .white, centeredIn: rect.offsetBy(dx: 0.5, dy: 0))
            }
            play.onClick = { actions.startFocus(item.id) }
            play.isHidden = true
            addSubview(play)
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { nil }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    private static func drawSymbol(_ name: String, size: CGFloat, color: NSColor, centeredIn box: NSRect) {
        guard let image = Paper.symbolImage(name, size: size, color: color) else { return }
        let s = image.size
        image.draw(in: NSRect(x: box.midX - s.width / 2, y: box.midY - s.height / 2, width: s.width, height: s.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            Paper.ink.withAlphaComponent(0.05).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
        let hasSubject = item.subject != nil
        let dueText = item.due.map { ToDoDay.label(due: $0, today: today) }
        let dueWidth = dueText.map { ($0 as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11.5, weight: .medium)]).width + 10 } ?? 4
        let textWidth = bounds.width - 32 - (hovered ? 62 : dueWidth)
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: item.isDone ? Paper.inkLight : Paper.ink, .paragraphStyle: para,
        ]
        if item.isDone { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        let textY: CGFloat = hasSubject ? 5 : (bounds.height - 17) / 2
        (item.text as NSString).draw(in: NSRect(x: 32, y: textY, width: textWidth, height: 17), withAttributes: attributes)
        if let subject = item.subject {
            Paper.color(forSubject: subject).setFill()
            NSBezierPath(ovalIn: NSRect(x: 33, y: 26, width: 8, height: 8)).fill()
            (subject as NSString).draw(in: NSRect(x: 46, y: 22, width: textWidth - 14, height: 15),
                                       withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: Paper.inkLight, .paragraphStyle: para])
        }
        if !hovered, let due = item.due, let label = dueText {
            let overdue = !item.isDone && (ToDoDay.days(from: today, to: due) ?? 0) < 0
            let alignment = NSMutableParagraphStyle()
            alignment.alignment = .right
            (label as NSString).draw(
                in: NSRect(x: bounds.width - dueWidth - 2, y: (bounds.height - 15) / 2, width: dueWidth, height: 15),
                withAttributes: [.font: NSFont.systemFont(ofSize: 11.5, weight: overdue ? .medium : .regular),
                                 .foregroundColor: overdue ? FocusPalette.danger : Paper.inkLight, .paragraphStyle: alignment])
        }
    }
}

/// La pagina «Da fare» della scheda: il campo per aggiungere (con la scadenza e la materia, facoltative) e la lista.
final class ToDoPageView: NSView, NSTextFieldDelegate {
    static let pad: CGFloat = 16
    private static let maxListHeight: CGFloat = 420

    override var isFlipped: Bool { true }

    private var state: ToDoCardState
    private let actions: ToDoPageActions
    private let field = NSTextField()
    private var due: String?
    private var subject: String?
    private var picking = false
    private var showDone = false
    private var lastTextEmpty = true
    private var editingNow = false
    private var listScroll: CGFloat = 0
    private var listView: NSScrollView?
    private weak var pill: InputPill?
    private(set) var height: CGFloat = 0
    /// Chiamata quando la pagina cambia altezza (compaiono le scelte, la lista cresce).
    var onHeight: ((CGFloat) -> Void)?

    private var inner: CGFloat { frame.width - 2 * Self.pad }

    init(width: CGFloat, state: ToDoCardState, actions: ToDoPageActions) {
        self.state = state
        self.actions = actions
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        appearance = NSAppearance(named: .aqua)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 13)
        field.textColor = Paper.ink
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.placeholderAttributedString = NSAttributedString(
            string: "Aggiungi una cosa…", attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: FocusPalette.postitHint])
        field.delegate = self
        field.target = self
        field.action = #selector(submit)
        rebuild()
    }

    required init?(coder: NSCoder) { nil }

    func update(_ new: ToDoCardState) {
        state = new
        rebuild()
    }

    /// Mette il cursore nel campo (per quando la pagina si apre).
    func focusField() {
        window?.makeFirstResponder(field)
    }

    // MARK: - Costruzione

    private func rebuild() {
        let editing = field.currentEditor() != nil
        editingNow = editing
        if let scroll = listView { listScroll = scroll.contentView.bounds.origin.y }
        for view in subviews { view.removeFromSuperview() }
        listView = nil
        let pad = Self.pad
        var y: CGFloat = 14

        // Intestazione con la freccia indietro
        let back = ToDoButton(frame: NSRect(x: pad - 6, y: y, width: 36, height: 30), label: "Torna alla scheda")
        back.drawer = { rect, pressed, hovered in
            if let image = Paper.symbolImage("chevron.left", size: 15, color: hovered || pressed ? Paper.ink : Paper.inkLight) {
                let size = image.size
                image.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height),
                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
        }
        back.onClick = { [actions] in actions.back() }
        addSubview(back)
        let title = NSTextField(labelWithString: "Da fare")
        title.font = Paper.markerFont(20)
        title.textColor = Paper.ink
        title.frame = NSRect(x: pad + 30, y: y + 2, width: inner - 30, height: 26)
        addSubview(title)
        y += 42

        y = addInput(y: y)
        if !field.stringValue.isEmpty { y = addChoices(y: y) }
        y += 6
        y = addList(y: y)
        height = y + 14
        setFrameSize(NSSize(width: frame.width, height: height))
        onHeight?(height)

        if editing {
            window?.makeFirstResponder(field)
            field.currentEditor()?.selectedRange = NSRange(location: field.stringValue.utf16.count, length: 0)
        }
    }

    private func addInput(y: CGFloat) -> CGFloat {
        let pill = InputPill(frame: NSRect(x: Self.pad, y: y, width: inner, height: 38))
        pill.isActive = editingNow
        field.frame = NSRect(x: 16, y: 9, width: inner - 16 - 44, height: 20)
        pill.addSubview(field)
        let plus = ToDoButton(frame: NSRect(x: inner - 34, y: 5, width: 28, height: 28), label: "Aggiungi")
        plus.drawer = { rect, pressed, hovered in
            let shape = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            (pressed ? Paper.accentPressed : hovered ? Paper.accent : Paper.accent.withAlphaComponent(0.9)).setFill()
            shape.fill()
            if let image = Paper.symbolImage("plus", size: 13, color: .white) {
                let s = image.size
                image.draw(in: NSRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height),
                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
        }
        plus.onClick = { [weak self] in self?.submit() }
        pill.addSubview(plus)
        addSubview(pill)
        self.pill = pill
        return y + 38
    }

    /// Le scelte facoltative sotto il campo: per quando, e per quale materia.
    private func addChoices(y start: CGFloat) -> CGFloat {
        var y = start + 8
        y = addCaption("Per quando", y: y)
        let tomorrow = ToDoDay.adding(days: 1, to: state.today)
        let nextWeek = ToDoDay.adding(days: 7, to: state.today)
        var dueChips: [(String, Bool, () -> Void)] = [
            ("Oggi", due == state.today, { [weak self] in self?.pickDue(self?.state.today) }),
            ("Domani", due != nil && due == tomorrow, { [weak self] in self?.pickDue(tomorrow) }),
            ("Fra una settimana", due != nil && due == nextWeek, { [weak self] in self?.pickDue(nextWeek) }),
        ]
        let custom = due != nil && due != state.today && due != tomorrow && due != nextWeek
        dueChips.append((custom ? ToDoDay.label(due: due ?? "", today: state.today) : "Scegli…", custom || picking, { [weak self] in
            guard let self else { return }
            if self.picking { self.picking = false } else { self.picking = true }
            self.rebuild()
        }))
        y = addChips(dueChips, y: y)
        if picking {
            let picker = NSDatePicker(frame: NSRect(x: Self.pad, y: y + 2, width: 139, height: 148))
            picker.datePickerStyle = .clockAndCalendar
            picker.datePickerElements = .yearMonthDay
            picker.appearance = NSAppearance(named: .aqua)
            picker.locale = Locale(identifier: "it_IT")
            picker.dateValue = Date()
            picker.minDate = Calendar.current.startOfDay(for: Date())
            picker.target = self
            picker.action = #selector(datePicked(_:))
            addSubview(picker)
            y += 2 + 148 + 4
        }
        if !state.recentSubjects.isEmpty {
            y = addCaption("Materia", y: y + 4)
            y = addChips(state.recentSubjects.prefix(6).map { name in
                (name, subject.map { Subject.key($0) == Subject.key(name) } ?? false, { [weak self] in
                    guard let self else { return }
                    self.subject = (self.subject.map { Subject.key($0) == Subject.key(name) } ?? false) ? nil : name
                    self.rebuild()
                })
            }, y: y)
        }
        return y + 2
    }

    private func addCaption(_ text: String, y: CGFloat) -> CGFloat {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11.5)
        label.textColor = Paper.inkLight
        label.frame = NSRect(x: Self.pad + 4, y: y, width: inner, height: 15)
        addSubview(label)
        return y + 19
    }

    /// Tocchi in fila che vanno a capo quando finisce il posto.
    private func addChips(_ chips: [(title: String, selected: Bool, action: () -> Void)], y start: CGFloat) -> CGFloat {
        var x = Self.pad
        var y = start
        let font = NSFont.systemFont(ofSize: 12.5)
        for chip in chips {
            let width = min((chip.title as NSString).size(withAttributes: [.font: font]).width + 24, inner)
            if x + width > Self.pad + inner + 0.5 {
                x = Self.pad
                y += 32
            }
            let button = ToDoButton(frame: NSRect(x: x, y: y, width: width, height: 26), label: chip.title)
            button.drawer = { rect, pressed, hovered in
                let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: rect.height / 2, yRadius: rect.height / 2)
                (chip.selected ? (pressed ? Paper.accentPressed : Paper.accent)
                    : pressed ? Paper.accent.withAlphaComponent(0.3) : hovered ? Paper.accent.withAlphaComponent(0.14) : Paper.paper).setFill()
                shape.fill()
                (chip.selected ? Paper.accent : Paper.paperEdge).setStroke()
                shape.lineWidth = 1
                shape.stroke()
                let para = NSMutableParagraphStyle()
                para.alignment = .center
                para.lineBreakMode = .byTruncatingTail
                (chip.title as NSString).draw(in: NSRect(x: rect.minX + 6, y: rect.midY - 8, width: rect.width - 12, height: 16),
                                              withAttributes: [.font: font, .foregroundColor: chip.selected ? NSColor.white : Paper.ink, .paragraphStyle: para])
            }
            button.onClick = chip.action
            addSubview(button)
            x += width + 6
        }
        return y + 26 + 6
    }

    // MARK: - La lista

    /// Il foglio che scorre: i gruppi con le loro righe, il caso «niente da fare» e le voci fatte.
    private func makeDocument(width: CGFloat) -> FlippedView {
        let doc = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: 0))
        var y: CGFloat = 0
        let hasOpen = !state.sections.isEmpty
        for section in state.sections {
            let header = NSTextField(labelWithString: section.group.title)
            header.font = Paper.markerFont(15)
            header.textColor = section.group == .overdue ? FocusPalette.danger : Paper.ink
            header.frame = NSRect(x: 2, y: y + 6, width: width - 4, height: 20)
            doc.addSubview(header)
            y += 28
            for item in section.items {
                let row = ToDoRowView(item: item, today: state.today, width: width, actions: rowActions())
                row.frame.origin = NSPoint(x: 0, y: y)
                doc.addSubview(row)
                y += row.frame.height
            }
        }
        if !hasOpen {
            let icon = NSImageView(image: Paper.symbolImage("checklist", size: 30, color: NSColor(calibratedRed: 0.72, green: 0.60, blue: 0.45, alpha: 1)) ?? NSImage())
            icon.frame = NSRect(x: (width - 40) / 2, y: y + 14, width: 40, height: 36)
            doc.addSubview(icon)
            let head = NSTextField(labelWithString: state.done.isEmpty ? "Tutto in ordine" : "Tutto fatto")
            head.font = Paper.markerFont(18)
            head.textColor = Paper.ink
            head.alignment = .center
            head.frame = NSRect(x: 0, y: y + 54, width: width, height: 24)
            doc.addSubview(head)
            let body = NSTextField(wrappingLabelWithString: "Qui puoi segnare le cose da ricordare, con o senza data.")
            body.font = NSFont.systemFont(ofSize: 12.5)
            body.textColor = Paper.inkLight
            body.alignment = .center
            body.frame = NSRect(x: 12, y: y + 80, width: width - 24, height: 36)
            doc.addSubview(body)
            y += 124
        }
        if !state.done.isEmpty {
            y += 8
            let toggle = ToDoButton(frame: NSRect(x: 0, y: y, width: width, height: 28), label: showDone ? "Nascondi le fatte" : "Mostra le fatte")
            let count = state.done.count
            let open = showDone
            toggle.drawer = { rect, pressed, hovered in
                if let image = Paper.symbolImage(open ? "chevron.down" : "chevron.right", size: 11, color: Paper.inkLight) {
                    let s = image.size
                    image.draw(in: NSRect(x: rect.minX + 6, y: rect.midY - s.height / 2, width: s.width, height: s.height),
                               from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
                ("Fatte · \(count)" as NSString).draw(in: NSRect(x: rect.minX + 24, y: rect.midY - 8.5, width: rect.width - 30, height: 17),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 12.5, weight: .medium), .foregroundColor: hovered || pressed ? Paper.ink : Paper.inkLight])
            }
            toggle.onClick = { [weak self] in
                guard let self else { return }
                self.showDone.toggle()
                self.rebuild()
            }
            doc.addSubview(toggle)
            y += 28
            if showDone {
                for item in state.done {
                    let row = ToDoRowView(item: item, today: state.today, width: width, actions: rowActions())
                    row.frame.origin = NSPoint(x: 0, y: y)
                    doc.addSubview(row)
                    y += row.frame.height
                }
            }
        }
        doc.setFrameSize(NSSize(width: width, height: y))
        return doc
    }

    private func addList(y start: CGFloat) -> CGFloat {
        var doc = makeDocument(width: inner)
        let y = doc.frame.height
        // Mentre si scrive (con le scelte aperte) la lista lascia più posto alla pagina.
        let limit = field.stringValue.isEmpty ? Self.maxListHeight : Self.maxListHeight - 170
        let visible = min(y, limit)
        let scroll = NSScrollView(frame: NSRect(x: Self.pad, y: start, width: inner, height: visible))
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = y > limit
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        // Con la barra a vista il foglio è un po' più stretto: le righe si rifanno a quella misura.
        scroll.tile()
        let width = scroll.contentSize.width
        if abs(width - inner) > 0.5 { doc = makeDocument(width: width) }
        scroll.documentView = doc
        addSubview(scroll)
        listView = scroll
        let maxScroll = max(doc.frame.height - visible, 0)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(listScroll, maxScroll)))
        scroll.reflectScrolledClipView(scroll.contentView)
        return start + visible
    }

    private func rowActions() -> ToDoPageActions { actions }

    // MARK: - Azioni

    private func pickDue(_ day: String?) {
        due = (due == day) ? nil : day
        picking = false
        rebuild()
    }

    @objc private func datePicked(_ sender: NSDatePicker) {
        due = ToDoDay.string(for: sender.dateValue, calendar: ToDoDay.calendar())
        picking = false
        rebuild()
    }

    @objc private func submit() {
        let text = field.stringValue
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let chosenDue = due, chosenSubject = subject
        field.stringValue = ""
        lastTextEmpty = true
        due = nil
        subject = nil
        picking = false
        listScroll = 0
        actions.add(text, chosenDue, chosenSubject)
    }

    // MARK: - Il campo

    func controlTextDidBeginEditing(_ obj: Notification) { pill?.isActive = true }
    func controlTextDidEndEditing(_ obj: Notification) { pill?.isActive = false }

    func controlTextDidChange(_ obj: Notification) {
        if field.stringValue.count > ToDoText.maxLength {
            field.stringValue = String(field.stringValue.prefix(ToDoText.maxLength))
        }
        let empty = field.stringValue.isEmpty
        if empty != lastTextEmpty {
            lastTextEmpty = empty
            // Compaiono (o spariscono) le scelte: la pagina si ricostruisce e il cursore resta dov'è.
            DispatchQueue.main.async { [weak self] in self?.rebuild() }
        }
    }
}
