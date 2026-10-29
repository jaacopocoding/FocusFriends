import AppKit

/// Quello che la scheda del menu mostra: la fotografia del momento, composta dal MenuController.
struct MenuCardState {
    var pet: Pet
    var allPets: [Pet]
    /// Il nome di chi usa l'app (nil = non l'ha scritto).
    var userName: String?
    var isPetVisible: Bool
    var phase: Pomodoro.Phase?
    var subject: String?
    var remaining: String
    var breakMinutes: Int
    var todaySeconds: Int
    var todayFocusCount: Int
    var streak: Int
    /// La serie è ghiacciata: ieri non si è studiato, studiando oggi continua.
    var streakFrozen = false
    var focusTimers: [Int]
    var restTimers: [Int]
    var customFocus: [Int]
    var customRest: [Int]
    var chattiness: Chattiness
    var petWalks: Bool
    var movementOn: Bool
    var askOn: Bool
    var ambient: AmbientSound
    var ambientVolume: Double
    var music: MusicSource
    var musicLabel: String
    var musicVolume: Double
    // La schermata del focus e quella della pausa
    var focusProgress: Double
    var phaseRange: String
    var focusMinutes: Int
    /// Il conto alla rovescia è fermo: «Ferma» diventa «Riprendi».
    var isPaused: Bool
    /// La pausa in corso è quella lunga (dopo quattro focus).
    var isLongBreak: Bool
    /// Focus fatti del ciclo dei quattro (nil = pausa lunga spenta).
    var cycleDone: Int?
    /// Gli avatar nell'ordine in cui si sbloccano (chi c'è già e chi no) e quanti focus pieni di studio ci sono in tutto.
    var avatars: [AvatarRoster.Entry] = []
    var focusesDone = 0
    var notes: [String]
    var background: BackgroundChoice
    var backgroundVolume: Double
    /// L'ultimo focus finito (per «Hai fatto 50 minuti di Anatomia» e «Com'è andata?» in pausa).
    var lastFocusMinutes: Int?
    var lastFocusSubject: String?
    var lastSessionID: UUID?
    var lastRating: FocusRating?
    /// Le cose da fare (la pagina «Da fare»).
    var todo = ToDoCardState()
    /// L'album delle figurine: quante se ne hanno, quante ce ne sono e quante sono nuove (non ancora viste).
    var albumFound = 0
    var albumTotal = 0
    var albumNew = 0
}

/// Quello che serve ogni secondo mentre la scheda è aperta: poco, perché il resto (statistiche, serie, compagni)
/// si ricalcola solo quando la scheda si ricostruisce.
struct MenuCardLiveState {
    var phase: Pomodoro.Phase?
    var isPaused: Bool
    var remaining: String
    var focusProgress: Double
}

/// Cosa succede quando si tocca qualcosa. Il MenuController le collega a quello che già fa il menu.
struct MenuCardActions {
    var startFocus: (Int) -> Void
    var startBreak: (Int) -> Void
    var stopTimer: () -> Void
    var selectPet: (Pet) -> Void
    var showStats: () -> Void
    var showGarden: () -> Void
    var showAlbum: () -> Void
    var cycleChattiness: () -> Void
    var toggleMovement: () -> Void
    var toggleAsk: () -> Void
    var cycleAmbient: () -> Void
    var cycleMusic: () -> Void
    var setMusicVolume: (Double) -> Void
    var setAmbientVolume: (Double) -> Void
    var toggleVisibility: () -> Void
    var speak: () -> Void
    var addTimer: (CustomTimers.Kind, Int) -> CustomTimers.AddResult
    var removeTimer: (CustomTimers.Kind, Int) -> Void
    var moreSettings: () -> Void
    var quit: () -> Void
    var addMinutes: () -> Void
    var togglePause: () -> Void
    var addNote: (String) -> Void
    var discardFocus: () -> Void
    var setBackground: (BackgroundChoice) -> Void
    var setBackgroundVolume: (Double) -> Void
    var rateLast: (FocusRating) -> Void
    var todoAdd: (_ text: String, _ due: String?, _ subject: String?) -> Void
    var todoUpdate: (_ id: UUID, _ text: String, _ due: String?, _ subject: String?) -> Void
    var todoToggle: (UUID) -> Void
    var todoRemove: (UUID) -> Void
    /// Avvia un focus per questa cosa da fare, con i minuti scelti sul quadrante.
    var todoStartFocus: (UUID, Int) -> Void
}

/// Un pulsante disegnato a mano (origine in alto): ogni elemento della scheda lo usa con il suo disegno.
private final class CardButton: NSButton {
    var drawer: ((NSRect, _ pressed: Bool, _ hovered: Bool) -> Void)?
    var onClick: (() -> Void)?
    private var isHovered = false

    init(frame: NSRect, label: String? = nil) {
        super.init(frame: frame)
        isBordered = false
        setButtonType(.momentaryPushIn)
        title = ""
        target = self
        action = #selector(fire)
        if let label { setAccessibilityLabel(label) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }
    @objc private func fire() { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        drawer?(bounds, isHighlighted, isHovered)
    }
}

/// La scheda del menu: una carta con il compagno che sbuca dal bordo, i tre focus, il riepilogo di oggi e le
/// impostazioni più usate. Stesso linguaggio delle altre schede (carta, inchiostro, pennarello).
private final class MenuCardView: NSView {
    static let width: CGFloat = 300
    /// Quanto il compagno esce dal bordo alto della carta.
    static let overflow: CGFloat = 30
    private static let avatar: CGFloat = 70
    private static let pad: CGFloat = 16

    override var isFlipped: Bool { true }

    private let provide: () -> MenuCardState
    private let live: () -> MenuCardLiveState
    private let actions: MenuCardActions
    /// Chiude la scheda (se `close`) e poi esegue l'azione.
    private let perform: (_ close: Bool, _ action: () -> Void) -> Void
    var onResize: ((CGFloat) -> Void)?

    private enum Page { case main, timers, focus, rest, todo, avatars }
    private var page: Page = .main
    /// In cima alla carta: il compagno sbuca dal bordo nella scheda e nel quadrante; le schermate del quaderno no.
    static let pageTop: CGFloat = 2
    private var cardTop: CGFloat { page == .focus || page == .rest ? Self.pageTop : Self.overflow }
    private var tomato: FocusTomatoView?
    /// La pagina «Avatar»: il compagno al centro del palco (nil = quello che c'è adesso) e il palco, che resta quando la pagina si ricostruisce.
    private var avatarIndex: Int?
    private var avatarStage: AvatarStageView?
    private var noteField: NSTextField?
    private var draftNote = ""

    private static func defaultPage(for phase: Pomodoro.Phase?) -> Page {
        switch phase {
        case .focus?: return .focus
        case .rest?: return .rest
        case nil: return .main
        }
    }
    /// Il quadrante dei timer: tiene il suo valore mentre lo si trascina (la pagina intorno si ricostruisce).
    private var dial: TimerDial?
    /// La pagina «Da fare»: tiene la bozza che si sta scrivendo mentre la scheda si ricostruisce.
    private var todoPage: ToDoPageView?
    private var dialKind: CustomTimers.Kind = .focus
    private var dialMinutes = 50
    /// La cosa da fare per cui si sta scegliendo quanto dura il focus (si arriva dal ▶ di «Da fare»): il quadrante la mostra e «Avvia» parte per lei.
    private var todoFocus: ToDoItem?
    private var timerMessage: String?

    private var statusLabel: NSTextField?
    private var clockLabel: NSTextField?
    private var shownPhase: Pomodoro.Phase?
    private var shownRunning = false
    private var shownPaused = false

    init(state: @escaping () -> MenuCardState, live: @escaping () -> MenuCardLiveState, actions: MenuCardActions,
         perform: @escaping (_ close: Bool, _ action: () -> Void) -> Void) {
        self.provide = state
        self.live = live
        self.actions = actions
        self.perform = perform
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 400))
        appearance = NSAppearance(named: .aqua)
        page = Self.defaultPage(for: provide().phase)
        rebuild()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Disegno della carta

    override func draw(_ dirtyRect: NSRect) {
        let top = cardTop
        let card = NSRect(x: 1, y: top, width: bounds.width - 2, height: bounds.height - top - 1)
        let shape = NSBezierPath(roundedRect: card, xRadius: 20, yRadius: 20)
        Paper.paper.setFill()
        shape.fill()
        Paper.paperEdge.setStroke()
        shape.lineWidth = 1.5
        shape.stroke()
        if page == .focus || page == .rest { FocusDraw.spiralHoles(in: bounds.width, top: top) }
    }

    // MARK: - Aiuti

    private func label(_ text: String, font: NSFont, color: NSColor = Paper.ink, alignment: NSTextAlignment = .center,
                       frame: NSRect) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.alignment = alignment
        field.lineBreakMode = .byTruncatingTail
        field.frame = frame
        addSubview(field)
        return field
    }

    private static func symbol(_ name: String, size: CGFloat, color: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    private static func text(_ string: String, in rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .left) {
        let para = NSMutableParagraphStyle()
        para.alignment = alignment
        para.lineBreakMode = .byTruncatingTail
        (string as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
    }

    private static func drawSymbol(_ name: String, size: CGFloat, color: NSColor, centeredIn box: NSRect) {
        guard let image = symbol(name, size: size, color: color) else { return }
        let s = image.size
        image.draw(in: NSRect(x: box.midX - s.width / 2, y: box.midY - s.height / 2, width: s.width, height: s.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func add(_ frame: NSRect, label: String? = nil, close: Bool = false, _ action: @escaping () -> Void,
                     draw: @escaping (NSRect, Bool, Bool) -> Void) {
        let button = CardButton(frame: frame, label: label)
        button.drawer = draw
        button.onClick = { [weak self] in self?.perform(close, action) }
        addSubview(button)
    }

    /// Il compagno in un cerchio: un tocco e parla.
    private func addAvatar(_ s: MenuCardState, frame: NSRect) {
        let icon = MenuController.menuIcon(for: s.pet, height: 160)
        let focus = s.pet.iconFocus
        add(frame, label: "Fai parlare \(s.pet.name)", close: true, actions.speak) { rect, pressed, hovered in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
            NSColor(calibratedRed: 1.0, green: 0.99, blue: 0.94, alpha: 1).setFill()
            circle.fill()
            if let icon {
                NSGraphicsContext.saveGraphicsState()
                circle.addClip()
                let scale = rect.height / icon.size.height * 1.12
                let size = NSSize(width: icon.size.width * scale, height: icon.size.height * scale)
                let origin = NSPoint(x: rect.midX - size.width * focus, y: rect.midY - size.height * 0.48)
                icon.draw(in: NSRect(origin: origin, size: size), from: .zero, operation: .sourceOver, fraction: 1,
                          respectFlipped: true, hints: nil)
                NSGraphicsContext.restoreGraphicsState()
            }
            (hovered || pressed ? Paper.accent : Paper.paperEdge).setStroke()
            circle.lineWidth = 2.5
            circle.stroke()
        }
    }

    // MARK: - Costruzione

    /// Ricostruisce tutta la scheda dallo stato attuale (dopo un tocco, o quando cambia fase del timer).
    func rebuild() {
        if let field = noteField { draftNote = field.stringValue }
        for view in subviews where !(page == .timers && view === dial) && !(page == .todo && view === todoPage) && !(page == .avatars && view === avatarStage) { view.removeFromSuperview() }
        if page != .timers { dial = nil }
        if page != .todo { todoPage = nil }
        if page != .avatars { avatarStage = nil }
        if page != .timers { todoFocus = nil }
        statusLabel = nil
        clockLabel = nil
        tomato = nil
        noteField = nil
        let s = provide()
        shownPhase = s.phase
        shownRunning = s.phase != nil
        shownPaused = s.isPaused
        // Le schermate del focus e della pausa ci sono solo finché c'è quella fase.
        if (page == .focus && s.phase != .focus) || (page == .rest && s.phase != .rest) { page = .main }
        switch page {
        case .timers:
            buildTimers(s)
            return
        case .todo:
            buildToDo(s)
            return
        case .avatars:
            buildAvatars(s)
            return
        case .focus:
            buildFocus(s)
            return
        case .rest:
            buildRest(s)
            return
        case .main:
            break
        }

        let w = Self.width
        let pad = Self.pad
        let inner = w - 2 * pad
        var y = Self.overflow + 42

        // Il compagno che sbuca: un tocco e parla.
        addAvatar(s, frame: NSRect(x: w / 2 - Self.avatar / 2, y: 0, width: Self.avatar, height: Self.avatar))

        // Saluto e stato
        let greeting = s.userName.map { "Ciao \($0)" } ?? "Ciao!"
        _ = label(greeting, font: Paper.markerFont(20), frame: NSRect(x: pad, y: y, width: inner, height: 26))
        y += 27
        statusLabel = label(statusText(s), font: NSFont.systemFont(ofSize: 12), color: Paper.inkLight,
                            frame: NSRect(x: pad, y: y, width: inner, height: 16))
        y += 24

        // Gli avatar: una riga che apre la pagina, e quanto manca al prossimo da sbloccare.
        y = addAvatarRow(s, y: y)
        y += 14

        // Focus e pausa, oppure il timer che sta andando.
        if let phase = s.phase {
            y = addRunning(s, phase: phase, y: y)
        } else {
            y = addDurations(s, y: y)
        }
        y += 14

        // Riepilogo di oggi
        let tileWidth = (inner - 12) / 3
        let tiles: [(String, String)] = [
            (StudyStats.duration(seconds: s.todaySeconds), "oggi"),
            ("\(s.todayFocusCount)", "focus"),
            ("\(s.streak)", s.streakFrozen ? "ghiacciata" : (s.streak == 1 ? "giorno di fila" : "di fila")),
        ]
        for (i, tile) in tiles.enumerated() {
            let frame = NSRect(x: pad + CGFloat(i) * (tileWidth + 6), y: y, width: tileWidth, height: 50)
            add(frame, label: "\(tile.0) \(tile.1)", close: true, actions.showStats) { rect, pressed, hovered in
                let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 11, yRadius: 11)
                NSColor.white.withAlphaComponent(pressed || hovered ? 0.85 : 0.55).setFill()
                shape.fill()
                Paper.paperEdge.setStroke()
                shape.lineWidth = 1
                shape.stroke()
                Self.text(tile.0, in: NSRect(x: rect.minX + 9, y: rect.minY + 6, width: rect.width - 14, height: 24),
                          font: Paper.markerFont(17), color: Paper.ink)
                Self.text(tile.1, in: NSRect(x: rect.minX + 9, y: rect.minY + 31, width: rect.width - 14, height: 14),
                          font: NSFont.systemFont(ofSize: 11), color: Paper.inkLight)
            }
        }
        y += 50 + 12

        // Giardino e statistiche
        let half = (inner - 6) / 2
        for (i, item) in [("Giardino", "leaf", true), ("Statistiche", "chart.bar.xaxis", false)].enumerated() {
            let frame = NSRect(x: pad + CGFloat(i) * (half + 6), y: y, width: half, height: 34)
            let action = item.2 ? actions.showGarden : actions.showStats
            add(frame, label: item.0, close: true, action) { rect, pressed, hovered in
                let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: rect.height / 2, yRadius: rect.height / 2)
                (pressed ? Paper.accent.withAlphaComponent(0.3) : hovered ? Paper.accent.withAlphaComponent(0.14) : Paper.paper).setFill()
                shape.fill()
                Paper.paperEdge.setStroke()
                shape.lineWidth = 1
                shape.stroke()
                let textWidth = (item.0 as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium)]).width
                let startX = rect.midX - (18 + textWidth) / 2
                Self.drawSymbol(item.1, size: 14, color: Paper.inkLight, centeredIn: NSRect(x: startX, y: rect.minY, width: 14, height: rect.height))
                Self.text(item.0, in: NSRect(x: startX + 20, y: rect.midY - 8, width: textWidth + 4, height: 17),
                          font: NSFont.systemFont(ofSize: 13, weight: .medium), color: Paper.ink)
            }
        }
        y += 34 + 12

        // Linea e impostazioni rapide
        let line = NSView(frame: NSRect(x: pad, y: y, width: inner, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = Paper.paperEdge.withAlphaComponent(0.5).cgColor
        addSubview(line)
        y += 8

        y = addOption(symbol: "bubble.left", title: "Frasi", value: s.chattiness.title, toggle: nil, y: y, close: false) {
            self.actions.cycleChattiness()
        }
        y = addOption(symbol: s.ambient.symbolName, title: "Suono ambiente", value: s.ambient.title, toggle: nil, y: y, close: false) {
            self.actions.cycleAmbient()
        }
        if s.ambient != .none {
            y = addVolume(value: s.ambientVolume, y: y) { self.actions.setAmbientVolume($0) }
        }
        y = addOption(symbol: "music.note", title: "Musica", value: s.musicLabel, toggle: nil, y: y, close: false) {
            self.actions.cycleMusic()
        }
        if s.music != .off {
            y = addVolume(value: s.musicVolume, y: y) { self.actions.setMusicVolume($0) }
        }
        if s.petWalks {
            y = addOption(symbol: "figure.walk", title: "Cammina per lo schermo", value: nil, toggle: s.movementOn, y: y, close: false) {
                self.actions.toggleMovement()
            }
        }
        y = addOption(symbol: "face.smiling", title: "Chiedi com'è andata", value: nil, toggle: s.askOn, y: y, close: false) {
            self.actions.toggleAsk()
        }
        y = addOption(symbol: "checklist", title: "Da fare", value: s.todo.openCount > 0 ? "\(s.todo.openCount)" : nil, toggle: nil, y: y, close: false) {
            self.page = .todo
        }
        y = addOption(symbol: "book.closed", title: "Album", value: s.albumTotal > 0
                      ? "\(s.albumFound)/\(s.albumTotal)" + (s.albumNew > 0 ? " · \(s.albumNew) \(s.albumNew == 1 ? "nuova" : "nuove")" : "") : nil,
                      toggle: nil, y: y, close: true) {
            self.actions.showAlbum()
        }
        y = addOption(symbol: s.isPetVisible ? "eye.slash" : "eye",
                      title: s.isPetVisible ? "Nascondi \(s.pet.name)" : "Mostra \(s.pet.name)",
                      value: nil, toggle: nil, y: y, close: true) {
            self.actions.toggleVisibility()
        }
        y += 6

        // In fondo
        addFooter(title: "Altre impostazioni…", x: pad, width: 150, alignment: .left, y: y, action: actions.moreSettings)
        addFooter(title: "Esci", x: w - pad - 60, width: 60, alignment: .right, y: y, action: actions.quit)
        y += 24 + 12

        setFrameSize(NSSize(width: w, height: y))
        needsDisplay = true
        onResize?(y)
    }

    private func statusText(_ s: MenuCardState) -> String {
        switch s.phase {
        case .focus?: return s.subject.map { "Focus · \($0)" } ?? "Focus"
        case .rest?: return s.isLongBreak ? "Pausa lunga" : "Pausa"
        case nil: return s.isPetVisible ? "\(s.pet.name) è qui con te" : "\(s.pet.name) è nascosto"
        }
    }

    // MARK: - Avatar

    /// Una barra di avanzamento: la pista e la parte fatta (mai più stretta di un pallino).
    private static func drawBar(_ rect: NSRect, fraction: CGFloat) {
        Paper.track.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        Paper.accent.setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: max(rect.width * min(max(fraction, 0), 1), rect.height), height: rect.height),
                     xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
    }

    /// La riga «Avatar»: le teste dei compagni che ci sono, e un tocco apre la pagina per sceglierli. Sotto, quanto manca al prossimo da sbloccare
    /// (senza dire chi è). Con più avatar e più isole la riga resta la stessa: cambia solo il conto.
    private func addAvatarRow(_ s: MenuCardState, y: CGFloat) -> CGFloat {
        let pad = Self.pad
        let inner = Self.width - 2 * pad
        let unlocked = s.avatars.filter(\.isUnlocked)
        let subtitle = AvatarRoster.countLine(unlocked: unlocked.count, locked: s.avatars.count - unlocked.count)
        let others = unlocked.compactMap { entry in s.allPets.first { $0.id == entry.id } }.filter { $0.id != s.pet.id }
        let heads: [(pet: Pet, icon: NSImage?)] = ([s.pet] + others).prefix(3).map { ($0, MenuController.menuIcon(for: $0, height: 80)) }
        let open: () -> Void = { [weak self] in
            guard let self else { return }
            self.avatarIndex = nil
            self.page = .avatars
            self.rebuild()
        }
        add(NSRect(x: pad, y: y, width: inner, height: 46), label: "Avatar: \(subtitle)", open) { rect, pressed, hovered in
            let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
            (pressed ? Paper.accent.withAlphaComponent(0.2) : hovered ? Paper.accent.withAlphaComponent(0.1)
                : NSColor(calibratedRed: 1, green: 0.98, blue: 0.94, alpha: 1)).setFill()
            shape.fill()
            Paper.paperEdge.setStroke()
            shape.lineWidth = 1
            shape.stroke()
            // le teste si sovrappongono: la prima sta sopra
            for (i, head) in heads.enumerated().reversed() {
                let circle = NSRect(x: rect.minX + 10 + CGFloat(i) * 21, y: rect.midY - 15, width: 30, height: 30)
                let path = NSBezierPath(ovalIn: circle)
                NSColor(calibratedRed: 1, green: 0.99, blue: 0.94, alpha: 1).setFill()
                path.fill()
                if let icon = head.icon {
                    NSGraphicsContext.saveGraphicsState()
                    path.addClip()
                    let scale = circle.height / icon.size.height * 1.12
                    let size = NSSize(width: icon.size.width * scale, height: icon.size.height * scale)
                    icon.draw(in: NSRect(origin: NSPoint(x: circle.midX - size.width * head.pet.iconFocus, y: circle.midY - size.height * 0.48), size: size),
                              from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                    NSGraphicsContext.restoreGraphicsState()
                }
                Paper.paperEdge.setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
            let textX = rect.minX + 10 + CGFloat(max(heads.count - 1, 0)) * 21 + 30 + 10
            Self.text("Avatar", in: NSRect(x: textX, y: rect.minY + 7, width: rect.maxX - textX - 30, height: 17),
                      font: NSFont.systemFont(ofSize: 13, weight: .medium), color: Paper.ink)
            Self.text(subtitle, in: NSRect(x: textX, y: rect.minY + 25, width: rect.maxX - textX - 30, height: 14),
                      font: NSFont.systemFont(ofSize: 11), color: Paper.inkLight)
            Self.drawSymbol("chevron.right", size: 14, color: Paper.inkLight, centeredIn: NSRect(x: rect.maxX - 26, y: rect.midY - 10, width: 16, height: 20))
        }
        var bottom = y + 46
        if let next = AvatarRoster.next(in: s.avatars) {
            let line = AvatarRoster.nextLine(need: next.need, have: s.focusesDone)
            let fraction = CGFloat(AvatarRoster.progress(need: next.need, have: s.focusesDone))
            add(NSRect(x: pad, y: bottom + 5, width: inner, height: 28), label: line, open) { rect, _, hovered in
                Self.text(line, in: NSRect(x: rect.minX + 2, y: rect.minY, width: rect.width - 4, height: 14),
                          font: NSFont.systemFont(ofSize: 11), color: hovered ? Paper.ink : Paper.inkLight)
                Self.drawBar(NSRect(x: rect.minX + 2, y: rect.minY + 19, width: rect.width - 4, height: 5), fraction: fraction)
            }
            bottom += 5 + 28
        }
        return bottom
    }

    /// La pagina «Avatar»: i compagni in fila sul palco, quello scelto grande al centro; si scorre da uno all'altro. Chi non c'è ancora è una sagoma
    /// nera sfocata, senza nome.
    private func buildAvatars(_ s: MenuCardState) {
        let w = Self.width
        let pad = Self.pad
        let inner = w - 2 * pad
        var y = Self.overflow + 14
        let entries = s.avatars
        let pets = entries.compactMap { entry in s.allPets.first { $0.id == entry.id } }
        guard !entries.isEmpty, pets.count == entries.count else {
            page = .main
            rebuild()
            return
        }

        // Intestazione con la freccia indietro
        add(NSRect(x: pad - 6, y: y, width: 36, height: 30), label: "Torna alla scheda", { [weak self] in
            self?.page = .main
            self?.rebuild()
        }) { rect, pressed, hovered in
            Self.drawSymbol("chevron.left", size: 15, color: hovered || pressed ? Paper.ink : Paper.inkLight, centeredIn: rect)
        }
        _ = label("Avatar", font: Paper.markerFont(20), alignment: .left, frame: NSRect(x: pad + 30, y: y + 2, width: inner - 100, height: 26))
        _ = label("\(entries.filter(\.isUnlocked).count) su \(entries.count)", font: NSFont.systemFont(ofSize: 11), color: Paper.inkLight,
                  alignment: .right, frame: NSRect(x: w - pad - 70, y: y + 8, width: 70, height: 15))
        y += 42

        // Il palco: ricorda dov'era quando la pagina si ricostruisce
        let current = min(max(avatarIndex ?? entries.firstIndex { $0.id == s.pet.id } ?? 0, 0), entries.count - 1)
        avatarIndex = current
        let stage: AvatarStageView
        if let existing = avatarStage {
            stage = existing
        } else {
            stage = AvatarStageView(frame: .zero)
            stage.onChange = { [weak self] index in
                self?.avatarIndex = index
                self?.rebuild()
            }
            avatarStage = stage
            addSubview(stage)
        }
        stage.frame = NSRect(x: pad, y: y, width: inner, height: 204)
        stage.configure(slots: zip(pets, entries).map { AvatarStageView.Slot(pet: $0, isUnlocked: $1.isUnlocked) }, index: current)
        y += 204 + 8

        // Il nome (se c'è) e l'isola
        let entry = entries[current]
        let pet = pets[current]
        _ = label(entry.isUnlocked ? pet.name : AvatarRoster.hiddenName, font: Paper.markerFont(24), frame: NSRect(x: pad, y: y, width: inner, height: 30))
        y += 31
        _ = label(entry.isUnlocked ? "Isola di \(pet.name)" : "L'isola è ancora chiusa", font: NSFont.systemFont(ofSize: 12), color: Paper.inkLight,
                  frame: NSRect(x: pad, y: y, width: inner, height: 16))
        y += 26

        // Le frecce e i puntini (se sono troppi, il conto)
        let rowY = y
        func addArrow(_ symbol: String, x: CGFloat, target: Int, name: String) {
            add(NSRect(x: x, y: rowY, width: 30, height: 30), label: name, { [weak self] in self?.avatarStage?.go(to: target) }) { rect, pressed, hovered in
                let shape = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
                (pressed ? Paper.accent.withAlphaComponent(0.25) : hovered ? Paper.accent.withAlphaComponent(0.12)
                    : NSColor(calibratedRed: 1, green: 0.98, blue: 0.94, alpha: 1)).setFill()
                shape.fill()
                Paper.paperEdge.setStroke()
                shape.lineWidth = 1
                shape.stroke()
                Self.drawSymbol(symbol, size: 13, color: Paper.ink, centeredIn: rect)
            }
        }
        if current > 0 { addArrow("chevron.left", x: pad + 12, target: current - 1, name: "Compagno precedente") }
        if current < entries.count - 1 { addArrow("chevron.right", x: w - pad - 12 - 30, target: current + 1, name: "Compagno successivo") }
        let dotsRoom = inner - 2 * (12 + 30 + 8)
        let dotWidths = entries.indices.map { $0 == current ? CGFloat(24) : CGFloat(14) }
        if dotWidths.reduce(0, +) <= dotsRoom {
            var x = (w - dotWidths.reduce(0, +)) / 2
            for i in entries.indices {
                add(NSRect(x: x, y: rowY + 4, width: dotWidths[i], height: 22), label: "Compagno \(i + 1) di \(entries.count)", { [weak self] in
                    self?.avatarStage?.go(to: i)
                }) { rect, _, hovered in
                    let on = i == current
                    let width: CGFloat = on ? 18 : 8
                    (on ? Paper.accent : hovered ? NSColor(calibratedRed: 0.75, green: 0.68, blue: 0.55, alpha: 1)
                        : NSColor(calibratedRed: 0.85, green: 0.79, blue: 0.68, alpha: 1)).setFill()
                    NSBezierPath(roundedRect: NSRect(x: rect.midX - width / 2, y: rect.midY - 4, width: width, height: 8), xRadius: 4, yRadius: 4).fill()
                }
                x += dotWidths[i]
            }
        } else {
            _ = label("\(current + 1) / \(entries.count)", font: NSFont.systemFont(ofSize: 12), color: Paper.inkLight,
                      frame: NSRect(x: pad + 52, y: rowY + 7, width: inner - 104, height: 16))
        }
        y = rowY + 30 + 12

        y = addAvatarInfo(s, entry: entry, pet: pet, y: y)
        y += 16
        setFrameSize(NSSize(width: w, height: y))
        needsDisplay = true
        onResize?(y)
    }

    /// Sotto il palco: per chi c'è, «con te» o il pulsante per studiare con lui; per chi non c'è ancora, quanto manca (e mai chi è).
    private func addAvatarInfo(_ s: MenuCardState, entry: AvatarRoster.Entry, pet: Pet, y: CGFloat) -> CGFloat {
        let w = Self.width
        let pad = Self.pad
        let inner = w - 2 * pad
        let height: CGFloat = entry.isUnlocked ? 46 : 96
        let have = min(s.focusesDone, entry.need)
        let fraction = CGFloat(AvatarRoster.progress(need: entry.need, have: s.focusesDone))
        let backdrop = CardButton(frame: NSRect(x: pad, y: y, width: inner, height: height))
        backdrop.isEnabled = false
        backdrop.drawer = { rect, _, _ in
            let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
            NSColor(calibratedRed: 1, green: 0.98, blue: 0.94, alpha: 1).setFill()
            shape.fill()
            Paper.paperEdge.setStroke()
            shape.lineWidth = 1
            shape.stroke()
            if !entry.isUnlocked { Self.drawBar(NSRect(x: rect.minX + 12, y: rect.minY + 32, width: rect.width - 24, height: 6), fraction: fraction) }
        }
        addSubview(backdrop)
        if entry.isUnlocked {
            if pet.id == s.pet.id {
                _ = label("✓ con te", font: NSFont.systemFont(ofSize: 14, weight: .medium), color: Paper.accentPressed,
                          frame: NSRect(x: pad, y: y + 14, width: inner, height: 18))
            } else {
                let title = "Studia con \(pet.name)"
                let width = ceil((title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium)]).width) + 40
                add(NSRect(x: (w - width) / 2, y: y + 8, width: width, height: 30), label: title, { [weak self] in
                    self?.actions.selectPet(pet)
                    self?.rebuild()
                }) { rect, pressed, hovered in
                    let shape = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
                    (pressed ? Paper.accentPressed : hovered ? Paper.accent.withAlphaComponent(0.92) : Paper.accent).setFill()
                    shape.fill()
                    Self.text(title, in: NSRect(x: rect.minX, y: rect.minY + 6, width: rect.width, height: 17),
                              font: NSFont.systemFont(ofSize: 13, weight: .medium), color: .white, alignment: .center)
                }
            }
        } else {
            _ = label("\(AvatarRoster.remainingText(need: entry.need, have: s.focusesDone)) (\(AvatarRoster.hoursText(need: entry.need, have: s.focusesDone)))",
                      font: NSFont.systemFont(ofSize: 11), color: Paper.inkLight, alignment: .left,
                      frame: NSRect(x: pad + 12, y: y + 10, width: inner - 24 - 56, height: 14))
            _ = label("\(have) / \(entry.need)", font: NSFont.systemFont(ofSize: 11), color: Paper.inkLight, alignment: .right,
                      frame: NSRect(x: w - pad - 12 - 56, y: y + 10, width: 56, height: 14))
            let things = GardenCatalog.items(forIsland: entry.id).count
            let promise = NSTextField(wrappingLabelWithString: things > 0
                ? "Con un nuovo compagno si apre la sua isola, con \(things) cose nuove da trovare."
                : "Con un nuovo compagno si apre la sua isola.")
            promise.font = NSFont.systemFont(ofSize: 12)
            promise.textColor = Paper.inkLight
            promise.frame = NSRect(x: pad + 12, y: y + 46, width: inner - 24, height: 40)
            addSubview(promise)
        }
        return y + height
    }

    private func addDurations(_ s: MenuCardState, y: CGFloat) -> CGFloat {
        let inner = Self.width - 2 * Self.pad
        let width = (inner - 12) / 3
        let items: [(number: String, caption: String, primary: Bool, run: () -> Void)] = [
            ("30", "minuti", false, { self.actions.startFocus(30) }),
            ("50", "minuti", true, { self.actions.startFocus(50) }),
            ("\(s.breakMinutes)", "pausa", false, { self.actions.startBreak(s.breakMinutes) }),
        ]
        for (i, item) in items.enumerated() {
            let frame = NSRect(x: Self.pad + CGFloat(i) * (width + 6), y: y, width: width, height: 58)
            add(frame, label: item.caption == "pausa" ? "Pausa di \(item.number) minuti" : "Focus di \(item.number) minuti",
                close: true, item.run) { rect, pressed, hovered in
                let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: rect.height / 2, yRadius: rect.height / 2)
                let fill: NSColor
                if item.primary {
                    fill = pressed ? Paper.accentPressed : Paper.accent
                } else {
                    fill = pressed ? Paper.accent.withAlphaComponent(0.3) : hovered ? Paper.accent.withAlphaComponent(0.14) : Paper.paper
                }
                fill.setFill()
                shape.fill()
                (item.primary ? Paper.accent : Paper.paperEdge).setStroke()
                shape.lineWidth = 1
                shape.stroke()
                let ink = item.primary ? NSColor.white : Paper.ink
                Self.text(item.number, in: NSRect(x: rect.minX, y: rect.minY + 9, width: rect.width, height: 26),
                          font: Paper.markerFont(22), color: ink, alignment: .center)
                Self.text(item.caption, in: NSRect(x: rect.minX, y: rect.minY + 36, width: rect.width, height: 14),
                          font: NSFont.systemFont(ofSize: 11), color: item.primary ? NSColor.white.withAlphaComponent(0.9) : Paper.inkLight,
                          alignment: .center)
            }
        }
        var next = y + 58 + 6
        add(NSRect(x: Self.width / 2 - 60, y: next, width: 120, height: 18), label: "Altri timer", { [weak self] in
            guard let self else { return }
            self.dialKind = .focus
            self.dialMinutes = 50
            self.timerMessage = nil
            self.page = .timers
            self.rebuild()
        }) {
            rect, pressed, hovered in
            Self.text("Altri timer…", in: rect, font: NSFont.systemFont(ofSize: 12), color: hovered || pressed ? Paper.ink : Paper.inkLight,
                      alignment: .center)
        }
        next += 18
        return next
    }

    /// Mentre il timer va: il tempo che manca e il pulsante per fermarlo.
    private func addRunning(_ s: MenuCardState, phase: Pomodoro.Phase, y: CGFloat) -> CGFloat {
        let inner = Self.width - 2 * Self.pad
        let box = NSRect(x: Self.pad, y: y, width: inner, height: 64)
        let backdrop = NSView(frame: box)
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 14
        backdrop.layer?.backgroundColor = Paper.accent.withAlphaComponent(0.12).cgColor
        backdrop.layer?.borderColor = Paper.accent.cgColor
        backdrop.layer?.borderWidth = 1
        addSubview(backdrop)

        let title = phase == .focus ? (s.subject.map { "FOCUS · \($0.uppercased())" } ?? "FOCUS") : "PAUSA"
        _ = label(title, font: NSFont.systemFont(ofSize: 11, weight: .semibold), color: Paper.inkLight, alignment: .left,
                  frame: NSRect(x: box.minX + 14, y: box.minY + 9, width: inner - 120, height: 14))
        clockLabel = label(s.remaining, font: Paper.markerFont(30), alignment: .left,
                           frame: NSRect(x: box.minX + 14, y: box.minY + 24, width: inner - 120, height: 36))
        add(NSRect(x: box.maxX - 98, y: box.midY - 18, width: 86, height: 36), label: "Ferma il timer", { [weak self] in
            self?.actions.stopTimer()
            self?.rebuild()
        }) { rect, pressed, hovered in
            let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: rect.height / 2, yRadius: rect.height / 2)
            (pressed ? Paper.accentPressed : Paper.accent).setFill()
            shape.fill()
            Self.text("Ferma", in: NSRect(x: rect.minX, y: rect.midY - 11, width: rect.width, height: 22),
                      font: Paper.markerFont(16), color: .white, alignment: .center)
            _ = hovered
        }
        return y + 64
    }

    /// Una riga delle impostazioni: icona, nome e, a destra, un valore o un interruttore.
    private func addOption(symbol: String, title: String, value: String?, toggle: Bool?, y: CGFloat, close: Bool,
                           action: @escaping () -> Void) -> CGFloat {
        let inner = Self.width - 2 * Self.pad
        let frame = NSRect(x: Self.pad - 6, y: y, width: inner + 12, height: 30)
        add(frame, label: title, close: close, { [weak self] in
            action()
            if !close { self?.rebuild() }
        }) { rect, pressed, hovered in
            if hovered || pressed {
                Paper.ink.withAlphaComponent(0.06).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
            }
            Self.drawSymbol(symbol, size: 14, color: Paper.inkLight, centeredIn: NSRect(x: rect.minX + 6, y: rect.minY, width: 18, height: rect.height))
            Self.text(title, in: NSRect(x: rect.minX + 32, y: rect.midY - 8.5, width: rect.width - 130, height: 17),
                      font: NSFont.systemFont(ofSize: 13), color: Paper.ink)
            if let value {
                Self.text(value, in: NSRect(x: rect.maxX - 110, y: rect.midY - 8.5, width: 100, height: 17),
                          font: NSFont.systemFont(ofSize: 13), color: Paper.inkLight, alignment: .right)
            }
            if let on = toggle {
                let track = NSRect(x: rect.maxX - 44, y: rect.midY - 9, width: 34, height: 18)
                (on ? Paper.accent : Paper.paperEdge.withAlphaComponent(0.35)).setFill()
                NSBezierPath(roundedRect: track, xRadius: 9, yRadius: 9).fill()
                let knob = NSRect(x: on ? track.maxX - 16 : track.minX + 2, y: track.minY + 2, width: 14, height: 14)
                NSColor.white.setFill()
                NSBezierPath(ovalIn: knob).fill()
            }
        }
        return y + 30
    }

    /// Il cursore del volume: sotto la riga del suono, quando è acceso.
    private func addVolume(value: Double, y: CGFloat, onChange: @escaping (Double) -> Void) -> CGFloat {
        let inner = Self.width - 2 * Self.pad
        _ = label("Volume", font: NSFont.systemFont(ofSize: 12), color: Paper.inkLight, alignment: .left,
                  frame: NSRect(x: Self.pad + 26, y: y + 6, width: 60, height: 16))
        let slider = VolumeSlider(frame: NSRect(x: Self.pad + 88, y: y, width: inner - 88 - 4, height: 28))
        slider.value = value
        slider.onChange = { new in onChange(new) }
        addSubview(slider)
        return y + 28
    }

    private func addFooter(title: String, x: CGFloat, width: CGFloat, alignment: NSTextAlignment, y: CGFloat, action: @escaping () -> Void) {
        add(NSRect(x: x, y: y, width: width, height: 24), label: title, close: true, action) { rect, pressed, hovered in
            Self.text(title, in: NSRect(x: rect.minX, y: rect.midY - 8.5, width: rect.width, height: 17),
                      font: NSFont.systemFont(ofSize: 12.5, weight: .medium), color: hovered || pressed ? Paper.ink : Paper.inkLight,
                      alignment: alignment)
        }
    }

    // MARK: - La pagina «Da fare»

    /// La pagina con il campo per aggiungere e la lista: è una vista a parte (ToDoPage.swift), che qui si sistema nella carta.
    private func buildToDo(_ s: MenuCardState) {
        let view: ToDoPageView
        if let existing = todoPage {
            view = existing
        } else {
            view = ToDoPageView(width: Self.width, state: s.todo, actions: ToDoPageActions(
                back: { [weak self] in
                    self?.page = .main
                    self?.rebuild()
                },
                add: { [weak self] text, due, subject in
                    self?.actions.todoAdd(text, due, subject)
                    self?.rebuild()
                },
                update: { [weak self] id, text, due, subject in
                    self?.actions.todoUpdate(id, text, due, subject)
                    self?.rebuild()
                },
                toggle: { [weak self] id in
                    self?.actions.todoToggle(id)
                    self?.rebuild()
                },
                remove: { [weak self] id in
                    self?.actions.todoRemove(id)
                    self?.rebuild()
                },
                startFocus: { [weak self] id in self?.openTimers(forToDo: id) }))
            view.onHeight = { [weak self] height in self?.fit(toDoHeight: height) }
            todoPage = view
        }
        view.frame.origin = NSPoint(x: 0, y: Self.overflow)
        addSubview(view)
        view.update(s.todo)
        fit(toDoHeight: view.height)
    }

    /// Il ▶ di una voce: si va al quadrante «Gira il timer» per scegliere i minuti; «Avvia il focus» parte per quella voce.
    private func openTimers(forToDo id: UUID) {
        let s = provide()
        guard let item = (s.todo.sections.flatMap(\.items) + s.todo.done).first(where: { $0.id == id }) else { return }
        todoFocus = item
        dialKind = .focus
        dialMinutes = (1...dialMax).contains(s.focusMinutes) ? s.focusMinutes : 50     // l'ultima durata scelta, come punto di partenza
        timerMessage = nil
        page = .timers
        rebuild()
    }

    private func fit(toDoHeight height: CGFloat) {
        guard page == .todo else { return }
        let total = Self.overflow + height
        guard abs(frame.height - total) > 0.5 else { return }
        setFrameSize(NSSize(width: Self.width, height: total))
        needsDisplay = true
        onResize?(total)
    }

    // MARK: - La pagina dei timer

    private var dialMax: Int { dialKind == .focus ? 120 : 30 }
    private var dialStep: Int { dialKind == .focus ? 5 : 1 }

    /// Il riquadro «FOCUS PER …» sopra il quadrante, quando si arriva dal ▶ di una voce di «Da fare». Restituisce la nuova y.
    private func addTodoBanner(_ item: ToDoItem, y start: CGFloat) -> CGFloat {
        let pad = Self.pad
        let inner = Self.width - 2 * pad
        var y = start
        let hasSubject = item.subject != nil
        let box = NSView(frame: NSRect(x: pad, y: y, width: inner, height: hasSubject ? 62 : 46))
        box.wantsLayer = true
        box.layer?.cornerRadius = 12
        box.layer?.backgroundColor = Paper.accent.withAlphaComponent(0.12).cgColor
        box.layer?.borderColor = Paper.accent.cgColor
        box.layer?.borderWidth = 1
        addSubview(box)
        _ = label("FOCUS PER", font: NSFont.systemFont(ofSize: 10.5, weight: .semibold), color: Paper.inkLight, alignment: .left,
                  frame: NSRect(x: box.frame.minX + 12, y: y + 7, width: inner - 24, height: 13))
        _ = label(item.text, font: NSFont.systemFont(ofSize: 13), alignment: .left,
                  frame: NSRect(x: box.frame.minX + 12, y: y + 22, width: inner - 24, height: 17))
        if let subject = item.subject {
            let dot = NSView(frame: NSRect(x: box.frame.minX + 13, y: y + 45, width: 8, height: 8))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 4
            dot.layer?.backgroundColor = Paper.color(forSubject: subject).cgColor
            addSubview(dot)
            _ = label(subject, font: NSFont.systemFont(ofSize: 11), color: Paper.inkLight, alignment: .left,
                  frame: NSRect(x: box.frame.minX + 26, y: y + 41, width: inner - 38, height: 15))
        }
        y += box.frame.height + 10
        return y
    }

    /// «Focus / Pausa»: la scelta di cosa gira il quadrante. Restituisce la nuova y.
    private func addKindSwitch(_ s: MenuCardState, y start: CGFloat) -> CGFloat {
        let pad = Self.pad
        let inner = Self.width - 2 * pad
        var y = start
        // Focus o pausa
        let backdrop = NSView(frame: NSRect(x: pad, y: y, width: inner, height: 30))
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 15
        backdrop.layer?.backgroundColor = Paper.paperEdge.withAlphaComponent(0.18).cgColor
        addSubview(backdrop)
        for (i, kind) in [CustomTimers.Kind.focus, .rest].enumerated() {
            let frame = NSRect(x: pad + CGFloat(i) * inner / 2, y: y, width: inner / 2, height: 30)
            add(frame, label: kind.title, { [weak self] in
                guard let self, self.dialKind != kind else { return }
                self.dialKind = kind
                self.dialMinutes = kind == .rest ? s.breakMinutes : 50
                self.timerMessage = nil
                self.rebuild()
            }) { [dialKind] rect, pressed, hovered in
                if dialKind == kind {
                    let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 3), xRadius: 12, yRadius: 12)
                    Paper.paper.setFill()
                    shape.fill()
                    Paper.paperEdge.setStroke()
                    shape.lineWidth = 1
                    shape.stroke()
                }
                Self.text(kind.title, in: NSRect(x: rect.minX, y: rect.midY - 8.5, width: rect.width, height: 17),
                          font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
                          color: dialKind == kind || hovered || pressed ? Paper.ink : Paper.inkLight, alignment: .center)
            }
        }
        y += 30 + 10
        return y
    }

    /// "‹ Gira il timer": il quadrante da girare per scegliere i minuti, i timer salvati e Avvia.
    private func buildTimers(_ s: MenuCardState) {
        let w = Self.width
        let pad = Self.pad
        let inner = w - 2 * pad
        var y = Self.overflow + 14

        // Intestazione con la freccia indietro (da «Da fare» si torna alla lista)
        add(NSRect(x: pad - 6, y: y, width: 36, height: 30), label: todoFocus == nil ? "Torna alla scheda" : "Torna a Da fare", { [weak self] in
            guard let self else { return }
            self.page = self.todoFocus == nil ? .main : .todo
            self.todoFocus = nil
            self.rebuild()
        }) { rect, pressed, hovered in
            if let image = Paper.symbolImage("chevron.left", size: 15, color: hovered || pressed ? Paper.ink : Paper.inkLight) {
                let size = image.size
                image.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height),
                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
        }
        _ = label("Gira il timer", font: Paper.markerFont(20), alignment: .left,
                  frame: NSRect(x: pad + 30, y: y + 2, width: inner - 30, height: 26))
        y += 42

        y = todoFocus.map { addTodoBanner($0, y: y) } ?? addKindSwitch(s, y: y)

        // Il quadrante
        let dialSize: CGFloat = 176
        let dialView: TimerDial
        if let existing = dial {
            dialView = existing
        } else {
            dialView = TimerDial(frame: .zero)
            dialView.onChange = { [weak self] minutes in
                self?.dialMinutes = minutes
                self?.timerMessage = nil
                self?.rebuild()
            }
            dial = dialView
            addSubview(dialView)
        }
        dialView.frame = NSRect(x: (w - dialSize) / 2, y: y, width: dialSize, height: dialSize)
        dialView.maxMinutes = dialMax
        dialView.step = dialStep
        dialView.hardMax = CustomTimers.allowed[dialKind]?.upperBound ?? 120
        dialView.minutes = dialMinutes
        y += dialSize + 2

        // Salva (se non c'è) o rimuovi (se è tuo) il timer con questi minuti
        let all = dialKind == .focus ? s.focusTimers : s.restTimers
        let mine = dialKind == .focus ? s.customFocus : s.customRest
        let linkFrame = NSRect(x: pad, y: y, width: inner, height: 20)
        if let message = timerMessage {
            _ = label(message, font: NSFont.systemFont(ofSize: 12), color: Paper.accent, frame: linkFrame)
        } else if mine.contains(dialMinutes) {
            add(linkFrame, label: "Rimuovi dai miei timer", { [weak self] in
                guard let self else { return }
                self.actions.removeTimer(self.dialKind, self.dialMinutes)
                self.rebuild()
            }) { rect, pressed, hovered in
                Self.text("Rimuovi dai miei timer", in: rect, font: NSFont.systemFont(ofSize: 12),
                          color: hovered || pressed ? Paper.ink : Paper.inkLight, alignment: .center)
            }
        } else if !all.contains(dialMinutes) {
            add(linkFrame, label: "Salva tra i miei timer", { [weak self] in
                guard let self else { return }
                switch self.actions.addTimer(self.dialKind, self.dialMinutes) {
                case .added: break
                case .tooMany(let max): self.timerMessage = "Puoi salvarne al massimo \(max): togline uno."
                case .outOfRange(let range): self.timerMessage = "Da \(range.lowerBound) a \(range.upperBound) minuti."
                case .alreadyExists: break
                }
                self.rebuild()
            }) { rect, pressed, hovered in
                Self.text("Salva tra i miei timer", in: rect, font: NSFont.systemFont(ofSize: 12, weight: .medium),
                          color: hovered || pressed ? Paper.accentPressed : Paper.accent, alignment: .center)
            }
        } else {
            _ = label(dialKind == .rest ? "Parte da sola dopo ogni focus."
                                        : "Trascina il pallino per cambiare i minuti.",
                      font: NSFont.systemFont(ofSize: 11.5), color: Paper.inkLight, frame: linkFrame)
        }
        y += 28

        // I timer che hai: si toccano per metterli sul quadrante.
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        var rows: [[Int]] = [[]]
        var rowWidth: CGFloat = 0
        func chipWidth(_ m: Int) -> CGFloat { ceil(("\(m)" as NSString).size(withAttributes: [.font: font]).width) + 30 }
        for minutes in all {
            let cw = chipWidth(minutes)
            if rowWidth + cw > inner, !rows[rows.count - 1].isEmpty {
                rows.append([])
                rowWidth = 0
            }
            rows[rows.count - 1].append(minutes)
            rowWidth += cw + 8
        }
        for row in rows {
            let total = row.reduce(0) { $0 + chipWidth($1) } + 8 * CGFloat(max(row.count - 1, 0))
            var x = (w - total) / 2
            for minutes in row {
                let cw = chipWidth(minutes)
                let selected = minutes == dialMinutes
                let isMine = mine.contains(minutes)
                add(NSRect(x: x, y: y, width: cw, height: 30), label: "\(minutes) minuti", { [weak self] in
                    self?.dialMinutes = minutes
                    self?.timerMessage = nil
                    self?.rebuild()
                }) { rect, pressed, hovered in
                    let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: rect.height / 2, yRadius: rect.height / 2)
                    (selected ? (pressed ? Paper.accentPressed : Paper.accent)
                        : pressed ? Paper.accent.withAlphaComponent(0.3)
                        : hovered ? Paper.accent.withAlphaComponent(0.14) : Paper.paper).setFill()
                    shape.fill()
                    (selected ? Paper.accent : Paper.paperEdge).setStroke()
                    shape.lineWidth = isMine && !selected ? 1.6 : 1
                    shape.stroke()
                    Self.text("\(minutes)", in: NSRect(x: rect.minX, y: rect.midY - 8.5, width: rect.width, height: 17),
                              font: font, color: selected ? .white : Paper.ink, alignment: .center)
                }
                x += cw + 8
            }
            y += 30 + 8
        }
        y += 4

        // Avvia
        let isFocus = dialKind == .focus
        let title = isFocus ? "Avvia il focus" : "Avvia la pausa"
        add(NSRect(x: pad, y: y, width: inner, height: 42), label: title, close: true, { [weak self] in
            guard let self else { return }
            if let item = self.todoFocus { self.actions.todoStartFocus(item.id, self.dialMinutes) }
            else if self.dialKind == .focus { self.actions.startFocus(self.dialMinutes) } else { self.actions.startBreak(self.dialMinutes) }
        }) { rect, pressed, hovered in
            let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: rect.height / 2, yRadius: rect.height / 2)
            (pressed ? Paper.accentPressed : Paper.accent).setFill()
            shape.fill()
            _ = hovered
            let font = Paper.markerFont(18)
            let textWidth = (title as NSString).size(withAttributes: [.font: font]).width
            let startX = rect.midX - (24 + textWidth) / 2
            if let play = Paper.symbolImage("play.fill", size: 13, color: .white) {
                let size = play.size
                play.draw(in: NSRect(x: startX, y: rect.midY - size.height / 2, width: size.width, height: size.height), from: .zero,
                          operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            Self.text(title, in: NSRect(x: startX + 24, y: rect.midY - 12, width: textWidth + 6, height: 24),
                      font: font, color: .white)
        }
        y += 42 + 10

        if s.phase != nil {
            add(NSRect(x: pad, y: y, width: inner, height: 22), label: "Ferma il timer", { [weak self] in
                self?.actions.stopTimer()
                self?.rebuild()
            }) { rect, pressed, hovered in
                Self.text("Ferma il timer in corso (\(s.remaining))", in: rect, font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
                          color: hovered || pressed ? Paper.ink : Paper.inkLight, alignment: .center)
            }
            y += 24
        }
        y += 10

        setFrameSize(NSSize(width: w, height: y))
        needsDisplay = true
        onResize?(y)
    }

    // MARK: - Aggiornamento dal vivo

    /// Ogni secondo mentre è aperta: il tempo che scorre. Se il timer è partito o finito si ricostruisce.
    func refreshLive() {
        let s = live()
        if s.phase != shownPhase || (s.phase != nil) != shownRunning {
            page = Self.defaultPage(for: s.phase)
            rebuild()
            return
        }
        if s.isPaused != shownPaused {
            rebuild()
            return
        }
        clockLabel?.stringValue = s.remaining
        if let tomato {
            tomato.big = s.remaining
            tomato.progress = s.focusProgress
        }
    }
}

// MARK: - Le schermate del focus e della pausa

private extension MenuCardView {
    /// Il titolo e la riga sotto, con il compagno a destra (un tocco e parla).
    func addHeader(_ s: MenuCardState, title: String, detail: String, top: CGFloat) {
        let w = Self.width, pad: CGFloat = 22
        _ = label(title, font: Paper.markerFont(24), alignment: .left, frame: NSRect(x: pad, y: top + 50, width: w - pad - 78, height: 32))
        _ = label(detail, font: NSFont.systemFont(ofSize: 11), color: Paper.inkLight, alignment: .left,
                  frame: NSRect(x: pad, y: top + 84, width: w - pad - 70, height: 16))
        addAvatar(s, frame: NSRect(x: w - 22 - 44, y: top + 48, width: 44, height: 44))
    }

    /// I quattro puntini del ciclo («Focus 2 di 4»): i fatti pieni, il corrente con il contorno.
    func addCycle(done: Int, highlightsNext: Bool, text: String, top: CGFloat) {
        let view = CycleDotsView(frame: NSRect(x: 22, y: top + 106, width: Self.width - 44, height: 16))
        view.done = done
        view.highlightsNext = highlightsNext
        view.text = text
        addSubview(view)
    }

    /// Il pomodoro al centro (la sua cima sta sotto l'intestazione).
    func addTomato(_ s: MenuCardState, ring: NSColor, small: String, top: CGFloat) {
        let view = FocusTomatoView(frame: NSRect(x: 0, y: top + 128, width: Self.width, height: FocusTomatoView.size.height))
        view.progress = s.focusProgress
        view.big = s.remaining
        view.small = small
        view.ring = ring
        addSubview(view)
        tomato = view
    }

    /// «+ 5 minuti» e (Ferma | Salta): i due pulsanti adesivi affiancati.
    func addStickerPair(top: CGFloat, secondTitle: String, secondIcon: FocusDraw.Icon, secondFill: NSColor = Paper.paper,
                        secondAction: @escaping () -> Void) {
        let w = Self.width, pad: CGFloat = 22
        let y = top + 378
        let half = w / 2
        add(NSRect(x: pad, y: y, width: half - 8 - pad + 4, height: 40), label: "Aggiungi \(Pomodoro.extensionMinutes) minuti", { [weak self] in
            self?.actions.addMinutes()
            self?.rebuild()
        }) { rect, pressed, hovered in
            FocusDraw.sticker(in: rect, fill: Paper.accent, label: "\(Pomodoro.extensionMinutes) minuti", textColor: .white,
                              icon: .plus, pressed: pressed, hovered: hovered)
        }
        add(NSRect(x: half + 8, y: y, width: w - 22 - 4 - half - 8 + 4, height: 40), label: secondTitle, { [weak self] in
            secondAction()
            self?.rebuild()
        }) { rect, pressed, hovered in
            FocusDraw.sticker(in: rect, fill: secondFill, label: secondTitle, textColor: Paper.ink, icon: secondIcon,
                              pressed: pressed, hovered: hovered)
        }
    }

    func addMenuLink(y: CGFloat) {
        add(NSRect(x: 18, y: y, width: 130, height: 24), label: "Torna alla scheda completa", { [weak self] in
            self?.page = .main
            self?.rebuild()
        }) { rect, pressed, hovered in
            Self.text("‹  Menu completo", in: NSRect(x: rect.minX + 4, y: rect.midY - 8.5, width: rect.width, height: 17),
                      font: NSFont.systemFont(ofSize: 11.5), color: hovered || pressed ? Paper.ink : Paper.inkLight)
        }
    }

    func finish(height: CGFloat) {
        setFrameSize(NSSize(width: Self.width, height: height))
        needsDisplay = true
        onResize?(height)
    }

    // MARK: Focus

    func buildFocus(_ s: MenuCardState) {
        let pad: CGFloat = 22, inner = Self.width - 44
        let top = Self.pageTop
        addHeader(s, title: s.subject ?? "Focus", detail: "\(s.phaseRange)  ·  \(s.focusMinutes) minuti", top: top)
        if let done = s.cycleDone {
            let current = min(done + 1, BreakCycle.focusesPerCycle)
            addCycle(done: done, highlightsNext: true, text: "Focus \(current) di \(BreakCycle.focusesPerCycle)", top: top)
        }
        addTomato(s, ring: Paper.accent, small: s.isPaused ? "fermo" : "rimasti", top: top)
        addStickerPair(top: top, secondTitle: s.isPaused ? "Riprendi" : "Ferma", secondIcon: s.isPaused ? .play : .stop,
                       secondFill: s.isPaused ? FocusPalette.chipOn : Paper.paper) { [weak self] in self?.actions.togglePause() }

        // Da fermo c'è anche «Termina e salva»: chiude il focus tenendo i minuti fatti.
        var below = top
        if s.isPaused {
            let title = "Termina e salva"
            add(NSRect(x: pad, y: top + 424, width: inner, height: 24), label: "Termina il focus e salvalo", close: true,
                actions.stopTimer) { rect, pressed, hovered in
                let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
                let tw = (title as NSString).size(withAttributes: [.font: font]).width
                let start = rect.midX - (20 + tw) / 2
                let color = pressed ? Paper.accentPressed : hovered ? Paper.accentPressed : Paper.accent
                if let check = Paper.symbolImage("checkmark.circle", size: 14, color: color) {
                    let size = check.size
                    check.draw(in: NSRect(x: start, y: rect.midY - size.height / 2, width: size.width, height: size.height),
                               from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
                Self.text(title, in: NSRect(x: start + 20, y: rect.midY - 8.5, width: tw + 6, height: 17), font: font, color: color)
            }
            below += 30
        }

        // Il sottofondo: uno alla volta, e il volume.
        _ = label("Sottofondo", font: Paper.markerFont(19), alignment: .left, frame: NSRect(x: pad, y: below + 442, width: 160, height: 26))
        let choices = BackgroundChoice.allCases
        let gap: CGFloat = 5
        let chipWidth = (inner - gap * CGFloat(choices.count - 1)) / CGFloat(choices.count)
        for (i, choice) in choices.enumerated() {
            let on = s.background == choice
            let frame = NSRect(x: pad + CGFloat(i) * (chipWidth + gap), y: below + 474, width: chipWidth, height: 24)
            add(frame, label: "Sottofondo: \(choice.title)", { [weak self] in
                self?.actions.setBackground(choice)
                self?.rebuild()
            }) { rect, pressed, hovered in
                let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.6, dy: 0.6), xRadius: 11.4, yRadius: 11.4)
                (on ? FocusPalette.chipOn : pressed ? Paper.accent.withAlphaComponent(0.3)
                    : hovered ? Paper.accent.withAlphaComponent(0.14) : Paper.paper).setFill()
                shape.fill()
                (on ? Paper.accent : Paper.paperEdge).setStroke()
                shape.lineWidth = on ? 1.4 : 1.1
                shape.stroke()
                Self.text(choice.title, in: NSRect(x: rect.minX, y: rect.midY - 7, width: rect.width, height: 14),
                          font: NSFont.systemFont(ofSize: 9.5, weight: on ? .semibold : .regular), color: Paper.ink, alignment: .center)
            }
        }
        if s.background == .none {
            _ = label("Scegli un suono o la musica per concentrarti.", font: NSFont.systemFont(ofSize: 11), color: Paper.inkLight,
                      frame: NSRect(x: pad, y: below + 506, width: inner, height: 16))
        } else {
            let slider = VolumeSlider(frame: NSRect(x: pad, y: below + 502, width: inner, height: 28))
            slider.value = s.backgroundVolume
            slider.onChange = { [weak self] in self?.actions.setBackgroundVolume($0) }
            addSubview(slider)
        }

        // Le note: un foglietto.
        let noteTop = below + 544
        let noteHeight = PostItView.height(noteCount: s.notes.count)
        let postit = PostItView(frame: NSRect(x: pad - 2, y: noteTop, width: inner + 4, height: noteHeight))
        postit.setNotes(s.notes)
        postit.field.stringValue = draftNote
        postit.onSubmit = { [weak self] text in
            guard let self else { return }
            self.draftNote = ""
            self.actions.addNote(text)
            self.rebuild()
            self.window?.makeFirstResponder(self.noteField)
        }
        addSubview(postit)
        noteField = postit.field

        // Elimina questo focus
        let deleteY = noteTop + noteHeight + 14
        add(NSRect(x: pad, y: deleteY, width: inner, height: 36), label: "Elimina questo focus", close: true, actions.discardFocus) {
            rect, pressed, hovered in
            let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.8, dy: 0.8), xRadius: rect.height / 2, yRadius: rect.height / 2)
            (pressed ? FocusPalette.dangerEdge.withAlphaComponent(0.55)
                : hovered ? FocusPalette.dangerFill.blended(withFraction: 0.35, of: FocusPalette.dangerEdge) ?? FocusPalette.dangerFill
                : FocusPalette.dangerFill).setFill()
            shape.fill()
            FocusPalette.dangerEdge.setStroke()
            shape.lineWidth = 1.6
            shape.stroke()
            let title = "Elimina questo focus"
            let font = NSFont.systemFont(ofSize: 13)
            let tw = (title as NSString).size(withAttributes: [.font: font]).width
            let start = rect.midX - (22 + tw) / 2
            FocusDraw.trash(centerX: start + 8, centerY: rect.midY, color: FocusPalette.danger)
            Self.text(title, in: NSRect(x: start + 22, y: rect.midY - 8.5, width: tw + 6, height: 17), font: font, color: FocusPalette.danger)
        }

        let linkY = deleteY + 36 + 12
        addMenuLink(y: linkY)
        finish(height: linkY + 24 + 14)
    }

    // MARK: Pausa

    func buildRest(_ s: MenuCardState) {
        let w = Self.width, pad: CGFloat = 22, inner = Self.width - 44
        let top = Self.pageTop
        let detail: String
        if let minutes = s.lastFocusMinutes {
            detail = "Hai fatto \(minutes) minuti" + (s.lastFocusSubject.map { " di \($0)" } ?? "")
        } else {
            detail = "Stacca un attimo."
        }
        addHeader(s, title: s.isLongBreak ? "Pausa lunga" : "Pausa", detail: detail, top: top)
        if let done = s.cycleDone {
            let text = s.isLongBreak ? "\(done) di \(BreakCycle.focusesPerCycle): ciclo completo"
                                     : "\(done) di \(BreakCycle.focusesPerCycle) fatti"
            addCycle(done: done, highlightsNext: false, text: text, top: top)
        }
        addTomato(s, ring: FocusPalette.rest, small: "di pausa", top: top)
        addStickerPair(top: top, secondTitle: "Salta", secondIcon: .skip) { [weak self] in self?.actions.stopTimer() }

        _ = label(s.isLongBreak ? "Alzati e muoviti un po': è una pausa lunga." : "Bevi un po' d'acqua e guarda lontano.", font: NSFont.systemFont(ofSize: 12.5), frame: NSRect(x: pad, y: top + 448, width: inner, height: 20))

        // Un altro focus
        let again = s.lastFocusMinutes ?? 50
        let title = "Nuovo focus · \(again) min"
        add(NSRect(x: pad, y: top + 486, width: inner + 4, height: 52), label: title, close: true, { [weak self] in
            self?.actions.startFocus(again)
        }) { rect, pressed, hovered in
            FocusDraw.sticker(in: rect, fill: Paper.accent, label: title, textColor: .white, icon: .none, pressed: pressed, hovered: hovered)
        }

        var y = top + 570
        if s.lastSessionID != nil {
            if let rating = s.lastRating {
                _ = label("Com'è andata?", font: Paper.markerFont(19), alignment: .left, frame: NSRect(x: pad, y: y, width: 200, height: 26))
                let faceRect = NSRect(x: pad + 2, y: y + 38, width: 30, height: 30)
                add(faceRect, label: "Com'è andata: \(rating.title)", {}) { rect, _, _ in
                    FaceIcon.draw(rating, in: rect, flipped: true, emphasized: true)
                }
                _ = label("Segnato: \(rating.title)", font: NSFont.systemFont(ofSize: 12.5), color: Paper.inkLight, alignment: .left,
                          frame: NSRect(x: pad + 42, y: y + 46, width: inner - 42, height: 16))
                y += 82
            } else {
                _ = label("Com'è andata?", font: Paper.markerFont(19), alignment: .left, frame: NSRect(x: pad, y: y, width: 200, height: 26))
                for (i, rating) in FocusRating.allCases.enumerated() {
                    let cx = w / 2 + CGFloat(i - 1) * 95
                    let frame = NSRect(x: cx - 40, y: y + 34, width: 80, height: 62)
                    add(frame, label: rating.title, { [weak self] in
                        self?.actions.rateLast(rating)
                        self?.rebuild()
                    }) { rect, pressed, hovered in
                        let size: CGFloat = pressed ? 28 : hovered ? 36 : 32
                        FaceIcon.draw(rating, in: NSRect(x: rect.midX - size / 2, y: rect.minY + 4 + (36 - size) / 2, width: size, height: size),
                                      flipped: true, emphasized: hovered)
                        Self.text(rating.title, in: NSRect(x: rect.minX, y: rect.minY + 42, width: rect.width, height: 15),
                                  font: NSFont.systemFont(ofSize: 10.5, weight: hovered ? .semibold : .regular),
                                  color: hovered ? Paper.ink : Paper.inkLight, alignment: .center)
                    }
                }
                y += 104
            }
        }

        // In fondo: la scheda completa, il giardino e le statistiche.
        let footY = y + 10
        addMenuLink(y: footY)
        let small = NSFont.systemFont(ofSize: 11)
        let gardenW = ceil(("Giardino" as NSString).size(withAttributes: [.font: small]).width)
        let statsW = ceil(("Statistiche" as NSString).size(withAttributes: [.font: small]).width)
        let dotW: CGFloat = 16
        let statsX = w - pad - statsW
        let gardenX = statsX - dotW - gardenW
        for (title, x, width, action) in [("Giardino", gardenX, gardenW, actions.showGarden), ("Statistiche", statsX, statsW, actions.showStats)] {
            add(NSRect(x: x - 3, y: footY, width: width + 6, height: 24), label: title, close: true, action) { rect, pressed, hovered in
                Self.text(title, in: NSRect(x: rect.minX + 3, y: rect.midY - 8, width: width + 2, height: 16), font: small,
                          color: hovered || pressed ? Paper.ink : Paper.inkLight)
            }
        }
        _ = label("·", font: small, color: Paper.inkLight, frame: NSRect(x: gardenX + gardenW, y: footY + 4, width: dotW, height: 16))
        finish(height: footY + 24 + 14)
    }
}

/// Mostra e nasconde la scheda del menu: un pannello senza bordi, chiuso da un clic fuori o da Esc.
final class MenuCard: NSObject {
    private let provide: () -> MenuCardState
    private let live: () -> MenuCardLiveState
    private let actions: MenuCardActions
    private var panel: KeyablePanel?
    private var content: MenuCardView?
    private var topLeft = NSPoint.zero
    /// Se la scheda sta accanto al personaggio, lo segue quando si muove: la finestra seguita e da che lato sta.
    private var followed: NSWindow?
    private var onLeft = true
    private var moveObservers: [NSObjectProtocol] = []
    private var ticker: Timer?
    private var monitors: [Any] = []
    private var resignObserver: NSObjectProtocol?

    init(state: @escaping () -> MenuCardState, live: @escaping () -> MenuCardLiveState, actions: MenuCardActions) {
        self.provide = state
        self.live = live
        self.actions = actions
        super.init()
    }

    var isShowing: Bool { panel != nil }

    enum Anchor {
        /// Sotto a questo rettangolo (l'icona nella barra dei menu), in coordinate dello schermo.
        case below(NSRect)
        /// Di fianco a questa finestra (il personaggio), a sinistra o a destra dove c'è posto; la segue se si muove.
        case beside(NSWindow)
    }

    /// Quando si è chiusa l'ultima volta: un clic sull'icona mentre è aperta la chiude (dal controllo dei clic
    /// fuori) e subito dopo arriva la sua azione, che non deve riaprirla.
    private var closedAt = Date.distantPast

    func toggle(anchor: Anchor) {
        if isShowing {
            close()
        } else if Date().timeIntervalSince(closedAt) > 0.3 {
            show(anchor: anchor)
        }
    }

    /// Dove si è aperta l'ultima volta: per riaprirla da qui quando si torna indietro da un'altra schermata.
    private var lastAnchor: Anchor?

    /// Riapre la scheda dov'era (o, se non c'era, di fianco al personaggio dato).
    func reopen(fallback: Anchor) {
        show(anchor: lastAnchor ?? fallback)
    }

    func show(anchor: Anchor) {
        guard panel == nil else { return }
        lastAnchor = anchor
        let view = MenuCardView(
            state: provide, live: live, actions: actions,
            perform: { [weak self] close, action in
                if close { self?.close() }
                action()
            }
        )
        let size = view.frame.size

        let panel = KeyablePanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                                 backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false          // la carta ha il suo bordo; l'ombra del pannello coprirebbe anche il compagno
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = view
        panel.appearance = NSAppearance(named: .aqua)
        panel.onCancel = { [weak self] in self?.close() }

        self.panel = panel
        content = view

        switch anchor {
        case .below(let rect):
            followed = nil
            let screen = Self.visibleFrame(containing: rect)
            topLeft = Self.clamp(NSPoint(x: rect.midX - size.width / 2, y: rect.minY - 6), size: size, in: screen)
            panel.setFrameTopLeftPoint(topLeft)
        case .beside(let window):
            followed = window
            onLeft = true
            reposition()
            // La scheda sta accanto al personaggio anche quando cammina o lo trascini.
            let center = NotificationCenter.default
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                moveObservers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.reposition()
                })
            }
        }

        view.onResize = { [weak self, weak panel] height in
            guard let self, let panel else { return }
            panel.setContentSize(NSSize(width: MenuCardView.width, height: height))
            if self.followed != nil {
                self.reposition()
            } else {
                panel.setFrameTopLeftPoint(self.topLeft)
            }
        }

        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
        // Si chiude con un clic fuori (anche in altre app) o quando perde la tastiera.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
                                                          handler: { [weak self] _ in self?.close() }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
                                                        handler: { [weak self] event in
            if let self, let panel = self.panel, event.window !== panel { self.close() }
            return event
        }) {
            monitors.append(local)
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) {
            [weak self] _ in self?.close()
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.content?.refreshLive() }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private static func visibleFrame(containing rect: NSRect) -> NSRect {
        NSScreen.screens.first(where: { $0.frame.intersects(rect) })?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
    }

    /// Tiene l'angolo in alto a sinistra dentro lo schermo.
    private static func clamp(_ point: NSPoint, size: NSSize, in screen: NSRect) -> NSPoint {
        NSPoint(x: min(max(point.x, screen.minX + 8), screen.maxX - size.width - 8),
                y: min(max(point.y, screen.minY + size.height + 8), screen.maxY))
    }

    /// Mette la scheda accanto al personaggio: dal lato in cui già sta, se c'è posto (altrimenti dall'altro),
    /// con il bordo basso allineato ai suoi piedi.
    private func reposition() {
        guard let panel, let pet = followed else { return }
        let size = panel.frame.size
        let rect = pet.frame
        let screen = Self.visibleFrame(containing: rect)
        let gap: CGFloat = 10
        var x = onLeft ? rect.minX - size.width - gap : rect.maxX + gap
        if onLeft, x < screen.minX + 8 {
            onLeft = false
            x = rect.maxX + gap
        } else if !onLeft, x + size.width > screen.maxX - 8 {
            onLeft = true
            x = rect.minX - size.width - gap
        }
        topLeft = Self.clamp(NSPoint(x: x, y: rect.minY + size.height), size: size, in: screen)
        panel.setFrameTopLeftPoint(topLeft)
    }

    func close() {
        guard let panel else { return }
        closedAt = Date()
        moveObservers.forEach { NotificationCenter.default.removeObserver($0) }
        moveObservers = []
        followed = nil
        self.panel = nil
        content = nil
        ticker?.invalidate()
        ticker = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    /// La scheda disegnata in un'immagine (per le anteprime).
    var contentView: NSView? { content }
}


/// Il quadrante del timer: un pomodoro da girare. Si trascina il pallino (o si usa la rotella) per scegliere i minuti.
private final class TimerDial: NSView {
    override var isFlipped: Bool { true }

    var minutes = 50 { didSet { needsDisplay = true } }
    var maxMinutes = 120 { didSet { needsDisplay = true } }
    var step = 5
    /// Il massimo che la rotella può raggiungere (più del giro intero: un timer tuo può essere più lungo).
    var hardMax = 180
    var onChange: ((Int) -> Void)?

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let c = NSPoint(x: bounds.midX, y: bounds.midY + 4)
        let outer = bounds.width / 2 - 14
        let ring: CGFloat = outer - 10

        // Il picciolo e le foglie in cima, come il logo.
        let leaf = NSColor(calibratedRed: 0.48, green: 0.60, blue: 0.35, alpha: 1)
        let top = c.y - outer
        for sign: CGFloat in [-1, 1] {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: c.x, y: top + 3))
            path.curve(to: NSPoint(x: c.x + sign * 20, y: top - 3),
                       controlPoint1: NSPoint(x: c.x + sign * 6, y: top - 12), controlPoint2: NSPoint(x: c.x + sign * 16, y: top - 12))
            path.curve(to: NSPoint(x: c.x, y: top + 3),
                       controlPoint1: NSPoint(x: c.x + sign * 16, y: top + 6), controlPoint2: NSPoint(x: c.x + sign * 6, y: top + 6))
            leaf.setFill()
            path.fill()
            Paper.ink.setStroke()
            path.lineWidth = 1.2
            path.stroke()
        }
        let stem = NSBezierPath(roundedRect: NSRect(x: c.x - 2.5, y: top - 14, width: 5, height: 14), xRadius: 2, yRadius: 2)
        leaf.setFill()
        stem.fill()
        Paper.ink.setStroke()
        stem.lineWidth = 1.2
        stem.stroke()

        // Il quadrante
        let face = NSBezierPath(ovalIn: NSRect(x: c.x - outer, y: c.y - outer, width: 2 * outer, height: 2 * outer))
        NSColor(calibratedRed: 1.0, green: 0.99, blue: 0.94, alpha: 1).setFill()
        face.fill()
        Paper.ink.setStroke()
        face.lineWidth = 2
        face.stroke()

        // La pista e la parte già girata
        let track = NSBezierPath(ovalIn: NSRect(x: c.x - ring, y: c.y - ring, width: 2 * ring, height: 2 * ring))
        Paper.track.setStroke()
        track.lineWidth = 12
        track.stroke()
        let fraction = TimerDialMath.filledFraction(minutes: minutes, maxMinutes: maxMinutes)
        let arc = NSBezierPath()
        let steps = max(Int(fraction * 120), 2)
        for i in 0...steps {
            let angle = -CGFloat.pi / 2 + CGFloat(fraction) * 2 * .pi * CGFloat(i) / CGFloat(steps)
            let p = NSPoint(x: c.x + ring * cos(angle), y: c.y + ring * sin(angle))
            if i == 0 { arc.move(to: p) } else { arc.line(to: p) }
        }
        Paper.accent.setStroke()
        arc.lineWidth = 12
        arc.lineCapStyle = .round
        arc.stroke()

        // Il pallino
        let end = -CGFloat.pi / 2 + CGFloat(fraction) * 2 * .pi
        let knob = NSRect(x: c.x + ring * cos(end) - 9, y: c.y + ring * sin(end) - 9, width: 18, height: 18)
        let knobPath = NSBezierPath(ovalIn: knob)
        NSColor(calibratedRed: 1.0, green: 0.99, blue: 0.94, alpha: 1).setFill()
        knobPath.fill()
        Paper.accent.setStroke()
        knobPath.lineWidth = 3
        knobPath.stroke()

        // I minuti
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        ("\(minutes)" as NSString).draw(in: NSRect(x: c.x - 50, y: c.y - 30, width: 100, height: 48),
                                       withAttributes: [.font: Paper.markerFont(40), .foregroundColor: Paper.ink, .paragraphStyle: para])
        ("minuti" as NSString).draw(in: NSRect(x: c.x - 50, y: c.y + 18, width: 100, height: 16),
                                   withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: Paper.inkLight, .paragraphStyle: para])
    }

    private func update(from event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let dx = p.x - bounds.midX, dy = p.y - (bounds.midY + 4)
        guard hypot(dx, dy) > 16 else { return }
        var fraction = atan2(dx, -dy) / (2 * .pi)
        if fraction < 0 { fraction += 1 }
        let new = TimerDialMath.minutes(fraction: Double(fraction), previous: minutes, maxMinutes: maxMinutes, step: step)
        if new != minutes {
            minutes = new
            onChange?(new)
        }
    }

    override func mouseDown(with event: NSEvent) { update(from: event) }
    override func mouseDragged(with event: NSEvent) { update(from: event) }

    /// La rotella (o due dita sul trackpad) aggiunge o toglie un minuto alla volta.
    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.5 else { return }
        let new = min(max(minutes + (delta > 0 ? 1 : -1), 1), hardMax)
        if new != minutes {
            minutes = new
            onChange?(new)
        }
    }
}


/// Un cursore orizzontale (0...1): si trascina, o si tocca nel punto che si vuole. Disegnato a mano, come il resto.
private final class VolumeSlider: NSView {
    override var isFlipped: Bool { true }
    var value: Double = 0.25 { didSet { needsDisplay = true } }
    var onChange: ((Double) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }

    private var track: NSRect { NSRect(x: 8, y: bounds.midY - 2.5, width: bounds.width - 16, height: 5) }

    override func draw(_ dirtyRect: NSRect) {
        let t = track
        Paper.track.setFill()
        NSBezierPath(roundedRect: t, xRadius: 2.5, yRadius: 2.5).fill()
        let filled = NSRect(x: t.minX, y: t.minY, width: t.width * CGFloat(value), height: t.height)
        Paper.accent.setFill()
        NSBezierPath(roundedRect: filled, xRadius: 2.5, yRadius: 2.5).fill()
        let knob = NSBezierPath(ovalIn: NSRect(x: t.minX + t.width * CGFloat(value) - 8, y: bounds.midY - 8, width: 16, height: 16))
        NSColor(calibratedRed: 1.0, green: 0.99, blue: 0.94, alpha: 1).setFill()
        knob.fill()
        Paper.accent.setStroke()
        knob.lineWidth = 2
        knob.stroke()
    }

    private func update(from event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        let new = AmbientSettings.clamp(Double((x - track.minX) / track.width))
        if abs(new - value) > 0.005 {
            value = new
            onChange?(new)
        }
    }

    override func mouseDown(with event: NSEvent) { update(from: event) }
    override func mouseDragged(with event: NSEvent) { update(from: event) }
}
