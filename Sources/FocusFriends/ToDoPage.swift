import AppKit

/// Quello che la pagina «Da fare» della scheda riceve: le voci già raggruppate e un po' di conti.
struct ToDoCardState {
    var sections: [ToDoSection] = []
    var done: [ToDoItem] = []
    var openCount = 0
    /// Oggi, «AAAA-MM-GG».
    var today = ""
    /// Le materie usate di recente, per sceglierne una con un tocco.
    var recentSubjects: [String] = []
}

/// Cosa succede quando si tocca qualcosa nella pagina.
struct ToDoPageActions {
    var back: () -> Void
    var add: (_ text: String, _ due: String?, _ subject: String?) -> Void
    var update: (_ id: UUID, _ text: String, _ due: String?, _ subject: String?) -> Void
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

/// Un simbolo di sistema al centro di un rettangolo.
private func drawSymbol(_ name: String, size: CGFloat, color: NSColor, centeredIn box: NSRect) {
    guard let image = Paper.symbolImage(name, size: size, color: color) else { return }
    let s = image.size
    image.draw(in: NSRect(x: box.midX - s.width / 2, y: box.midY - s.height / 2, width: s.width, height: s.height),
               from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}

/// Una riga della lista: il cerchio per segnarla fatta, il testo (fino a due righe), la materia e la scadenza. Toccando il
/// testo si modifica; sotto il mouse compaiono «Inizia un focus» e «Togli».
private final class ToDoRowView: NSView {
    override var isFlipped: Bool { true }

    private static let textFont = NSFont.systemFont(ofSize: 13)
    private static let lineHeight: CGFloat = 16
    /// Largo quanto serve per la scadenza o, sotto il mouse, per i due pulsanti.
    private static let sideWidth: CGFloat = 66

    private let item: ToDoItem
    private let today: String
    private let textHeight: CGFloat
    private let check: ToDoButton
    private let edit: ToDoButton?
    private let play: ToDoButton?
    private let trash: ToDoButton
    private var hovered = false { didSet { play?.isHidden = !hovered; trash.isHidden = !hovered; needsDisplay = true } }

    private static func textWidth(rowWidth: CGFloat) -> CGFloat { rowWidth - 32 - sideWidth }

    private static func measuredTextHeight(_ item: ToDoItem, rowWidth: CGFloat) -> CGFloat {
        let box = (item.text as NSString).boundingRect(with: NSSize(width: textWidth(rowWidth: rowWidth), height: .greatestFiniteMagnitude),
                                                       options: [.usesLineFragmentOrigin], attributes: [.font: textFont])
        return min(ceil(box.height), lineHeight * 2 + 2)
    }

    static func height(for item: ToDoItem, rowWidth: CGFloat) -> CGFloat {
        max(32, 8 + measuredTextHeight(item, rowWidth: rowWidth) + (item.subject == nil ? 0 : 17) + 7)
    }

    init(item: ToDoItem, today: String, width: CGFloat, actions: ToDoPageActions, onEdit: @escaping () -> Void) {
        self.item = item
        self.today = today
        textHeight = Self.measuredTextHeight(item, rowWidth: width)
        let height = Self.height(for: item, rowWidth: width)
        check = ToDoButton(frame: NSRect(x: 0, y: 0, width: 32, height: height), label: item.isDone ? "Rimetti da fare" : "Segna come fatta")
        trash = ToDoButton(frame: NSRect(x: width - 28, y: (height - 26) / 2, width: 26, height: 26), label: "Togli dalla lista")
        if item.isDone {
            play = nil
            edit = nil
        } else {
            play = ToDoButton(frame: NSRect(x: width - 56, y: (height - 26) / 2, width: 26, height: 26), label: "Inizia un focus")
            edit = ToDoButton(frame: NSRect(x: 32, y: 0, width: width - 32 - Self.sideWidth + 6, height: height), label: "Modifica: \(item.text)")
        }
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let done = item.isDone
        check.drawer = { rect, pressed, hovered in
            let circle = NSRect(x: 3, y: rect.midY - 10, width: 20, height: 20)
            let shape = NSBezierPath(ovalIn: circle.insetBy(dx: 1, dy: 1))
            if done {
                Paper.accent.setFill()
                shape.fill()
                drawSymbol("checkmark", size: 10, color: .white, centeredIn: circle)
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

        // Il testo si tocca per modificare (le voci fatte no): un pulsante trasparente sopra il disegno.
        if let edit {
            edit.drawer = { _, _, _ in }
            edit.onClick = onEdit
            addSubview(edit)
        }

        trash.drawer = { rect, pressed, hovered in
            drawSymbol("xmark", size: 11, color: hovered || pressed ? FocusPalette.danger : Paper.inkLight, centeredIn: rect)
        }
        trash.onClick = { actions.remove(item.id) }
        trash.isHidden = true
        addSubview(trash)

        if let play {
            play.drawer = { rect, pressed, hovered in
                let shape = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
                (pressed ? Paper.accentPressed : hovered ? Paper.accent : Paper.accent.withAlphaComponent(0.85)).setFill()
                shape.fill()
                drawSymbol("play.fill", size: 9, color: .white, centeredIn: rect.offsetBy(dx: 0.5, dy: 0))
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

    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            Paper.ink.withAlphaComponent(0.05).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
        let width = Self.textWidth(rowWidth: bounds.width)
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        var attributes: [NSAttributedString.Key: Any] = [
            .font: Self.textFont, .foregroundColor: item.isDone ? Paper.inkLight : Paper.ink, .paragraphStyle: para,
        ]
        if item.isDone { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        let hasSubject = item.subject != nil
        let blockHeight = textHeight + (hasSubject ? 17 : 0)
        let top = (bounds.height - blockHeight) / 2
        (item.text as NSString).draw(with: NSRect(x: 32, y: top, width: width, height: textHeight),
                                     options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
        if let subject = item.subject {
            let line = NSMutableParagraphStyle()
            line.lineBreakMode = .byTruncatingTail
            Paper.color(forSubject: subject).setFill()
            NSBezierPath(ovalIn: NSRect(x: 33, y: top + textHeight + 6, width: 8, height: 8)).fill()
            (subject as NSString).draw(in: NSRect(x: 46, y: top + textHeight + 2, width: width - 14, height: 15),
                                       withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: Paper.inkLight, .paragraphStyle: line])
        }
        if !hovered, let due = item.due {
            let label = ToDoDay.label(due: due, today: today)
            let overdue = !item.isDone && (ToDoDay.days(from: today, to: due) ?? 0) < 0
            let alignment = NSMutableParagraphStyle()
            alignment.alignment = .right
            (label as NSString).draw(
                in: NSRect(x: bounds.width - Self.sideWidth - 2, y: (bounds.height - 15) / 2, width: Self.sideWidth, height: 15),
                withAttributes: [.font: NSFont.systemFont(ofSize: 11.5, weight: overdue ? .medium : .regular),
                                 .foregroundColor: overdue ? FocusPalette.danger : Paper.inkLight, .paragraphStyle: alignment])
        }
    }
}

/// La pagina «Da fare» della scheda: la lista (con il «+» in alto) e, da lì, la pagina «Nuova cosa» / «Modifica» con il nome,
/// la scadenza e la materia (facoltative).
final class ToDoPageView: NSView, NSTextFieldDelegate {
    static let pad: CGFloat = 16
    private static let maxListHeight: CGFloat = 420

    override var isFlipped: Bool { true }

    /// La lista, oppure il modulo: per una cosa nuova (`nil`) o per modificarne una.
    private enum Mode: Equatable {
        case list
        case form(editing: UUID?)
    }

    private var state: ToDoCardState
    private let actions: ToDoPageActions
    private var mode = Mode.list
    private let nameField = NSTextField()
    private let subjectField = NSTextField()
    private var due: String?
    private var picking = false
    private var showDone = false
    /// Quale chip della materia è acceso adesso (per ricostruire solo quando cambia).
    private var shownSubjectChip: String?
    /// Il campo che si sta scrivendo, per ritrovarlo dopo aver ricostruito la pagina.
    private var editingField: NSTextField?
    private var listScroll: CGFloat = 0
    private var listView: NSScrollView?
    private weak var namePill: InputPill?
    private weak var subjectPill: InputPill?
    private(set) var height: CGFloat = 0
    /// Chiamata quando la pagina cambia altezza.
    var onHeight: ((CGFloat) -> Void)?

    private var inner: CGFloat { frame.width - 2 * Self.pad }

    init(width: CGFloat, state: ToDoCardState, actions: ToDoPageActions) {
        self.state = state
        self.actions = actions
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        appearance = NSAppearance(named: .aqua)
        configure(nameField, placeholder: "Per esempio: ripassare il capitolo 3")
        configure(subjectField, placeholder: "Scrivila o toccane una")
        rebuild()
    }

    required init?(coder: NSCoder) { nil }

    private func configure(_ field: NSTextField, placeholder: String) {
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 13)
        field.textColor = Paper.ink
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: FocusPalette.postitHint])
        field.delegate = self
        field.target = self
        field.action = #selector(save)
    }

    func update(_ new: ToDoCardState) {
        state = new
        rebuild()
    }

    // MARK: - Costruzione

    private func rebuild() {
        if let current = [nameField, subjectField].first(where: { $0.currentEditor() != nil }) { editingField = current }
        if let scroll = listView { listScroll = scroll.contentView.bounds.origin.y }
        for view in subviews { view.removeFromSuperview() }
        listView = nil
        var y: CGFloat = 14
        switch mode {
        case .list:
            y = buildList(y: y)
        case .form(let editing):
            y = buildForm(y: y, editing: editing)
        }
        height = y + 14
        setFrameSize(NSSize(width: frame.width, height: height))
        onHeight?(height)
        if let field = editingField {
            editingField = nil
            window?.makeFirstResponder(field)
            field.currentEditor()?.selectedRange = NSRange(location: field.stringValue.utf16.count, length: 0)
        }
    }

    /// La freccia indietro e il titolo; `trailing` è un pulsante a destra (il «+»).
    private func addHeader(title: String, backLabel: String, y: CGFloat, back: @escaping () -> Void) {
        let pad = Self.pad
        let button = ToDoButton(frame: NSRect(x: pad - 6, y: y, width: 36, height: 30), label: backLabel)
        button.drawer = { rect, pressed, hovered in
            drawSymbol("chevron.left", size: 15, color: hovered || pressed ? Paper.ink : Paper.inkLight, centeredIn: rect)
        }
        button.onClick = back
        addSubview(button)
        let label = NSTextField(labelWithString: title)
        label.font = Paper.markerFont(20)
        label.textColor = Paper.ink
        label.frame = NSRect(x: pad + 30, y: y + 2, width: inner - 30 - 36, height: 26)
        addSubview(label)
    }

    // MARK: - La lista

    private func buildList(y start: CGFloat) -> CGFloat {
        addHeader(title: "Da fare", backLabel: "Torna alla scheda", y: start) { [actions] in actions.back() }
        let plus = ToDoButton(frame: NSRect(x: frame.width - Self.pad - 30, y: start, width: 30, height: 30), label: "Nuova cosa")
        plus.drawer = { rect, pressed, hovered in
            let shape = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            (pressed ? Paper.accentPressed : hovered ? Paper.accent : Paper.accent.withAlphaComponent(0.9)).setFill()
            shape.fill()
            drawSymbol("plus", size: 14, color: .white, centeredIn: rect)
        }
        plus.onClick = { [weak self] in self?.openForm(editing: nil) }
        addSubview(plus)
        return addList(y: start + 42 + 2)
    }

    /// Il foglio che scorre: i gruppi con le loro righe, il caso «niente da fare» e le voci fatte.
    private func makeDocument(width: CGFloat) -> FlippedView {
        let doc = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: 0))
        var y: CGFloat = 0
        func addRow(_ item: ToDoItem) {
            let row = ToDoRowView(item: item, today: state.today, width: width, actions: actions, onEdit: { [weak self] in self?.openForm(editing: item) })
            row.frame.origin = NSPoint(x: 0, y: y)
            doc.addSubview(row)
            y += row.frame.height
        }
        for section in state.sections {
            let header = NSTextField(labelWithString: section.group.title)
            header.font = Paper.markerFont(15)
            header.textColor = section.group == .overdue ? FocusPalette.danger : Paper.ink
            header.frame = NSRect(x: 2, y: y + 6, width: width - 4, height: 20)
            doc.addSubview(header)
            y += 28
            section.items.forEach(addRow)
        }
        if state.sections.isEmpty {
            let icon = NSImageView(image: Paper.symbolImage("checklist", size: 30, color: NSColor(calibratedRed: 0.72, green: 0.60, blue: 0.45, alpha: 1)) ?? NSImage())
            icon.frame = NSRect(x: (width - 40) / 2, y: y + 14, width: 40, height: 36)
            doc.addSubview(icon)
            let head = NSTextField(labelWithString: state.done.isEmpty ? "Tutto in ordine" : "Tutto fatto")
            head.font = Paper.markerFont(18)
            head.textColor = Paper.ink
            head.alignment = .center
            head.frame = NSRect(x: 0, y: y + 54, width: width, height: 24)
            doc.addSubview(head)
            let body = NSTextField(wrappingLabelWithString: "Tocca il «+» per segnare una cosa da ricordare, con o senza data.")
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
                drawSymbol(open ? "chevron.down" : "chevron.right", size: 11, color: Paper.inkLight, centeredIn: NSRect(x: rect.minX + 6, y: rect.minY, width: 12, height: rect.height))
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
            if showDone { state.done.forEach(addRow) }
        }
        doc.setFrameSize(NSSize(width: width, height: y))
        return doc
    }

    private func addList(y start: CGFloat) -> CGFloat {
        var doc = makeDocument(width: inner)
        let y = doc.frame.height
        let visible = min(y, Self.maxListHeight)
        let scroll = NSScrollView(frame: NSRect(x: Self.pad, y: start, width: inner, height: visible))
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = y > Self.maxListHeight
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

    // MARK: - Il modulo: nuova cosa, o modifica

    func openForm(editing item: ToDoItem?) {
        if let item {
            nameField.stringValue = item.text
            subjectField.stringValue = item.subject ?? ""
            due = item.due
            mode = .form(editing: item.id)
        } else {
            nameField.stringValue = ""
            subjectField.stringValue = ""
            due = nil
            mode = .form(editing: nil)
        }
        picking = false
        editingField = nameField
        rebuild()
    }

    private func closeForm() {
        mode = .list
        nameField.stringValue = ""
        subjectField.stringValue = ""
        due = nil
        picking = false
        editingField = nil
        window?.makeFirstResponder(nil)
        rebuild()
    }

    private func buildForm(y start: CGFloat, editing: UUID?) -> CGFloat {
        var y = start
        addHeader(title: editing == nil ? "Nuova cosa" : "Modifica", backLabel: "Torna alla lista", y: y) { [weak self] in self?.closeForm() }
        y += 42

        y = addCaption("Cosa c'è da fare?", y: y)
        y = addField(nameField, pill: &namePill, y: y)

        y = addCaption("Per quando", y: y + 6)
        let today = state.today
        let tomorrow = ToDoDay.adding(days: 1, to: today), nextWeek = ToDoDay.adding(days: 7, to: today)
        let custom = due != nil && due != today && due != tomorrow && due != nextWeek
        y = addChips([
            ("Oggi", due == today, { [weak self] in self?.pickDue(today) }),
            ("Domani", due != nil && due == tomorrow, { [weak self] in self?.pickDue(tomorrow) }),
            ("Fra una settimana", due != nil && due == nextWeek, { [weak self] in self?.pickDue(nextWeek) }),
            (custom ? ToDoDay.label(due: due ?? "", today: today) : "Scegli…", custom || picking, { [weak self] in
                guard let self else { return }
                self.picking.toggle()
                self.rebuild()
            }),
        ], y: y)
        if picking {
            let picker = NSDatePicker(frame: NSRect(x: Self.pad, y: y + 2, width: 139, height: 148))
            picker.datePickerStyle = .clockAndCalendar
            picker.datePickerElements = .yearMonthDay
            picker.appearance = NSAppearance(named: .aqua)
            picker.locale = Locale(identifier: "it_IT")
            picker.dateValue = due.flatMap { ToDoDay.date(from: $0) } ?? Date()
            picker.minDate = Calendar.current.startOfDay(for: Date())
            picker.target = self
            picker.action = #selector(datePicked(_:))
            addSubview(picker)
            y += 2 + 148 + 4
        }

        y = addCaption("Materia", y: y + 6)
        y = addField(subjectField, pill: &subjectPill, y: y)
        let subjects = Array(state.recentSubjects.prefix(6))
        let typed = Subject.clean(subjectField.stringValue)
        shownSubjectChip = typed.flatMap { value in subjects.first { Subject.key($0) == Subject.key(value) } }
        if !subjects.isEmpty {
            y = addChips(subjects.map { name in
                (name, shownSubjectChip == name, { [weak self] in
                    guard let self else { return }
                    let already = self.shownSubjectChip == name
                    self.subjectField.stringValue = already ? "" : name
                    self.rebuild()
                })
            }, y: y + 8)
        }

        // Il pulsante grande e «Annulla»
        let canSave = ToDoText.clean(nameField.stringValue) != nil
        nameEnabled = canSave
        let title = editing == nil ? "Aggiungi" : "Salva"
        let save = ToDoButton(frame: NSRect(x: Self.pad, y: y + 10, width: inner, height: 40), label: title)
        save.drawer = { rect, pressed, hovered in
            let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: rect.height / 2, yRadius: rect.height / 2)
            (pressed ? Paper.accentPressed : (hovered && canSave ? Paper.accent : Paper.accent.withAlphaComponent(canSave ? 0.95 : 0.45))).setFill()
            shape.fill()
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            (title as NSString).draw(in: NSRect(x: rect.minX, y: rect.midY - 11, width: rect.width, height: 22),
                                     withAttributes: [.font: Paper.markerFont(18), .foregroundColor: NSColor.white, .paragraphStyle: para])
        }
        save.onClick = { [weak self] in self?.save() }
        addSubview(save)
        let cancel = ToDoButton(frame: NSRect(x: Self.pad, y: y + 10 + 40 + 4, width: inner, height: 26), label: "Annulla")
        cancel.drawer = { rect, pressed, hovered in
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            ("Annulla" as NSString).draw(in: NSRect(x: rect.minX, y: rect.midY - 8.5, width: rect.width, height: 17),
                                         withAttributes: [.font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
                                                          .foregroundColor: hovered || pressed ? Paper.ink : Paper.inkLight, .paragraphStyle: para])
        }
        cancel.onClick = { [weak self] in self?.closeForm() }
        addSubview(cancel)
        return y + 10 + 40 + 4 + 26
    }

    private func addCaption(_ text: String, y: CGFloat) -> CGFloat {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11.5)
        label.textColor = Paper.inkLight
        label.frame = NSRect(x: Self.pad + 4, y: y, width: inner, height: 15)
        addSubview(label)
        return y + 19
    }

    private func addField(_ field: NSTextField, pill: inout InputPill?, y: CGFloat) -> CGFloat {
        let box = InputPill(frame: NSRect(x: Self.pad, y: y, width: inner, height: 36))
        box.isActive = editingField === field
        field.frame = NSRect(x: 16, y: 8, width: inner - 32, height: 20)
        box.addSubview(field)
        addSubview(box)
        pill = box
        return y + 36
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

    /// «Aggiungi» o «Salva»: con il nome vuoto non si fa niente e si resta nel campo.
    @objc private func save() {
        guard case .form(let editing) = mode else { return }
        guard ToDoText.clean(nameField.stringValue) != nil else {
            editingField = nameField
            window?.makeFirstResponder(nameField)
            return
        }
        let text = nameField.stringValue
        let chosenDue = due
        let subject = Subject.clean(subjectField.stringValue)
        mode = .list
        nameField.stringValue = ""
        subjectField.stringValue = ""
        due = nil
        picking = false
        editingField = nil
        listScroll = 0
        window?.makeFirstResponder(nil)
        if let editing { actions.update(editing, text, chosenDue, subject) } else { actions.add(text, chosenDue, subject) }
    }

    // MARK: - I campi

    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        (field === nameField ? namePill : subjectPill)?.isActive = true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        (field === nameField ? namePill : subjectPill)?.isActive = false
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        let limit = field === nameField ? ToDoText.maxLength : Subject.maxLength
        if field.stringValue.count > limit { field.stringValue = String(field.stringValue.prefix(limit)) }
        if field === subjectField {
            // Se cambia quale materia recente combacia, il chip si accende o si spegne: la pagina si ricostruisce, il cursore resta.
            let typed = Subject.clean(field.stringValue)
            let match = typed.flatMap { value in state.recentSubjects.prefix(6).first { Subject.key($0) == Subject.key(value) } }
            if match != shownSubjectChip { DispatchQueue.main.async { [weak self] in self?.rebuild() } }
        }
        // Il pulsante «Aggiungi» è spento finché il nome è vuoto.
        if field === nameField, case .form = mode {
            let enabled = ToDoText.clean(field.stringValue) != nil
            if enabled != (nameEnabled) { nameEnabled = enabled; DispatchQueue.main.async { [weak self] in self?.rebuild() } }
        }
    }

    private var nameEnabled = false

    /// Esc nei campi: si torna alla lista senza salvare (fuori dai campi Esc chiude la scheda, come sempre).
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)), case .form = mode else { return false }
        closeForm()
        return true
    }
}
