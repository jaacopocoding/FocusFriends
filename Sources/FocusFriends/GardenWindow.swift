import AppKit

/// Il giardino: si conta il tempo di studio di ogni giorno. Ogni 50 minuti è una pianta adulta, e il resto cresce in
/// una piantina allo stadio di mezzo (GardenRules). Una aiuola per giorno; la scheda "Settimana" le mostra grandi,
/// "Mese" in un calendario. Si ricava tutto dal registro delle sessioni.
final class GardenView: NSView, NSViewToolTipOwner {
    static let size = NSSize(width: 1000, height: 540)
    private static let margin: CGFloat = 28

    override var isFlipped: Bool { true }

    private let log: SessionLog
    private let now: () -> Date
    private let calendar = StudyPeriod.calendar()

    private var kind: PeriodKind = .week
    private var period: StudyPeriod

    /// Una piantina disegnata: dove, e quale (stadio, materie, personaggio) di quale giorno.
    private struct Plant {
        var rect: NSRect
        var info: GardenRules.DayPlant
        var day: Date
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
        /// Il giorno ha almeno una piantina (nel mese: serve un po' di terra sotto).
        var hasPlants = false
    }
    private var plants: [Plant] = []
    private var beds: [Bed] = []
    /// Le piantine adulte del periodo e quelle ancora in crescita (una al massimo per giorno).
    private var adultPlants = 0
    private var growingPlants = 0
    private var totalSeconds = 0
    private var streak = 0
    /// Le immagini già caricate: "pianty-3", "porcellino-5"... Ogni personaggio può avere la sua collezione
    /// (`garden_<personaggio>_<stadio>.png`); chi non ce l'ha usa le piantine di Pianty.
    private var imageCache: [String: NSImage] = [:]
    /// Le sessioni del periodo e le piantine di ogni giorno (chiave: inizio del giorno), calcolate una volta per ricarica.
    private var dayItems: [Date: [StudySession]] = [:]
    private var dayPlants: [Date: [GardenRules.DayPlant]] = [:]

    private let segmented = NSSegmentedControl(labels: ["Settimana", "Mese"], trackingMode: .selectOne, target: nil, action: nil)
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    /// Chiamata dal pulsante «‹ Menu» in alto a sinistra: la finestra si chiude e si torna alla scheda del menu.
    var onBack: (() -> Void)?

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
        segmented.frame = NSRect(x: (Self.size.width - 190) / 2, y: 18, width: 190, height: 26)
        addSubview(segmented)

        let back = BackToMenuButton(target: self, action: #selector(backPressed))
        back.setFrameOrigin(NSPoint(x: 16, y: 14))
        addSubview(back)

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

        // Chiusa la finestra non serve ricalcolare: alla riapertura `select` lo fa. (Minimizzata sì: è ancora lì.)
        log.addObserver { [weak self] in
            guard let self, self.window.map({ $0.isVisible || $0.isMiniaturized }) ?? true else { return }
            self.reload()
        }
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

    @objc private func backPressed() { onBack?() }

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

        let inPeriod = log.sessions.filter { period.contains($0.startTime(in: calendar)) }
        totalSeconds = inPeriod.reduce(0) { $0 + $1.seconds }
        adultPlants = 0
        growingPlants = 0
        dayItems = [:]
        for session in inPeriod {
            dayItems[calendar.startOfDay(for: session.startTime(in: calendar)), default: []].append(session)
        }
        dayPlants = [:]
        var cursor = period.start
        while cursor < period.end {
            let day = GardenRules.plants(of: sessions(on: cursor), calendar: calendar)
            dayPlants[calendar.startOfDay(for: cursor)] = day
            adultPlants += day.filter { $0.isAdult }.count
            growingPlants += day.filter { !$0.isAdult }.count
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? period.end
        }

        plants = []
        beds = []
        removeAllToolTips()
        if kind == .week { layoutWeek(today: today) } else { layoutMonth(today: today) }
        for (index, plant) in plants.enumerated() {
            addToolTip(plant.rect, owner: self, userData: UnsafeMutableRawPointer(bitPattern: index + 1))
        }
        needsDisplay = true
    }

    /// Le sessioni di un giorno del periodo (già raggruppate da `reload`).
    private func sessions(on dayStart: Date) -> [StudySession] {
        dayItems[calendar.startOfDay(for: dayStart)] ?? []
    }

    /// Le piantine di un giorno del periodo (già calcolate da `reload`).
    private func plants(on dayStart: Date) -> [GardenRules.DayPlant] {
        dayPlants[calendar.startOfDay(for: dayStart)] ?? []
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

    private func image(forPet petID: String?, stage: Int) -> NSImage? {
        let pet = petID ?? "pianty"
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

    /// Le piantine di un giorno da mostrare: quella in crescita davanti, poi le adulte, fino a `limit`.
    private func visiblePlants(_ plants: [GardenRules.DayPlant], limit: Int) -> [GardenRules.DayPlant] {
        let growing = plants.filter { !$0.isAdult }
        let adults = plants.filter { $0.isAdult }
        return Array((growing + adults).prefix(limit))
    }

    /// La settimana: sette aiuole in fila, fino a sei piantine ciascuna (tre davanti e tre dietro).
    private func layoutWeek(today: Date) {
        let m = Self.margin
        let columnWidth = (Self.size.width - 2 * m) / 7
        let baseY: CGFloat = 392
        let plantHeight: CGFloat = 124
        for i in 0..<7 {
            guard let dayStart = calendar.date(byAdding: .day, value: i, to: period.start) else { continue }
            let x0 = m + CGFloat(i) * columnWidth
            let bedRect = NSRect(x: x0 + 8, y: baseY - 14, width: columnWidth - 16, height: 38)   // il monticello di terra
            let items = sessions(on: dayStart)
            let seconds = items.reduce(0) { $0 + $1.seconds }
            let all = plants(on: dayStart)
            // Quella che cresce davanti (più piccola) e le adulte dietro, così si vedono tutte.
            let shown = visiblePlants(all, limit: 6)
            let front = Array(shown.prefix(3))
            let back = Array(shown.dropFirst(3))
            let spacing = columnWidth / 3.35
            let extra = max(all.count - shown.count, 0)

            for (row, group) in [(1, back), (0, front)] {
                for (k, plant) in group.enumerated() {
                    let cx = x0 + columnWidth / 2 + (CGFloat(k) - CGFloat(group.count - 1) / 2) * spacing
                    let feetY = baseY + 6 - (row == 1 ? 36 : 0)
                    plants.append(Plant(
                        rect: plantRect(centerX: cx, feetY: feetY, height: plantHeight * (row == 1 ? 0.9 : 1)),
                        info: plant, day: dayStart, showsDot: row == 0
                    ))
                }
            }
            beds.append(Bed(
                rect: bedRect,
                dayLabel: formatted(dayStart, "EEE d").lowercased(),
                dayLabelPoint: NSPoint(x: x0 + columnWidth / 2, y: baseY + 30),
                total: items.isEmpty ? nil : StudyStats.duration(seconds: seconds) + (extra > 0 ? " · +\(extra)" : ""),
                extra: extra,
                isToday: calendar.isDate(dayStart, inSameDayAs: today),
                anchor: NSPoint(x: x0 + columnWidth / 2, y: baseY - 60),
                hasPlants: !all.isEmpty
            ))
        }
    }

    /// Il mese: un calendario con piantine piccole in ogni giorno (fino a quattro, poi "+N").
    private func layoutMonth(today: Date) {
        let m = Self.margin
        let cellWidth = (Self.size.width - 2 * m) / 7
        let top: CGFloat = 140
        guard let days = calendar.range(of: .day, in: .month, for: period.start) else { return }
        // Colonna del primo giorno (la settimana parte dal lunedì).
        let weekday = calendar.component(.weekday, from: period.start)           // 1 = domenica
        let offset = (weekday + 5) % 7                                           // 0 = lunedì
        // Cinque o sei righe: le celle si adattano, così il mese sta sempre nella finestra.
        let rows = (offset + days.count + 6) / 7
        let cellHeight = min(78, (Self.size.height - top - 58) / CGFloat(rows))     // 58: lo spazio per la legenda in fondo
        let plantHeight = min(54, cellHeight - 20)
        for (n, day) in days.enumerated() {
            guard let dayStart = calendar.date(byAdding: .day, value: n, to: period.start) else { continue }
            let slot = offset + n
            let col = slot % 7, row = slot / 7
            let cell = NSRect(x: m + CGFloat(col) * cellWidth, y: top + CGFloat(row) * cellHeight, width: cellWidth, height: cellHeight)
            let all = plants(on: dayStart)
            let shown = visiblePlants(all, limit: 4)
            let spacing: CGFloat = 25
            for (k, plant) in shown.enumerated() {
                let cx = cell.midX + (CGFloat(k) - CGFloat(shown.count - 1) / 2) * spacing
                plants.append(Plant(
                    rect: plantRect(centerX: cx, feetY: cell.maxY - 7, height: plantHeight),
                    info: plant, day: dayStart, showsDot: false
                ))
            }
            beds.append(Bed(
                rect: cell.insetBy(dx: 3, dy: 3), dayLabel: "\(day)", dayLabelPoint: NSPoint(x: cell.minX + 10, y: cell.minY + 6),
                total: nil, extra: max(all.count - shown.count, 0), isToday: calendar.isDate(dayStart, inSameDayAs: today),
                anchor: NSPoint(x: cell.midX, y: cell.midY), hasPlants: !all.isEmpty
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
        let plant = plants[index]
        let minutes = (plant.info.seconds + 30) / 60
        var head = formatted(plant.day, "EEEE d MMMM")
        head = head.prefix(1).uppercased() + head.dropFirst()
        let state = plant.info.isAdult ? "pianta adulta · \(GardenRules.minutesPerPlant) min"
            : "in crescita · \(minutes) min su \(GardenRules.minutesPerPlant)"
        let subjects = plant.info.subjects.map {
            "\($0.subject ?? Subject.none) \(StudyStats.duration(seconds: $0.seconds))"
        }.joined(separator: ", ")
        return head + " · " + state + (subjects.isEmpty ? "" : "\n" + subjects)
    }

    // MARK: - La scena

    /// Un generatore deterministico: l'erba e i fiori sono sempre negli stessi punti.
    private struct SeededRandom {
        var state: UInt64
        mutating func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((state >> 33) & 0xFFFF) / 65535
        }
        mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * next() }
    }

    private static var sceneCache: [String: NSImage] = [:]

    /// Il prato della stagione: cielo, sole e nuvole, colline, una staccionata e l'erba. Nel mese la scena è più
    /// bassa (il resto è il calendario sul prato). Si disegna una volta per tipo e stagione.
    static func scene(for kind: PeriodKind, season: Season) -> NSImage {
        let key = "\(kind.rawValue)-\(season.rawValue)"
        if let cached = sceneCache[key] { return cached }
        let image = NSImage(size: size, flipped: true) { rect in
            drawScene(kind: kind, season: season, in: rect)
            return true
        }
        sceneCache[key] = image
        return image
    }

    private typealias RGB = (CGFloat, CGFloat, CGFloat)

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    private static func lerp(_ a: RGB, _ b: RGB, _ t: CGFloat) -> NSColor {
        rgb(a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
    }

    /// I colori e gli elementi di ogni stagione.
    private struct SeasonStyle {
        var skyTop: RGB, skyBottom: RGB
        var sun: RGB, sunRadius: CGFloat, sunGlow: CGFloat
        var cloud: RGB, cloudCount: Int
        var farHill: RGB, nearHill: RGB
        var lawnTop: RGB, lawnBottom: RGB
        var blade: RGB
        var flowers: [RGB], flowerCount: Int, flowerRadius: CGFloat
        var leaves: Int
        var snow: Bool
    }

    private static func style(for season: Season) -> SeasonStyle {
        switch season {
        case .spring:
            return SeasonStyle(skyTop: (252, 244, 220), skyBottom: (200, 232, 228), sun: (255, 220, 130), sunRadius: 32, sunGlow: 1,
                               cloud: (255, 255, 255), cloudCount: 3, farHill: (186, 214, 158), nearHill: (150, 196, 120),
                               lawnTop: (140, 192, 104), lawnBottom: (104, 162, 82), blade: (90, 142, 68),
                               flowers: [(255, 255, 255), (250, 190, 205), (255, 224, 130), (206, 190, 240)], flowerCount: 48,
                               flowerRadius: 3.4, leaves: 0, snow: false)
        case .summer:
            return SeasonStyle(skyTop: (255, 238, 196), skyBottom: (170, 214, 240), sun: (255, 206, 90), sunRadius: 36, sunGlow: 1.15,
                               cloud: (255, 255, 255), cloudCount: 2, farHill: (176, 210, 124), nearHill: (136, 188, 88),
                               lawnTop: (122, 182, 74), lawnBottom: (90, 150, 58), blade: (68, 128, 50),
                               flowers: [(255, 214, 80), (255, 168, 70), (240, 110, 100), (255, 255, 255)], flowerCount: 34,
                               flowerRadius: 4.6, leaves: 0, snow: false)
        case .autumn:
            return SeasonStyle(skyTop: (255, 228, 198), skyBottom: (216, 214, 208), sun: (255, 188, 120), sunRadius: 30, sunGlow: 0.8,
                               cloud: (240, 230, 228), cloudCount: 4, farHill: (218, 198, 132), nearHill: (190, 162, 98),
                               lawnTop: (178, 170, 92), lawnBottom: (144, 138, 70), blade: (150, 130, 60),
                               flowers: [(230, 130, 70), (210, 90, 60)], flowerCount: 8, flowerRadius: 3.2, leaves: 90, snow: false)
        case .winter:
            return SeasonStyle(skyTop: (238, 240, 246), skyBottom: (206, 220, 232), sun: (255, 255, 255), sunRadius: 26, sunGlow: 0.5,
                               cloud: (252, 252, 255), cloudCount: 4, farHill: (226, 234, 244), nearHill: (206, 218, 232),
                               lawnTop: (234, 240, 238), lawnBottom: (204, 218, 214), blade: (150, 176, 168),
                               flowers: [], flowerCount: 0, flowerRadius: 3, leaves: 0, snow: true)
        }
    }

    private static func drawScene(kind: PeriodKind, season: Season, in rect: NSRect) {
        let w = rect.width, h = rect.height
        let isWeek = kind != .month
        let st = style(for: season)
        // Dove finisce il cielo e comincia il prato.
        let lawnTop: CGFloat = isWeek ? 300 : 140
        let ink = rgb(64, 40, 22)
        var rng = SeededRandom(state: 20261012 &+ UInt64(season.hashValueStable))

        // Il cielo
        let skyHeight = lawnTop + 20
        var y: CGFloat = 0
        while y < skyHeight {
            lerp(st.skyTop, st.skyBottom, y / skyHeight).setFill()
            NSRect(x: 0, y: y, width: w, height: 4).fill()
            y += 4
        }

        // Il sole (con un alone) e le nuvole
        let sun = NSPoint(x: isWeek ? 735 : 690, y: isWeek ? 74 : 40)
        for (r, a) in [(62, 0.10), (50, 0.16), (40, 0.28)] as [(CGFloat, CGFloat)] {
            let grown = r * st.sunGlow * (st.sunRadius / 32)
            rgb(st.sun.0, st.sun.1, st.sun.2, a * min(st.sunGlow, 1.4)).setFill()
            NSBezierPath(ovalIn: NSRect(x: sun.x - grown, y: sun.y - grown, width: 2 * grown, height: 2 * grown)).fill()
        }
        rgb(st.sun.0, st.sun.1, st.sun.2, season == .winter ? 0.7 : 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: sun.x - st.sunRadius, y: sun.y - st.sunRadius, width: 2 * st.sunRadius, height: 2 * st.sunRadius)).fill()
        let allClouds: [(CGFloat, CGFloat, CGFloat)] = isWeek
            ? [(120, 150, 1.0), (520, 168, 0.8), (905, 140, 0.9), (330, 110, 0.7)]
            : [(110, 110, 0.7), (560, 118, 0.6), (340, 92, 0.55), (900, 120, 0.6)]
        for (cx, cy, scale) in allClouds.prefix(st.cloudCount) {
            rgb(st.cloud.0, st.cloud.1, st.cloud.2, 0.88).setFill()
            for (dx, dy, r) in [(0, 0, 24), (26, 5, 20), (-26, 5, 18), (48, 11, 14), (-48, 11, 13)] as [(CGFloat, CGFloat, CGFloat)] {
                NSBezierPath(ovalIn: NSRect(x: cx + dx * scale - r * scale * 1.3, y: cy + dy * scale - r * scale * 0.8,
                                            width: 2.6 * r * scale, height: 1.6 * r * scale)).fill()
            }
        }

        // Le colline
        func hill(base: CGFloat, amp: CGFloat, phase: CGFloat, color: NSColor) {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 0, y: h))
            var x: CGFloat = 0
            while x <= w + 8 {
                path.line(to: NSPoint(x: x, y: base + amp * sin(x / 140 + phase)))
                x += 8
            }
            path.line(to: NSPoint(x: w, y: h))
            path.close()
            color.setFill()
            path.fill()
        }
        hill(base: lawnTop - 130 + (isWeek ? 0 : 60), amp: isWeek ? 22 : 12, phase: 0, color: rgb(st.farHill.0, st.farHill.1, st.farHill.2))
        hill(base: lawnTop - 94 + (isWeek ? 0 : 42), amp: isWeek ? 16 : 9, phase: 1.7, color: rgb(st.nearHill.0, st.nearHill.1, st.nearHill.2))

        // La staccionata (nel mese è bassa: sopra c'è il riepilogo, sotto il calendario)
        let fenceHeight: CGFloat = isWeek ? 64 : 18
        let fenceTop = lawnTop - fenceHeight - 2
        let fenceBottom = lawnTop - 2
        let railThickness: CGFloat = isWeek ? 8 : 4
        let picketWidth: CGFloat = isWeek ? 18 : 12
        let picketStep: CGFloat = isWeek ? 30 : 20
        rgb(250, 238, 210).setFill()
        ink.setStroke()
        for rail in [fenceTop + fenceHeight * 0.34, fenceTop + fenceHeight * 0.70] {
            let r = NSRect(x: -2, y: rail, width: w + 4, height: railThickness)
            r.fill()
            NSBezierPath(rect: r).stroke()
        }
        var x: CGFloat = 14
        while x < w {
            let picket = NSBezierPath()
            picket.move(to: NSPoint(x: x, y: fenceTop + fenceHeight * 0.2))
            picket.line(to: NSPoint(x: x + picketWidth / 2, y: fenceTop))
            picket.line(to: NSPoint(x: x + picketWidth, y: fenceTop + fenceHeight * 0.2))
            picket.line(to: NSPoint(x: x + picketWidth, y: fenceBottom))
            picket.line(to: NSPoint(x: x, y: fenceBottom))
            picket.close()
            rgb(252, 243, 220).setFill()
            picket.fill()
            picket.lineWidth = 1
            picket.stroke()
            if st.snow {
                // Un cappuccio di neve su ogni paletto
                let cap = NSBezierPath(roundedRect: NSRect(x: x - 1, y: fenceTop - 3, width: picketWidth + 2, height: isWeek ? 9 : 5),
                                       xRadius: 3, yRadius: 3)
                rgb(255, 255, 255).setFill()
                cap.fill()
                rgb(150, 170, 190).setStroke()
                cap.lineWidth = 1
                cap.stroke()
            }
            x += picketStep
        }

        // Il prato
        var ly = lawnTop
        while ly < h {
            lerp(st.lawnTop, st.lawnBottom, (ly - lawnTop) / (h - lawnTop)).setFill()
            NSRect(x: 0, y: ly, width: w, height: 4).fill()
            ly += 4
        }
        rgb(st.blade.0, st.blade.1, st.blade.2).setStroke()
        for _ in 0..<(season == .winter ? 120 : 220) {
            let gx = rng.range(0, w), gy = rng.range(lawnTop + 10, h - 4)
            let blade = NSBezierPath()
            blade.move(to: NSPoint(x: gx, y: gy))
            blade.line(to: NSPoint(x: gx + rng.range(-3, 3), y: gy - rng.range(5, 10)))
            blade.lineWidth = 2
            blade.stroke()
        }
        if st.snow {
            // Chiazze di neve sul prato
            rgb(255, 255, 255, 0.85).setFill()
            for _ in 0..<26 {
                let sx = rng.range(0, w), sy = rng.range(lawnTop + 14, h - 10)
                NSBezierPath(ovalIn: NSRect(x: sx - rng.range(14, 30), y: sy - 4, width: rng.range(28, 60), height: rng.range(8, 14))).fill()
            }
        }

        // Fiori
        let flowerCount = isWeek ? st.flowerCount : st.flowerCount / 2
        for i in 0..<flowerCount {
            let fx = rng.range(10, w - 10), fy = rng.range(lawnTop + 16, h - 10)
            let c = st.flowers[i % st.flowers.count]
            let r = st.flowerRadius
            if season == .summer {
                // Girasoli: petali gialli e cuore scuro
                rgb(c.0, c.1, c.2).setFill()
                NSBezierPath(ovalIn: NSRect(x: fx - r, y: fy - r, width: 2 * r, height: 2 * r)).fill()
                rgb(110, 70, 36).setFill()
                NSBezierPath(ovalIn: NSRect(x: fx - r * 0.45, y: fy - r * 0.45, width: r * 0.9, height: r * 0.9)).fill()
            } else {
                rgb(c.0, c.1, c.2).setFill()
                let dot = NSBezierPath(ovalIn: NSRect(x: fx - r, y: fy - r, width: 2 * r, height: 2 * r))
                dot.fill()
                ink.setStroke()
                dot.lineWidth = 1
                dot.stroke()
            }
        }

        // Foglie d'autunno: sul prato e in aria
        if st.leaves > 0 {
            let colors: [RGB] = [(205, 96, 44), (224, 156, 52), (170, 62, 40), (196, 120, 40)]
            for i in 0..<st.leaves {
                let inAir = i % 5 == 0
                let lx = rng.range(8, w - 8)
                let ly = inAir ? rng.range(60, lawnTop + 10) : rng.range(lawnTop + 14, h - 10)
                let c = colors[i % colors.count]
                NSGraphicsContext.saveGraphicsState()
                let t = NSAffineTransform()
                t.translateX(by: lx, yBy: ly)
                t.rotate(byDegrees: rng.range(-60, 60))
                t.concat()
                rgb(c.0, c.1, c.2, inAir ? 0.85 : 0.95).setFill()
                NSBezierPath(ovalIn: NSRect(x: -7, y: -3.5, width: 14, height: 7)).fill()
                rgb(c.0 * 0.6, c.1 * 0.6, c.2 * 0.6).setStroke()
                let vein = NSBezierPath()
                vein.move(to: NSPoint(x: -7, y: 0))
                vein.line(to: NSPoint(x: 7, y: 0))
                vein.lineWidth = 0.8
                vein.stroke()
                NSGraphicsContext.restoreGraphicsState()
            }
        }

        // Fiocchi di neve
        if st.snow {
            rgb(255, 255, 255, 0.95).setFill()
            for _ in 0..<(isWeek ? 90 : 60) {
                let fx = rng.range(0, w), fy = rng.range(0, h)
                let r = rng.range(1.4, 3.2)
                NSBezierPath(ovalIn: NSRect(x: fx - r, y: fy - r, width: 2 * r, height: 2 * r)).fill()
            }
        }
    }

    // MARK: - Disegno

    private func text(_ string: String, at rect: NSRect, font: NSFont, color: NSColor = Paper.ink, alignment: NSTextAlignment = .left) {
        let para = NSMutableParagraphStyle()
        para.alignment = alignment
        para.lineBreakMode = .byTruncatingTail
        (string as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
    }

    override func draw(_ dirtyRect: NSRect) {
        let anchorDate = calendar.date(byAdding: .day, value: kind == .week ? 3 : 14, to: period.start) ?? period.start
        Self.scene(for: kind, season: Season.of(anchorDate, calendar: calendar)).draw(in: bounds)
        let width = Self.size.width
        let m = Self.margin

        text(periodTitle, at: NSRect(x: m + 40, y: 60, width: width - 2 * m - 80, height: 26),
             font: Paper.markerFont(22), alignment: .center)

        // Riga di riepilogo e giorni di fila
        let totalPlants = adultPlants + growingPlants
        let adultWord = adultPlants == 1 ? "1 pianta adulta" : "\(adultPlants) piante adulte"
        let growingText = growingPlants == 0 ? "" : (growingPlants == 1 ? " e 1 in crescita" : " e \(growingPlants) in crescita")
        let when = kind == .week ? "questa settimana" : "questo mese"
        let summary = totalPlants == 0
            ? "Il giardino è ancora vuoto: ogni 50 minuti di studio in un giorno è una pianta adulta."
            : "\(StudyStats.duration(seconds: totalSeconds)) di studio \(when): \(adultWord)\(growingText)."
        text(summary, at: NSRect(x: m, y: 100, width: width - 2 * m - 200, height: 20),
             font: NSFont.systemFont(ofSize: 14), color: Paper.inkLight)
        let badge = NSRect(x: width - m - 180, y: 12, width: 180, height: 44)
        let badgeShape = NSBezierPath(roundedRect: badge, xRadius: 12, yRadius: 12)
        Paper.accent.withAlphaComponent(0.12).setFill()
        badgeShape.fill()
        text("\(streak)", at: NSRect(x: badge.minX + 14, y: badge.minY + 4, width: 40, height: 34), font: Paper.markerFont(30))
        text(streak == 1 ? "giorno di fila" : "giorni di fila", at: NSRect(x: badge.minX + 54, y: badge.minY + 14, width: 120, height: 18),
             font: NSFont.systemFont(ofSize: 14), color: Paper.inkLight)

        // Monticelli di terra (settimana) o caselle del calendario sul prato (mese)
        let soilFill = NSColor(calibratedRed: 0.61, green: 0.45, blue: 0.31, alpha: 1)
        let outlineInk = NSColor(calibratedRed: 0.25, green: 0.16, blue: 0.09, alpha: 1)
        for bed in beds {
            if kind == .week {
                let mound = NSBezierPath(ovalIn: bed.rect)
                soilFill.setFill()
                mound.fill()
                (bed.isToday ? Paper.accent : outlineInk).setStroke()
                mound.lineWidth = bed.isToday ? 3 : 2
                mound.stroke()
                // Il cartello di legno con il giorno e le ore, su un paletto.
                let cx = bed.dayLabelPoint.x
                let sign = NSRect(x: cx - 46, y: bed.dayLabelPoint.y, width: 92, height: 44)
                outlineInk.setStroke()
                let stake = NSBezierPath()
                stake.move(to: NSPoint(x: cx, y: bed.rect.maxY - 6))
                stake.line(to: NSPoint(x: cx, y: sign.minY + 2))
                stake.lineWidth = 3
                stake.stroke()
                let tag = NSBezierPath(roundedRect: sign, xRadius: 8, yRadius: 8)
                NSColor(calibratedRed: 0.96, green: 0.89, blue: 0.71, alpha: 1).setFill()
                tag.fill()
                (bed.isToday ? Paper.accent : outlineInk).setStroke()
                tag.lineWidth = bed.isToday ? 2.5 : 1.5
                tag.stroke()
                text(bed.dayLabel, at: NSRect(x: sign.minX, y: sign.minY + 4, width: sign.width, height: 22),
                     font: Paper.markerFont(17), alignment: .center)
                text(bed.total ?? "—", at: NSRect(x: sign.minX, y: sign.minY + 26, width: sign.width, height: 16),
                     font: NSFont.systemFont(ofSize: 11.5), color: Paper.inkLight, alignment: .center)
            } else {
                let patch = NSBezierPath(roundedRect: bed.rect, xRadius: 12, yRadius: 12)
                NSColor.white.withAlphaComponent(bed.isToday ? 0.30 : 0.13).setFill()
                patch.fill()
                if bed.isToday {
                    Paper.accent.setStroke()
                    patch.lineWidth = 2.5
                    patch.stroke()
                }
                let tag = NSRect(x: bed.rect.minX + 6, y: bed.rect.minY + 5, width: bed.dayLabel.count > 1 ? 24 : 20, height: 16)
                let tagShape = NSBezierPath(roundedRect: tag, xRadius: 5, yRadius: 5)
                NSColor(calibratedRed: 0.96, green: 0.89, blue: 0.71, alpha: 1).setFill()
                tagShape.fill()
                outlineInk.setStroke()
                tagShape.lineWidth = 1
                tagShape.stroke()
                text(bed.dayLabel, at: NSRect(x: tag.minX, y: tag.minY + 1, width: tag.width, height: 14),
                     font: NSFont.systemFont(ofSize: 10.5, weight: .semibold), color: Paper.ink, alignment: .center)
                // Un po' di terra sotto le piantine del giorno.
                if bed.hasPlants {
                    let soil = NSBezierPath(ovalIn: NSRect(x: bed.rect.midX - bed.rect.width * 0.38, y: bed.rect.maxY - 17,
                                                           width: bed.rect.width * 0.76, height: 13))
                    soilFill.setFill()
                    soil.fill()
                }
            }
        }
        // Piantine: le dietro prima (sono all'inizio della lista della riga dietro), poi quelle davanti
        for plant in plants {
            image(forPet: plant.info.pet, stage: plant.info.stage)?
                .draw(in: plant.rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            if plant.showsDot {
                let color = plant.info.subject.map { Paper.color(forSubject: $0) } ?? Paper.inkLight.withAlphaComponent(0.55)
                let dot = NSBezierPath(ovalIn: NSRect(x: plant.rect.midX - 6, y: plant.rect.maxY + 3, width: 12, height: 12))
                color.setFill()
                dot.fill()
                // Bordo bianco per staccarsi dalla terra.
                NSColor.white.withAlphaComponent(0.9).setStroke()
                dot.lineWidth = 1
                dot.stroke()
            }
        }
        if kind == .month {
            for bed in beds where bed.extra > 0 {
                text("+\(bed.extra)", at: NSRect(x: bed.rect.maxX - 34, y: bed.rect.minY + 4, width: 28, height: 14),
                     font: NSFont.systemFont(ofSize: 11, weight: .bold), color: Paper.accent, alignment: .right)
            }
        }
        if adultPlants + growingPlants > 0 {
            let strip = NSRect(x: m - 10, y: Self.size.height - 58, width: width - 2 * m + 20, height: 50)
            let shape = NSBezierPath(roundedRect: strip, xRadius: 12, yRadius: 12)
            Paper.paper.withAlphaComponent(0.88).setFill()
            shape.fill()
            text("Ogni 50 minuti di studio in un giorno è una pianta adulta; il resto cresce in una piantina più piccola.",
                 at: NSRect(x: m, y: Self.size.height - 48, width: width - 2 * m, height: 18),
                 font: NSFont.systemFont(ofSize: 12), color: Paper.inkLight)
            let hint = kind == .week
                ? "Il pallino sotto il vaso è la materia. Passa il mouse su una piantina per i dettagli."
                : "Passa il mouse su una piantina per i dettagli."
            text(hint, at: NSRect(x: m, y: Self.size.height - 30, width: width - 2 * m, height: 18),
                 font: NSFont.systemFont(ofSize: 12), color: Paper.inkLight)
        }
        if adultPlants + growingPlants == 0 {
            let y: CGFloat = kind == .week ? 350 : 330
            let pill = NSRect(x: width / 2 - 240, y: y - 8, width: 480, height: 40)
            Paper.paper.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 14, yRadius: 14).fill()
            text("Ancora nessuna piantina in questo periodo.", at: NSRect(x: pill.minX, y: y, width: pill.width, height: 24),
                 font: Paper.markerFont(20), color: Paper.ink, alignment: .center)
        }
    }
}

/// Tiene la finestra del giardino.
final class GardenController {
    private var window: NSWindow?
    private var view: GardenView?
    /// Chiamata dal pulsante «‹ Menu» nella pagina: la finestra si chiude e si torna alla scheda del menu.
    var onBack: (() -> Void)?

    func show() {
        if window == nil {
            let view = GardenView(log: .shared)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: GardenView.size),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = Profile.shared.gardenTitle
            window.contentView = view
            window.isReleasedWhenClosed = false
            window.backgroundColor = Paper.paper
            window.appearance = NSAppearance(named: .aqua)
            view.onBack = { [weak self, weak window] in
                window?.orderOut(nil)
                self?.onBack?()
            }
            window.center()
            self.window = window
            self.view = view
        }
        window?.title = Profile.shared.gardenTitle      // se nel frattempo è cambiato il nome
        view?.select(.week)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private extension Season {
    /// Un numero fisso per stagione (hashValue cambia a ogni avvio): serve a variare erba e fiori.
    var hashValueStable: Int {
        switch self {
        case .spring: return 1
        case .summer: return 2
        case .autumn: return 3
        case .winter: return 4
        }
    }
}
