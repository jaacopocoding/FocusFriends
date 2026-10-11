import AppKit

/// Il giardino: ogni focus finito è una piantina, che cresce con i minuti studiati. Una aiuola per giorno;
/// la scheda "Settimana" le mostra grandi, "Mese" in un calendario. Si ricava tutto dal registro delle sessioni.
final class GardenView: NSView, NSViewToolTipOwner {
    static let size = NSSize(width: 1000, height: 580)
    private static let margin: CGFloat = 28

    override var isFlipped: Bool { true }

    private let log: SessionLog
    private let now: () -> Date
    private let calendar = StudyPeriod.calendar()

    private var kind: PeriodKind = .week
    private var period: StudyPeriod

    /// Una piantina disegnata: dove, di che stadio, di quale sessione.
    private struct Plant {
        var rect: NSRect
        var stage: Int
        var session: StudySession
        var showsDot: Bool
    }
    private struct Bed {
        var rect: NSRect
        var dayLabel: String
        var dayLabelPoint: NSPoint
        var total: String?
        var extra: Int
        var isToday: Bool
        var anchor: NSPoint
    }
    private var plants: [Plant] = []
    private var beds: [Bed] = []
    private var totalPlants = 0
    private var totalSeconds = 0
    private var streak = 0
    /// Le immagini già caricate: "pianty-3", "porcellino-5"... Ogni personaggio può avere la sua collezione
    /// (`garden_<personaggio>_<stadio>.png`); chi non ce l'ha usa le piantine di Pianty.
    private var imageCache: [String: NSImage] = [:]

    private let segmented = NSSegmentedControl(labels: ["Settimana", "Mese"], trackingMode: .selectOne, target: nil, action: nil)
    private let previousButton = NSButton()
    private let nextButton = NSButton()

    init(log: SessionLog, now: @escaping () -> Date = Date.init) {
        self.log = log
        self.now = now
        self.period = StudyPeriod.containing(now(), kind: .week)
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        appearance = NSAppearance(named: .aqua)

        segmented.selectedSegment = 0
        segmented.segmentStyle = .rounded
        segmented.target = self
        segmented.action = #selector(kindChanged)
        segmented.frame = NSRect(x: Self.margin, y: 18, width: 190, height: 26)
        addSubview(segmented)

        for (button, symbol, action) in [(previousButton, "chevron.left", #selector(goPrevious)), (nextButton, "chevron.right", #selector(goNext))] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.isBordered = false
            button.contentTintColor = Paper.ink
            button.target = self
            button.action = action
            addSubview(button)
        }
        previousButton.frame = NSRect(x: Self.margin, y: 58, width: 32, height: 28)
        nextButton.frame = NSRect(x: Self.size.width - Self.margin - 32, y: 58, width: 32, height: 28)

        log.addObserver { [weak self] in self?.reload() }
        reload()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Dati e disposizione

    func select(_ newKind: PeriodKind) {
        kind = newKind == .month ? .month : .week
        segmented.selectedSegment = kind == .month ? 1 : 0
        period = StudyPeriod.containing(now(), kind: kind, calendar: calendar)
        reload()
    }

    @objc private func kindChanged() {
        select(segmented.selectedSegment == 1 ? .month : .week)
    }

    @objc private func goPrevious() {
        period = period.shifted(by: -1, calendar: calendar)
        reload()
    }

    @objc private func goNext() {
        guard !period.contains(now()) else { return }
        period = period.shifted(by: 1, calendar: calendar)
        reload()
    }

    func reload() {
        let today = now()
        nextButton.isEnabled = !period.contains(today)
        nextButton.alphaValue = period.contains(today) ? 0.25 : 1
        streak = StudyStats.streak(sessions: log.sessions, now: today, calendar: calendar)

        let inPeriod = log.sessions.filter { period.contains($0.start) }
        totalPlants = inPeriod.count
        totalSeconds = inPeriod.reduce(0) { $0 + $1.seconds }

        plants = []
        beds = []
        removeAllToolTips()
        if kind == .week { layoutWeek(today: today) } else { layoutMonth(today: today) }
        for (index, plant) in plants.enumerated() {
            addToolTip(plant.rect, owner: self, userData: UnsafeMutableRawPointer(bitPattern: index + 1))
        }
        needsDisplay = true
    }

    private func sessions(on dayStart: Date) -> [StudySession] {
        guard let next = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return log.sessions.filter { $0.start >= dayStart && $0.start < next }
    }

    private func formatted(_ date: Date, _ format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.timeZone = calendar.timeZone
        f.dateFormat = format
        return f.string(from: date)
    }

    /// L'aspetto delle piantine: la tela di Pianty (208x341) con i piedi a 1,76% dal fondo.
    private static let canvasAspect: CGFloat = 208.0 / 341.0
    private static let feetFraction: CGFloat = 0.0176

    private func image(for session: StudySession, stage: Int) -> NSImage? {
        let pet = session.pet ?? "pianty"
        let key = "\(pet)-\(stage)"
        if let cached = imageCache[key] { return cached }
        let candidates = ["garden_\(pet)_\(stage)", "pianty_stage\(stage)_1"]
        for name in candidates {
            if let url = Bundle.main.url(forResource: name, withExtension: "png"), let image = NSImage(contentsOf: url) {
                imageCache[key] = image
                return image
            }
        }
        return nil
    }

    private func plantRect(centerX: CGFloat, feetY: CGFloat, height: CGFloat) -> NSRect {
        let width = height * Self.canvasAspect
        return NSRect(x: centerX - width / 2, y: feetY - height * (1 - Self.feetFraction), width: width, height: height)
    }

    /// La settimana: sette aiuole in fila, fino a sei piantine ciascuna (tre davanti e tre dietro).
    private func layoutWeek(today: Date) {
        let m = Self.margin
        let columnWidth = (Self.size.width - 2 * m) / 7
        let baseY: CGFloat = 392
        let plantHeight: CGFloat = 112
        for i in 0..<7 {
            guard let dayStart = calendar.date(byAdding: .day, value: i, to: period.start) else { continue }
            let x0 = m + CGFloat(i) * columnWidth
            let bedRect = NSRect(x: x0 + 5, y: baseY - 10, width: columnWidth - 10, height: 58)
            let items = sessions(on: dayStart)
            let seconds = items.reduce(0) { $0 + $1.seconds }
            // Le più piccole davanti e le più alte dietro, così si vedono tutte.
            let shown = items.prefix(6).sorted {
                let a = GardenRules.stage(seconds: $0.seconds), b = GardenRules.stage(seconds: $1.seconds)
                return a != b ? a < b : $0.start < $1.start
            }
            let front = Array(shown.prefix(3))
            let back = Array(shown.dropFirst(3))
            let spacing = columnWidth / 3.35

            for (row, group) in [(1, back), (0, front)] {
                for (k, session) in group.enumerated() {
                    let cx = x0 + columnWidth / 2 + (CGFloat(k) - CGFloat(group.count - 1) / 2) * spacing
                    let feetY = baseY + 16 - (row == 1 ? 46 : 0)
                    plants.append(Plant(
                        rect: plantRect(centerX: cx, feetY: feetY, height: plantHeight * (row == 1 ? 0.9 : 1)),
                        stage: GardenRules.stage(seconds: session.seconds), session: session, showsDot: row == 0
                    ))
                }
            }
            beds.append(Bed(
                rect: bedRect,
                dayLabel: formatted(dayStart, "EEE d").lowercased(),
                dayLabelPoint: NSPoint(x: x0 + columnWidth / 2, y: baseY + 66),
                total: items.isEmpty ? nil : StudyStats.duration(seconds: seconds)
                    + (items.count > 6 ? " · +\(items.count - 6)" : ""),
                extra: max(items.count - 6, 0),
                isToday: calendar.isDate(dayStart, inSameDayAs: today),
                anchor: NSPoint(x: x0 + columnWidth / 2, y: baseY - 60)
            ))
        }
    }

    /// Il mese: un calendario con piantine piccole in ogni giorno (fino a quattro, poi "+N").
    private func layoutMonth(today: Date) {
        let m = Self.margin
        let cellWidth = (Self.size.width - 2 * m) / 7
        let cellHeight: CGFloat = 78
        let top: CGFloat = 150
        guard let days = calendar.range(of: .day, in: .month, for: period.start) else { return }
        // Colonna del primo giorno (la settimana parte dal lunedì).
        let weekday = calendar.component(.weekday, from: period.start)           // 1 = domenica
        let offset = (weekday + 5) % 7                                           // 0 = lunedì
        for (n, day) in days.enumerated() {
            guard let dayStart = calendar.date(byAdding: .day, value: n, to: period.start) else { continue }
            let slot = offset + n
            let col = slot % 7, row = slot / 7
            let cell = NSRect(x: m + CGFloat(col) * cellWidth, y: top + CGFloat(row) * cellHeight, width: cellWidth, height: cellHeight)
            let items = sessions(on: dayStart)
            let shown = Array(items.prefix(4))
            let spacing: CGFloat = 25
            for (k, session) in shown.enumerated() {
                let cx = cell.midX + (CGFloat(k) - CGFloat(shown.count - 1) / 2) * spacing
                plants.append(Plant(
                    rect: plantRect(centerX: cx, feetY: cell.maxY - 8, height: 54),
                    stage: GardenRules.stage(seconds: session.seconds), session: session, showsDot: false
                ))
            }
            beds.append(Bed(
                rect: cell.insetBy(dx: 3, dy: 3), dayLabel: "\(day)", dayLabelPoint: NSPoint(x: cell.minX + 10, y: cell.minY + 6),
                total: nil, extra: max(items.count - 4, 0), isToday: calendar.isDate(dayStart, inSameDayAs: today),
                anchor: NSPoint(x: cell.midX, y: cell.midY)
            ))
        }
    }

    // MARK: - Testi

    private var periodTitle: String {
        switch kind {
        case .week:
            let last = period.end.addingTimeInterval(-1)
            return "\(formatted(period.start, "d MMM")) – \(formatted(last, "d MMM yyyy"))"
        default:
            let title = formatted(period.start, "MMMM yyyy")
            return title.prefix(1).uppercased() + title.dropFirst()
        }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        let index = Int(bitPattern: data) - 1
        guard plants.indices.contains(index) else { return "" }
        let s = plants[index].session
        let minutes = (s.seconds + 30) / 60
        var parts = [formatted(s.start, "EEE d MMM, HH:mm"), s.subject ?? Subject.none, "\(minutes) min"]
        if !s.completed { parts.append("interrotto") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Disegno

    private func text(_ string: String, at rect: NSRect, font: NSFont, color: NSColor = Paper.ink, alignment: NSTextAlignment = .left) {
        let para = NSMutableParagraphStyle()
        para.alignment = alignment
        para.lineBreakMode = .byTruncatingTail
        (string as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
    }

    override func draw(_ dirtyRect: NSRect) {
        Paper.paper.setFill()
        bounds.fill()
        let width = Self.size.width
        let m = Self.margin

        text(periodTitle, at: NSRect(x: m + 40, y: 60, width: width - 2 * m - 80, height: 26),
             font: Paper.markerFont(22), alignment: .center)

        // Riga di riepilogo e giorni di fila
        let plantsWord = totalPlants == 1 ? "1 piantina" : "\(totalPlants) piantine"
        let when = kind == .week ? "in questa settimana" : "in questo mese"
        let summary = totalPlants == 0
            ? "Il giardino è ancora vuoto: ogni focus che finisci pianta una piantina."
            : "\(plantsWord) \(when) · \(StudyStats.duration(seconds: totalSeconds)) di studio. Più hai studiato, più sono cresciute."
        text(summary, at: NSRect(x: m, y: 100, width: width - 2 * m - 200, height: 20),
             font: NSFont.systemFont(ofSize: 14), color: Paper.inkLight)
        let badge = NSRect(x: width - m - 180, y: 12, width: 180, height: 44)
        let badgeShape = NSBezierPath(roundedRect: badge, xRadius: 12, yRadius: 12)
        Paper.accent.withAlphaComponent(0.12).setFill()
        badgeShape.fill()
        text("\(streak)", at: NSRect(x: badge.minX + 14, y: badge.minY + 4, width: 40, height: 34), font: Paper.markerFont(30))
        text(streak == 1 ? "giorno di fila" : "giorni di fila", at: NSRect(x: badge.minX + 54, y: badge.minY + 14, width: 120, height: 18),
             font: NSFont.systemFont(ofSize: 14), color: Paper.inkLight)

        // Aiuole
        for bed in beds {
            if kind == .week {
                let outline = NSBezierPath(roundedRect: bed.rect, xRadius: 14, yRadius: 14)
                NSColor(calibratedRed: 0.93, green: 0.84, blue: 0.69, alpha: 1).setFill()
                outline.fill()
                (bed.isToday ? Paper.accent : Paper.paperEdge).setStroke()
                outline.lineWidth = bed.isToday ? 2 : 1
                outline.stroke()
                let soil = NSRect(x: bed.rect.minX, y: bed.rect.minY + 26, width: bed.rect.width, height: 32)
                NSColor(calibratedRed: 0.59, green: 0.44, blue: 0.31, alpha: 1).setFill()
                NSBezierPath(roundedRect: soil, xRadius: 14, yRadius: 14).fill()
                text(bed.dayLabel, at: NSRect(x: bed.dayLabelPoint.x - 60, y: bed.dayLabelPoint.y, width: 120, height: 26),
                     font: Paper.markerFont(20), alignment: .center)
                if let total = bed.total {
                    text(total, at: NSRect(x: bed.dayLabelPoint.x - 60, y: bed.dayLabelPoint.y + 28, width: 120, height: 18),
                         font: NSFont.systemFont(ofSize: 13), color: Paper.inkLight, alignment: .center)
                }
            } else {
                let outline = NSBezierPath(roundedRect: bed.rect, xRadius: 10, yRadius: 10)
                NSColor(calibratedRed: 0.93, green: 0.84, blue: 0.69, alpha: bed.isToday ? 0.9 : 0.5).setFill()
                outline.fill()
                if bed.isToday {
                    Paper.accent.setStroke()
                    outline.lineWidth = 2
                    outline.stroke()
                }
                text(bed.dayLabel, at: NSRect(x: bed.dayLabelPoint.x, y: bed.dayLabelPoint.y, width: 30, height: 14),
                     font: NSFont.systemFont(ofSize: 11, weight: .semibold), color: Paper.inkLight)
            }
        }
        // Piantine: le dietro prima (sono all'inizio della lista della riga dietro), poi quelle davanti
        for plant in plants {
            image(for: plant.session, stage: plant.stage)?
                .draw(in: plant.rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            if plant.showsDot {
                let color = plant.session.subject.map { Paper.color(forSubject: $0) } ?? Paper.inkLight.withAlphaComponent(0.55)
                let dot = NSBezierPath(ovalIn: NSRect(x: plant.rect.midX - 6, y: plant.rect.maxY + 3, width: 12, height: 12))
                color.setFill()
                dot.fill()
                // Bordo bianco per staccarsi dalla terra; arancione se il focus è stato interrotto.
                (plant.session.completed ? NSColor.white.withAlphaComponent(0.9) : Paper.accent).setStroke()
                dot.lineWidth = plant.session.completed ? 1 : 2.5
                dot.stroke()
            }
        }
        if kind == .month {
            for bed in beds where bed.extra > 0 {
                text("+\(bed.extra)", at: NSRect(x: bed.rect.maxX - 34, y: bed.rect.minY + 4, width: 28, height: 14),
                     font: NSFont.systemFont(ofSize: 11, weight: .bold), color: Paper.accent, alignment: .right)
            }
        }
        if kind == .week, totalPlants > 0 {
            text("Il pallino sotto il vaso è la materia; con il bordo arancione il focus è stato interrotto. Passa il mouse su una piantina per i dettagli.",
                 at: NSRect(x: m, y: Self.size.height - 40, width: width - 2 * m, height: 18),
                 font: NSFont.systemFont(ofSize: 12), color: Paper.inkLight)
        }
        if totalPlants == 0 {
            let y: CGFloat = kind == .week ? 260 : 320
            text("Ancora nessuna piantina in questo periodo.", at: NSRect(x: m, y: y, width: width - 2 * m, height: 24),
                 font: Paper.markerFont(20), color: Paper.inkLight, alignment: .center)
        }
    }
}

/// Tiene la finestra del giardino.
final class GardenController {
    private var window: NSWindow?
    private var view: GardenView?

    func show() {
        if window == nil {
            let view = GardenView(log: .shared)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: GardenView.size),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Il mio giardino · FocusFriends"
            window.contentView = view
            window.isReleasedWhenClosed = false
            window.backgroundColor = Paper.paper
            window.appearance = NSAppearance(named: .aqua)
            window.center()
            self.window = window
            self.view = view
        }
        view?.select(.week)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
