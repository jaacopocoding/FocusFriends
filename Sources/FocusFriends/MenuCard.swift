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
}

/// Cosa succede quando si tocca qualcosa. Il MenuController le collega a quello che già fa il menu.
struct MenuCardActions {
    var startFocus: (Int) -> Void
    var startBreak: (Int) -> Void
    var stopTimer: () -> Void
    var selectPet: (Pet) -> Void
    var showStats: () -> Void
    var showGarden: () -> Void
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
    private let actions: MenuCardActions
    /// Chiude la scheda (se `close`) e poi esegue l'azione.
    private let perform: (_ close: Bool, _ action: () -> Void) -> Void
    var onResize: ((CGFloat) -> Void)?

    private enum Page { case main, timers }
    private var page: Page = .main
    /// Il quadrante dei timer: tiene il suo valore mentre lo si trascina (la pagina intorno si ricostruisce).
    private var dial: TimerDial?
    private var dialKind: CustomTimers.Kind = .focus
    private var dialMinutes = 50
    private var timerMessage: String?

    private var statusLabel: NSTextField?
    private var clockLabel: NSTextField?
    private var shownPhase: Pomodoro.Phase?
    private var shownRunning = false

    init(state: @escaping () -> MenuCardState, actions: MenuCardActions,
         perform: @escaping (_ close: Bool, _ action: () -> Void) -> Void) {
        self.provide = state
        self.actions = actions
        self.perform = perform
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 400))
        appearance = NSAppearance(named: .aqua)
        rebuild()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Disegno della carta

    override func draw(_ dirtyRect: NSRect) {
        let card = NSRect(x: 1, y: Self.overflow, width: bounds.width - 2, height: bounds.height - Self.overflow - 1)
        let shape = NSBezierPath(roundedRect: card, xRadius: 20, yRadius: 20)
        Paper.paper.setFill()
        shape.fill()
        Paper.paperEdge.setStroke()
        shape.lineWidth = 1.5
        shape.stroke()
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

    // MARK: - Costruzione

    /// Ricostruisce tutta la scheda dallo stato attuale (dopo un tocco, o quando cambia fase del timer).
    func rebuild() {
        for view in subviews where !(page == .timers && view === dial) { view.removeFromSuperview() }
        if page == .main { dial = nil }
        statusLabel = nil
        clockLabel = nil
        let s = provide()
        shownPhase = s.phase
        shownRunning = s.phase != nil
        if page == .timers {
            buildTimers(s)
            return
        }

        let w = Self.width
        let pad = Self.pad
        let inner = w - 2 * pad
        var y = Self.overflow + 42

        // Il compagno che sbuca: un tocco e parla.
        let avatarFrame = NSRect(x: w / 2 - Self.avatar / 2, y: 0, width: Self.avatar, height: Self.avatar)
        let icon = MenuController.menuIcon(for: s.pet, height: 160)
        let focus = s.pet.iconFocus
        add(avatarFrame, label: "Fai parlare \(s.pet.name)", close: true, actions.speak) { rect, pressed, hovered in
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

        // Saluto e stato
        let greeting = s.userName.map { "Ciao \($0)" } ?? "Ciao!"
        _ = label(greeting, font: Paper.markerFont(20), frame: NSRect(x: pad, y: y, width: inner, height: 26))
        y += 27
        statusLabel = label(statusText(s), font: NSFont.systemFont(ofSize: 12), color: Paper.inkLight,
                            frame: NSRect(x: pad, y: y, width: inner, height: 16))
        y += 24

        // I compagni: tre nomi, quello scelto sottolineato.
        y = addCompanions(s, y: y)
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
            ("\(s.streak)", s.streak == 1 ? "giorno di fila" : "di fila"),
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
        case .rest?: return "Pausa"
        case nil: return s.isPetVisible ? "\(s.pet.name) è qui con te" : "\(s.pet.name) è nascosto"
        }
    }

    private func addCompanions(_ s: MenuCardState, y: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let separator: CGFloat = 20
        let widths = s.allPets.map { ceil(($0.name as NSString).size(withAttributes: [.font: font]).width) + 8 }
        let total = widths.reduce(0, +) + separator * CGFloat(max(widths.count - 1, 0))
        var x = (Self.width - total) / 2
        for (i, pet) in s.allPets.enumerated() {
            let selected = pet.id == s.pet.id
            let frame = NSRect(x: x, y: y, width: widths[i], height: 20)
            add(frame, label: "Compagno: \(pet.name)", { [weak self] in self?.actions.selectPet(pet); self?.rebuild() }) { rect, pressed, hovered in
                Self.text(pet.name, in: NSRect(x: rect.minX + 4, y: rect.minY, width: rect.width - 4, height: 17),
                          font: font, color: selected || hovered || pressed ? Paper.ink : Paper.inkLight)
                if selected {
                    Paper.accent.setFill()
                    NSBezierPath(roundedRect: NSRect(x: rect.minX + 4, y: rect.maxY - 3, width: rect.width - 8, height: 2.5),
                                 xRadius: 1.2, yRadius: 1.2).fill()
                }
            }
            x += widths[i]
            if i < s.allPets.count - 1 {
                let dot = label("·", font: NSFont.systemFont(ofSize: 13), color: Paper.inkLight,
                                frame: NSRect(x: x, y: y, width: separator, height: 17))
                dot.alignment = .center
                x += separator
            }
        }
        return y + 20
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

    // MARK: - La pagina dei timer

    private var dialMax: Int { dialKind == .focus ? 120 : 30 }
    private var dialStep: Int { dialKind == .focus ? 5 : 1 }

    /// "‹ Gira il timer": il quadrante da girare per scegliere i minuti, i timer salvati e Avvia.
    private func buildTimers(_ s: MenuCardState) {
        let w = Self.width
        let pad = Self.pad
        let inner = w - 2 * pad
        var y = Self.overflow + 14

        // Intestazione con la freccia indietro
        add(NSRect(x: pad - 6, y: y, width: 36, height: 30), label: "Torna alla scheda", { [weak self] in
            self?.page = .main
            self?.rebuild()
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
            if self.dialKind == .focus { self.actions.startFocus(self.dialMinutes) } else { self.actions.startBreak(self.dialMinutes) }
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
        let s = provide()
        if s.phase != shownPhase || (s.phase != nil) != shownRunning {
            rebuild()
            return
        }
        clockLabel?.stringValue = s.remaining
    }
}

/// Mostra e nasconde la scheda del menu: un pannello senza bordi, chiuso da un clic fuori o da Esc.
final class MenuCard: NSObject {
    private let provide: () -> MenuCardState
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

    init(state: @escaping () -> MenuCardState, actions: MenuCardActions) {
        self.provide = state
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
            state: provide, actions: actions,
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
