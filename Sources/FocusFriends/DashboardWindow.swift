import AppKit

/// Una materia da scegliere per l'andamento (nil = tutte), con il suo posto.
private typealias TrendChip = (subject: String?, title: String, rect: NSRect)

/// Le posizioni della vista «Anno»: la mappa (una colonna per settimana, una riga per giorno), i tre numeri e l'andamento.
private struct YearLayout {
    var monthsY: CGFloat = 0
    var grid = NSRect.zero
    var pitch: CGFloat = 1
    var columns = 1
    /// In che riga cade il primo giorno dell'anno (la colonna 0 comincia dal lunedì).
    var firstRow = 0
    var legendY: CGFloat = 0
    var tilesY: CGFloat = 0
    /// Il titolo dell'andamento (nil se non ce n'è uno da mostrare), le materie tra cui scegliere e le barre.
    var trendY: CGFloat?
    var chips: [TrendChip] = []
    var bars = NSRect.zero
    var axisY: CGFloat = 0
}

/// Quello che il mouse sta guardando nella vista «Anno»: un giorno della mappa o una settimana dell'andamento.
private enum YearHover: Equatable {
    case day(Int)
    case week(Int)
}

/// Le posizioni verticali delle parti del riepilogo, calcolate dai dati (vedi DashboardView.buildLayout).
private struct SummaryLayout {
    var year: YearLayout?
    /// Settimana e mese: l'andamento per giorno (il titolo, le materie, le barre) e sotto la riga di quello che c'è sotto il mouse.
    var chartTitleY: CGFloat?
    var chartChips: [TrendChip] = []
    var chartTop: CGFloat?
    var chartTipY: CGFloat?
    /// «Per materia»: il titolo e le righe (una per materia, la più studiata in cima), se nel periodo c'è almeno una materia.
    var subjectsY: CGFloat?
    var subjectRowsY: CGFloat = 0
    /// I giorni di fila e le facce, su una riga.
    var statusY: CGFloat?
    var insightsY: CGFloat?
    /// Dove finisce il riepilogo (in coordinate della pagina): sotto ci sono le sessioni (o, per settimana e mese, il pulsante della tendina).
    var contentEnd: CGFloat = 130
}

/// La pagina che scorre: il riepilogo, il pulsante della tendina e, aperte, le sessioni.
private final class PageView: NSView {
    override var isFlipped: Bool { true }
    weak var owner: DashboardView?

    override func draw(_ dirtyRect: NSRect) {
        owner?.drawSummary()
    }

    // Il mouse serve alle barre della settimana e del mese e alla vista «Anno»: il giorno sotto il cursore, un clic su un giorno o su una materia.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) { owner?.pageHovered(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { owner?.pageHovered(at: nil) }
    override func mouseDown(with event: NSEvent) { owner?.pageClicked(at: convert(event.locationInWindow, from: nil)) }
}

/// La finestra delle statistiche. Il riepilogo è calmo: un grande numero, una barra con le materie, i giorni di
/// fila e come è andata. Per un giorno sotto ci sono subito le sessioni, una per una, con la nota e la faccia;
/// per la settimana e il mese le apre «Mostra le sessioni».
final class DashboardView: NSView {
    static let size = NSSize(width: 560, height: 660)
    private static let margin: CGFloat = 40

    override var isFlipped: Bool { true }

    private let log: SessionLog
    private let now: () -> Date
    private let calendar = StudyPeriod.calendar()

    private var kind: PeriodKind = .day
    private var period: StudyPeriod
    private var summary = StudySummary()
    private var streak = 0
    /// La serie è ghiacciata: ieri non si è studiato, studiando oggi continua.
    private var streakFrozen = false
    /// Le frasi su quando rendi meglio, dal periodo che si guarda (per un giorno: la materia andata bene).
    private var insights: [String] = []
    /// Settimana e mese: un elemento per giorno (della materia scelta, `trendSubject`), le materie tra cui scegliere e il giorno sotto il mouse.
    private var chartDays: [YearStats.Day] = []
    private var chartSubjects: [String] = []
    private var chartHover: Int?
    private var layout = SummaryLayout()
    // La vista «Anno»: i giorni della mappa, i tre numeri, le materie tra cui scegliere e l'andamento per settimana.
    private var yearDays: [YearStats.Day] = []
    private var yearHighlights = YearStats.Highlights()
    private var trendSubjects: [String] = []
    /// La materia scelta per l'andamento dell'anno, della settimana o del mese (nil = tutte).
    private var trendSubject: String?
    private var trendWeeks: [StudyBucket] = []
    private var showsTrend = false
    private var yearHover: YearHover?
    /// La tendina delle sessioni è aperta (sotto il riepilogo, nella stessa pagina).
    private var showsDiary = false
    private let scroll = NSScrollView()
    private let page = PageView()
    private var diary: DiaryView?
    /// Dove comincia la pagina che scorre, nella finestra (sotto l'intestazione).
    private static let pageTop: CGFloat = 96
    private static let footerHeight: CGFloat = 56

    private let segmented = NSSegmentedControl(labels: ["Oggi", "Settimana", "Mese", "Anno"], trackingMode: .selectOne, target: nil, action: nil)
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private let exportButton = NSButton()
    private let deleteButton = NSButton()
    private let sessionsButton = NSButton()
    /// Chiamata dal pulsante «‹ Menu» in alto a sinistra: la finestra si chiude e si torna alla scheda del menu.
    var onBack: (() -> Void)?

    init(log: SessionLog, now: @escaping () -> Date = Date.init) {
        self.log = log
        self.now = now
        self.period = StudyPeriod.containing(now(), kind: .day)
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        // La carta è sempre chiara: i controlli devono avere l'aspetto chiaro anche con il Mac in modalità scura.
        appearance = NSAppearance(named: .aqua)
        let width = Self.size.width

        segmented.selectedSegment = 0
        segmented.segmentStyle = .rounded
        segmented.target = self
        segmented.action = #selector(kindChanged)
        segmented.frame = NSRect(x: (width - 320) / 2, y: 18, width: 320, height: 26)
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
        previousButton.frame = NSRect(x: Self.margin - 6, y: 58, width: 32, height: 28)
        nextButton.frame = NSRect(x: width - Self.margin - 26, y: 58, width: 32, height: 28)
        previousButton.setAccessibilityLabel("Periodo precedente")
        nextButton.setAccessibilityLabel("Periodo successivo")

        func style(_ button: NSButton, _ title: String, color: NSColor, action: Selector, frame: NSRect) {
            button.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 12.5, weight: .medium), .foregroundColor: color,
            ])
            button.isBordered = false
            button.target = self
            button.action = action
            button.frame = frame
            addSubview(button)
        }
        // La pagina che scorre (con la rotella) tra l'intestazione e i pulsanti in fondo.
        let visibleHeight = Self.size.height - Self.pageTop - Self.footerHeight
        scroll.frame = NSRect(x: 0, y: Self.pageTop, width: width, height: visibleHeight)
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        page.frame = NSRect(x: 0, y: 0, width: width, height: visibleHeight)
        page.owner = self
        scroll.documentView = page
        addSubview(scroll)

        let bottom = Self.size.height - 40
        style(deleteButton, "Cancella tutto…", color: Paper.inkLight, action: #selector(deleteEverything),
              frame: NSRect(x: Self.margin - 6, y: bottom, width: 120, height: 24))
        style(exportButton, "Esporta CSV…", color: Paper.inkLight, action: #selector(exportCSV),
              frame: NSRect(x: width - Self.margin - 110, y: bottom, width: 116, height: 24))
        sessionsButton.isBordered = false
        sessionsButton.target = self
        sessionsButton.action = #selector(toggleDiary)
        page.addSubview(sessionsButton)

        // Chiusa la finestra non serve ricalcolare: alla riapertura `select` lo fa. (Minimizzata sì: è ancora lì.)
        log.addObserver { [weak self] in
            guard let self, self.window.map({ $0.isVisible || $0.isMiniaturized }) ?? true else { return }
            self.reload()
        }
        reload()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Dati

    /// Ricalcola tutto (dopo un cambio di scheda, di periodo o del registro).
    func reload() {
        let today = now()
        summary = StudyStats.summary(sessions: log.sessions, period: period, calendar: calendar)
        let streakResult = StudyStreak.analyze(sessions: log.sessions, now: today, calendar: calendar)
        streak = streakResult.days
        streakFrozen = streakResult.isFrozen
        if kind == .day {
            insights = StudyStats.dayInsight(sessions: summary.sessions, calendar: calendar).map { [$0] } ?? []
        } else {
            insights = StudyStats.insights(sessions: summary.sessions, calendar: calendar)
        }
        if kind == .week || kind == .month {
            chartSubjects = YearStats.trendSubjects(of: summary)
            if let chosen = trendSubject, !chartSubjects.contains(where: { Subject.key($0) == Subject.key(chosen) }) { trendSubject = nil }
            chartDays = YearStats.days(sessions: log.sessions, period: period, subject: trendSubject, calendar: calendar)
        } else {
            chartSubjects = []
            chartDays = []
        }
        chartHover = nil
        nextButton.isEnabled = !period.contains(today) && period.end <= today.addingTimeInterval(86_400 * 366)
        nextButton.alphaValue = period.contains(today) ? 0.25 : 1
        if kind == .year { loadYear() }
        layout = buildLayout()
        if kind == .day { showsDiary = true }
        if summary.sessions.isEmpty || kind == .year { showsDiary = false }
        relayoutPage()
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        needsDisplay = true
        page.needsDisplay = true
    }

    func select(_ newKind: PeriodKind) {
        if newKind != kind { trendSubject = nil }
        if newKind != kind { showsDiary = false }
        kind = newKind
        segmented.selectedSegment = newKind.rawValue
        period = StudyPeriod.containing(now(), kind: newKind, calendar: calendar)
        reload()
    }

    @objc private func kindChanged() {
        select(PeriodKind(rawValue: segmented.selectedSegment) ?? .day)
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

    @objc private func toggleDiary() {
        showsDiary.toggle()
        relayoutPage()
        page.needsDisplay = true
        // Aperta: lascio un po' di riepilogo in alto e porto le sessioni in vista. Chiusa: resto dentro la pagina.
        let maxOffset = max(page.frame.height - scroll.contentView.bounds.height, 0)
        var offset = scroll.contentView.bounds.origin.y
        if showsDiary { offset = sessionsButton.frame.minY - 96 }
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(max(offset, 0), maxOffset)))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    /// Sistema la pagina: il pulsante sotto il riepilogo (non per un giorno), la tendina sotto, e l'altezza che scorre.
    private func relayoutPage() {
        updateSessionsButton()
        diary?.removeFromSuperview()
        diary = nil
        let width = Self.size.width
        let visibleHeight = Self.size.height - Self.pageTop - Self.footerHeight
        var end = layout.contentEnd
        if !summary.sessions.isEmpty && kind != .year {
            if kind == .day {
                end = layout.contentEnd + 8
            } else {
                let buttonY = layout.contentEnd + 22
                sessionsButton.frame.origin = NSPoint(x: (width - sessionsButton.frame.width) / 2, y: buttonY)
                end = buttonY + 28
            }
            if showsDiary {
                let view = DiaryView(sessions: summary.sessions.sorted { $0.startTime(in: calendar) < $1.startTime(in: calendar) },
                                     kind: kind, calendar: calendar, width: contentWidth + 24)
                view.onSelect = { [weak self] id in
                    guard let self, let session = self.log.sessions.first(where: { $0.id == id }) else { return }
                    self.edit(session)
                }
                view.frame.origin = NSPoint(x: Self.margin - 12, y: end + 10)
                page.addSubview(view)
                diary = view
                end = view.frame.maxY
            }
        }
        page.frame = NSRect(x: 0, y: 0, width: width, height: max(visibleHeight, end + 24))
    }

    private func updateSessionsButton() {
        let title = showsDiary ? "Nascondi le sessioni" : "Mostra le sessioni"
        let symbol = showsDiary ? "chevron.up" : "chevron.down"
        sessionsButton.attributedTitle = NSAttributedString(string: title + " ", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: Paper.ink,
        ])
        sessionsButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        sessionsButton.imagePosition = .imageTrailing
        sessionsButton.contentTintColor = Paper.ink
        sessionsButton.isHidden = summary.sessions.isEmpty || kind == .year || kind == .day
        // Largo quanto serve, così la freccia sta vicino alla scritta.
        sessionsButton.sizeToFit()
        sessionsButton.frame.size = NSSize(width: sessionsButton.frame.width + 12, height: 28)
    }

    // MARK: - Testi

    private func formatted(_ date: Date, _ format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.timeZone = calendar.timeZone
        f.dateFormat = format
        return f.string(from: date)
    }

    private var periodTitle: String {
        switch kind {
        case .day:
            let title = formatted(period.start, "EEEE d MMMM yyyy")
            return title.prefix(1).uppercased() + title.dropFirst()
        case .week:
            let last = period.end.addingTimeInterval(-1)
            return "\(formatted(period.start, "d MMM")) – \(formatted(last, "d MMM yyyy"))"
        case .month:
            let title = formatted(period.start, "MMMM yyyy")
            return title.prefix(1).uppercased() + title.dropFirst()
        case .year:
            return formatted(period.start, "yyyy")
        }
    }

    /// Sotto al numero: "di studio · 4 focus · 1 interrotto".
    private var subtitle: String {
        guard summary.focusCount > 0 else { return "" }
        var parts = ["di studio", summary.focusCount == 1 ? "1 focus" : "\(summary.focusCount) focus"]
        if summary.interruptedCount == 1 { parts.append("1 interrotto") }
        if summary.interruptedCount > 1 { parts.append("\(summary.interruptedCount) interrotti") }
        return parts.joined(separator: " · ")
    }

    /// Una riga in più, più piccola: una parola gentile oggi, la media negli altri periodi.
    private var secondary: String {
        let isCurrent = period.contains(now())
        guard summary.focusCount > 0 else {
            return isCurrent ? "Quando vuoi, io sono qui." : "Nessun focus in questo periodo."
        }
        switch kind {
        case .day:
            return isCurrent ? StudyStats.encouragement(totalSeconds: summary.totalSeconds) : ""
        case .week, .month, .year:
            let days = summary.buckets.filter { $0.seconds > 0 }.count
            return "In media \(StudyStats.duration(seconds: summary.totalSeconds / max(days, 1))) nei \(days) giorni in cui hai studiato."
        }
    }

    // MARK: - Posizioni

    private var contentWidth: CGFloat { Self.size.width - 2 * Self.margin }

    private func color(for subject: String) -> NSColor {
        if subject == Subject.none || subject.hasPrefix("Altre (") { return Paper.inkLight.withAlphaComponent(0.5) }
        return Paper.color(forSubject: subject)
    }

    private func buildLayout() -> SummaryLayout {
        var l = SummaryLayout()
        guard summary.totalSeconds > 0 else { return l }
        if kind == .year { return buildYearLayout(l) }
        var y: CGFloat = 130
        if kind != .day {
            y += 6
            l.chartTitleY = y
            y += 26
            l.chartChips = trendChips(chartSubjects, y: &y)
            l.chartTop = y
            y += Self.chartHeight + 24
            l.chartTipY = y
            y += 18 + 14
        }
        if kind == .day { y += 10 }
        y = layoutSubjects(&l, from: y) - 4

        if streak > 0 || summary.ratedCount > 0 {
            y += 18
            l.statusY = y
            y += 26
        }
        if !insights.isEmpty {
            y += 8
            l.insightsY = y
            y += CGFloat(insights.count) * 18
        }
        l.contentEnd = y
        return l
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

        // Periodo, al centro tra le frecce
        text(periodTitle, at: NSRect(x: Self.margin + 30, y: 60, width: width - 2 * Self.margin - 60, height: 26),
             font: Paper.markerFont(20), alignment: .center)

    }

    /// Il riepilogo, disegnato nella pagina che scorre (le coordinate partono dal suo bordo alto).
    fileprivate func drawSummary() {
        // Il grande numero
        let empty = summary.totalSeconds == 0
        text(empty ? "0 min" : StudyStats.duration(seconds: summary.totalSeconds),
             at: NSRect(x: Self.margin, y: 8, width: contentWidth, height: 72),
             font: Paper.markerFont(58), color: empty ? Paper.inkLight.withAlphaComponent(0.6) : Paper.ink, alignment: .center)
        if !subtitle.isEmpty {
            text(subtitle, at: NSRect(x: Self.margin, y: 86, width: contentWidth, height: 20),
                 font: NSFont.systemFont(ofSize: 14), color: Paper.inkLight, alignment: .center)
        }
        let more = secondary
        if !more.isEmpty {
            text(more, at: NSRect(x: Self.margin, y: empty ? 86 : 106, width: contentWidth, height: 18),
                 font: NSFont.systemFont(ofSize: 12.5), color: Paper.inkLight.withAlphaComponent(0.85), alignment: .center)
        }
        guard !empty else { return }
        if kind == .year { drawYear(); return }

        if let y = layout.chartTitleY {
            text("Andamento per giorno", at: NSRect(x: Self.margin, y: y, width: 260, height: 18), font: NSFont.systemFont(ofSize: 13, weight: .medium))
            text(YearStats.dayTrendCaption(maxSeconds: chartDays.map { $0.seconds }.max() ?? 0),
                 at: NSRect(x: Self.margin + 200, y: y + 1, width: contentWidth - 200, height: 16),
                 font: NSFont.systemFont(ofSize: 11.5), color: Paper.inkLight, alignment: .right)
            drawTrendChips(layout.chartChips)
        }
        if let top = layout.chartTop { drawMiniChart(top: top) }
        if let y = layout.chartTipY {
            text(chartHoverText, at: NSRect(x: Self.margin, y: y, width: contentWidth, height: 17),
                 font: NSFont.systemFont(ofSize: 12.5), color: chartHover == nil ? Paper.inkLight : Paper.ink, alignment: .center)
        }
        drawSubjects()
        if let y = layout.statusY { drawStatus(y: y) }
        if let y = layout.insightsY {
            for (i, line) in insights.enumerated() {
                text(line, at: NSRect(x: Self.margin, y: y + CGFloat(i) * 18, width: contentWidth, height: 16),
                     font: NSFont.systemFont(ofSize: 12.5), color: Paper.ink, alignment: .center)
            }
        }
    }

    private static let chartHeight: CGFloat = 80

    /// Dove stanno le barre dei giorni (settimana e mese).
    private var chartArea: NSRect {
        NSRect(x: Self.margin, y: layout.chartTop ?? 0, width: contentWidth, height: Self.chartHeight)
    }

    /// Una barra per giorno, alta quanto si è studiato; i giorni che devono ancora venire non hanno la barra. Passandoci
    /// sopra si legge il giorno, cliccandola si apre.
    private func drawMiniChart(top: CGFloat) {
        let area = chartArea
        let maxSeconds = max(chartDays.map { $0.seconds }.max() ?? 0, 1)
        let slot = area.width / CGFloat(max(chartDays.count, 1))
        let barWidth = max(min(slot * 0.55, 22), 3)
        let today = calendar.startOfDay(for: now())
        Paper.paperEdge.withAlphaComponent(0.6).setFill()
        NSRect(x: area.minX, y: area.maxY, width: area.width, height: 1).fill()
        for (i, day) in chartDays.enumerated() {
            let x = area.minX + slot * CGFloat(i) + (slot - barWidth) / 2
            if day.start <= today {
                let height = day.seconds == 0 ? 3 : max(CGFloat(day.seconds) / CGFloat(maxSeconds) * area.height, 5)
                let lit = day.start == today || chartHover == i
                (day.seconds == 0 ? Paper.paperEdge.withAlphaComponent(chartHover == i ? 0.7 : 0.35)
                    : trendColor.withAlphaComponent(lit ? 1 : 0.6)).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: area.maxY - height - 1, width: barWidth, height: height),
                             xRadius: min(barWidth / 2, 4), yRadius: min(barWidth / 2, 4)).fill()
            }

            let label: String?
            switch kind {
            case .week: label = formatted(day.start, "EEE")
            case .month:
                let number = calendar.component(.day, from: day.start)
                label = (number == 1 || number % 5 == 0) ? "\(number)" : nil
            case .day, .year: label = nil
            }
            if let label {
                text(label, at: NSRect(x: x - 10, y: area.maxY + 5, width: barWidth + 20, height: 14),
                     font: NSFont.systemFont(ofSize: 10.5), color: day.start <= today ? Paper.inkLight : Paper.inkLight.withAlphaComponent(0.45),
                     alignment: .center)
            }
        }
    }

    /// Sopra le barre: il giorno sotto il mouse, o come si usa.
    private var chartHoverText: String {
        guard let i = chartHover, chartDays.indices.contains(i) else { return "Clicca un giorno per aprirlo" }
        return YearStats.dayText(chartDays[i], calendar: calendar)
    }

    /// Il giorno della settimana o del mese sotto il punto (solo fino a oggi).
    fileprivate func chartDay(at point: NSPoint) -> Int? {
        guard layout.chartTop != nil, !chartDays.isEmpty else { return nil }
        let area = chartArea.insetBy(dx: 0, dy: -8)
        guard area.contains(point) else { return nil }
        let index = min(max(Int((point.x - area.minX) / (area.width / CGFloat(chartDays.count))), 0), chartDays.count - 1)
        return chartDays[index].start <= calendar.startOfDay(for: now()) ? index : nil
    }

    /// Su una riga: i giorni di fila (con la fiamma, o il fiocco se la serie è ghiacciata) e quante volte bene, così così,
    /// poca testa nel periodo.
    private func drawStatus(y: CGFloat) {
        let font = NSFont.systemFont(ofSize: 13)
        let streakFont = NSFont.systemFont(ofSize: 13, weight: .medium)
        let streakLabel = streak == 0 ? nil
            : (streak == 1 ? "1 giorno di fila" : "\(streak) giorni di fila") + (streakFrozen ? " · ghiacciata: studia oggi" : "")
        let streakWidth = streakLabel.map { 22 + ceil(($0 as NSString).size(withAttributes: [.font: streakFont]).width) } ?? 0
        let faces = summary.ratedCount > 0 ? FocusRating.allCases.map { rating -> (FocusRating, String, CGFloat) in
            let count = "\(summary.ratingCounts[rating] ?? 0)"
            return (rating, count, 24 + ceil((count as NSString).size(withAttributes: [.font: font]).width))
        } : []
        let facesWidth = faces.reduce(0) { $0 + $1.2 } + 12 * CGFloat(max(faces.count - 1, 0))
        let gap: CGFloat = streakLabel != nil && !faces.isEmpty ? 28 : 0
        var x = (Self.size.width - (streakWidth + gap + facesWidth)) / 2

        if let label = streakLabel {
            let iconColor = streakFrozen ? NSColor(calibratedRed: 0.30, green: 0.55, blue: 0.82, alpha: 1) : Paper.accent
            if let flame = Paper.symbolImage(streakFrozen ? "snowflake" : "flame", size: 15, color: iconColor) {
                let s = flame.size
                flame.draw(in: NSRect(x: x, y: y + 11 - s.height / 2, width: s.width, height: s.height), from: .zero,
                           operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            text(label, at: NSRect(x: x + 22, y: y + 2, width: streakWidth - 18, height: 18), font: streakFont, color: Paper.ink)
            x += streakWidth + gap
        }
        for (rating, count, width) in faces {
            FaceIcon.draw(rating, in: NSRect(x: x, y: y + 1, width: 20, height: 20), flipped: true)
            text(count, at: NSRect(x: x + 24, y: y + 2, width: width - 20, height: 18), font: font,
                 color: (summary.ratingCounts[rating] ?? 0) > 0 ? Paper.ink : Paper.inkLight)
            x += width + 12
        }
    }

    // MARK: - Modifica di una sessione

    private func edit(_ session: StudySession) {
        let alert = NSAlert()
        alert.messageText = "Modifica sessione"
        let minutes = (session.seconds + 30) / 60
        alert.informativeText = "\(formatted(session.startTime(in: calendar), "EEEE d MMMM, HH:mm")) · \(minutes) min"

        let field = NSTextField(frame: NSRect(x: 0, y: 30, width: 300, height: 24))
        field.stringValue = session.subject ?? ""
        field.placeholderString = "Materia"
        // Per correggere una materia scritta male (o unirne due) in tutte le sessioni in un colpo solo.
        let everywhere = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        everywhere.frame = NSRect(x: 0, y: 0, width: 300, height: 22)
        if let subject = session.subject {
            everywhere.title = "Cambia la materia in tutte le sessioni «\(subject)»"
        } else {
            everywhere.isHidden = true
        }
        let noteField = NSTextField(frame: NSRect(x: 0, y: 62, width: 300, height: 24))
        noteField.stringValue = session.note ?? ""
        noteField.placeholderString = "Cosa hai fatto? (facoltativo)"
        let ratingControl = NSSegmentedControl(labels: ["Nessun voto"] + FocusRating.allCases.map { $0.title },
                                               trackingMode: .selectOne, target: nil, action: nil)
        ratingControl.controlSize = .small
        ratingControl.frame = NSRect(x: 0, y: 94, width: 300, height: 24)
        ratingControl.selectedSegment = session.rating.flatMap { FocusRating.allCases.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        // Le note scritte durante il focus: una per riga.
        let notesView = NSTextView(frame: NSRect(x: 0, y: 0, width: 292, height: 60))
        notesView.string = (session.notes ?? []).joined(separator: "\n")
        notesView.font = NSFont.systemFont(ofSize: 12)
        notesView.isRichText = false
        notesView.isVerticallyResizable = true
        notesView.textContainerInset = NSSize(width: 2, height: 3)
        let notesScroll = NSScrollView(frame: NSRect(x: 0, y: 126, width: 300, height: 62))
        notesScroll.documentView = notesView
        notesScroll.hasVerticalScroller = true
        notesScroll.borderType = .bezelBorder
        let notesCaption = NSTextField(labelWithString: "Note del focus (una per riga)")
        notesCaption.font = NSFont.systemFont(ofSize: 11)
        notesCaption.textColor = .secondaryLabelColor
        notesCaption.frame = NSRect(x: 0, y: 190, width: 300, height: 14)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 206))
        container.addSubview(notesScroll)
        container.addSubview(notesCaption)
        container.addSubview(field)
        container.addSubview(everywhere)
        container.addSubview(noteField)
        container.addSubview(ratingControl)
        alert.accessoryView = container
        alert.addButton(withTitle: "Salva")
        alert.addButton(withTitle: "Elimina")
        alert.addButton(withTitle: "Annulla")
        alert.window.initialFirstResponder = field
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if everywhere.state == .on, let subject = session.subject {
                log.renameSubject(from: subject, to: field.stringValue)
            } else {
                log.setSubject(id: session.id, subject: field.stringValue)
            }
            let selected = ratingControl.selectedSegment
            let rating = selected >= 1 ? FocusRating.allCases[selected - 1] : nil
            log.setReflection(id: session.id, rating: rating, note: noteField.stringValue)
            log.setNotes(id: session.id, notes: notesView.string.components(separatedBy: .newlines))
        case .alertSecondButtonReturn:
            log.remove(id: session.id)
        default:
            break
        }
    }

    // MARK: - Cancellare tutto

    @objc private func deleteEverything() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Cancellare tutti i dati?"
        let count = log.sessions.count
        alert.informativeText = "Verranno cancellate tutte le sessioni di studio (\(count)), il giardino, le copie di sicurezza e il tuo nome. "
            + "Non si può annullare. Se vuoi tenerle, esportale prima con «Esporta CSV…»."
        let confirm = alert.addButton(withTitle: "Cancella tutto")
        confirm.hasDestructiveAction = true
        alert.addButton(withTitle: "Annulla")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        log.deleteAll()
        Profile.shared.reset()
        Garden.shared.reset()
    }

    // MARK: - Esportazione

    @objc private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "focusfriends-sessioni.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Self.csv(for: log.sessions).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Non riesco a salvare il file"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    static func csv(for sessions: [StudySession]) -> String {
        SessionCSV.csv(for: sessions)
    }
}

// MARK: - Anno

/// La vista «Anno»: una mappa con un quadratino per giorno, tre numeri e l'andamento per settimana (logica in YearStats.swift).
extension DashboardView {
    /// I colori dei livelli (0 = niente ... 4 = tanto): dalla carta al verde.
    private static let heatColors: [NSColor] = [
        Paper.track,
        NSColor(calibratedRed: 0.81, green: 0.89, blue: 0.69, alpha: 1),
        NSColor(calibratedRed: 0.61, green: 0.80, blue: 0.45, alpha: 1),
        NSColor(calibratedRed: 0.37, green: 0.66, blue: 0.29, alpha: 1),
        NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.23, alpha: 1),
    ]

    fileprivate func loadYear() {
        let today = now()
        yearDays = YearStats.days(sessions: log.sessions, period: period, calendar: calendar)
        yearHighlights = YearStats.highlights(sessions: log.sessions, period: period, now: today, calendar: calendar)
        trendSubjects = YearStats.trendSubjects(of: summary)
        if let chosen = trendSubject, !trendSubjects.contains(where: { Subject.key($0) == Subject.key(chosen) }) { trendSubject = nil }
        let all = YearStats.weeklyTrend(sessions: log.sessions, period: period, subject: nil, through: today, calendar: calendar)
        showsTrend = YearStats.showsTrend(all)
        trendWeeks = trendSubject == nil ? all
            : YearStats.weeklyTrend(sessions: log.sessions, period: period, subject: trendSubject, through: today, calendar: calendar)
        yearHover = nil
    }

    fileprivate func buildYearLayout(_ base: SummaryLayout) -> SummaryLayout {
        var l = base
        var year = YearLayout()
        let labelWidth: CGFloat = 24
        year.columns = YearStats.columns(of: period, calendar: calendar)
        year.firstRow = YearStats.cell(of: period.start, in: period, calendar: calendar).row
        year.pitch = (contentWidth - labelWidth) / CGFloat(year.columns)
        year.monthsY = 130
        year.grid = NSRect(x: Self.margin + labelWidth, y: 148, width: year.pitch * CGFloat(year.columns), height: year.pitch * 7)
        year.legendY = year.grid.maxY + 10
        year.tilesY = year.legendY + 36
        var y = year.tilesY + 54 + 28
        y = layoutSubjects(&l, from: y)
        if showsTrend {
            year.trendY = y
            y += 26
            year.chips = trendChips(trendSubjects, y: &y)
            year.bars = NSRect(x: Self.margin, y: y, width: contentWidth, height: 70)
            year.axisY = year.bars.maxY + 4
            y = year.axisY + 18
        }
        l.year = year
        l.contentEnd = y + 6
        return l
    }

    /// «Tutte» e le materie, una dopo l'altra (a capo quando non c'è più posto), da `y`; `y` finisce sotto, con un po' di spazio.
    /// Senza materie (meno di due con un nome) niente.
    fileprivate func trendChips(_ subjects: [String], y: inout CGFloat) -> [TrendChip] {
        guard !subjects.isEmpty else { return [] }
        let font = NSFont.systemFont(ofSize: 12)
        var chips: [TrendChip] = []
        var x = Self.margin
        for subject in [nil] + subjects.map({ Optional($0) }) {
            let title = subject ?? "Tutte"
            let width = ceil((title as NSString).size(withAttributes: [.font: font]).width) + 22
            if x + width > Self.margin + contentWidth, x > Self.margin {
                x = Self.margin
                y += 28
            }
            chips.append((subject: subject, title: title, rect: NSRect(x: x, y: y, width: width, height: 22)))
            x += width + 6
        }
        y += 22 + 12
        return chips
    }

    /// Le materie dell'andamento: quella scelta piena, del suo colore; le altre bianche col bordo.
    fileprivate func drawTrendChips(_ chips: [TrendChip]) {
        for chip in chips {
            let selected = (chip.subject == nil && trendSubject == nil) || (chip.subject.map { Subject.key($0) } == trendSubject.map { Subject.key($0) } && chip.subject != nil)
            let shape = NSBezierPath(roundedRect: chip.rect, xRadius: 11, yRadius: 11)
            let fill = chip.subject.map { Paper.color(forSubject: $0) } ?? Paper.accent
            if selected {
                fill.setFill()
                shape.fill()
            } else {
                NSColor.white.withAlphaComponent(0.5).setFill()
                shape.fill()
                Paper.paperEdge.setStroke()
                shape.lineWidth = 0.8
                shape.stroke()
            }
            text(chip.title, at: NSRect(x: chip.rect.minX + 4, y: chip.rect.minY + 3, width: chip.rect.width - 8, height: 16),
                 font: NSFont.systemFont(ofSize: 12), color: selected ? .white : Paper.ink, alignment: .center)
        }
    }

    private func cellRect(_ index: Int, _ layout: YearLayout) -> NSRect {
        let offset = index + layout.firstRow
        let gap = max(1.5, layout.pitch * 0.2)
        return NSRect(x: layout.grid.minX + CGFloat(offset / 7) * layout.pitch, y: layout.grid.minY + CGFloat(offset % 7) * layout.pitch,
                      width: layout.pitch - gap, height: layout.pitch - gap)
    }

    fileprivate var trendColor: NSColor { trendSubject.map { Paper.color(forSubject: $0) } ?? Paper.accent }

    fileprivate func drawYear() {
        guard let yl = layout.year else { return }
        let today = calendar.startOfDay(for: now())
        let small = NSFont.systemFont(ofSize: 10.5)

        for mark in YearStats.monthStarts(in: period, calendar: calendar) {
            text(YearStats.monthLabel(mark.month), at: NSRect(x: yl.grid.minX + CGFloat(mark.column) * yl.pitch, y: yl.monthsY, width: 40, height: 14),
                 font: small, color: Paper.inkLight)
        }
        for (row, name) in [(0, "lun"), (2, "mer"), (4, "ven")] {
            text(name, at: NSRect(x: Self.margin, y: yl.grid.minY + CGFloat(row) * yl.pitch + (yl.pitch - 12) / 2, width: 24, height: 12),
                 font: NSFont.systemFont(ofSize: 9.5), color: Paper.inkLight)
        }
        for (i, day) in yearDays.enumerated() {
            let rect = cellRect(i, yl)
            let shape = NSBezierPath(roundedRect: rect, xRadius: 1.8, yRadius: 1.8)
            if day.start > today {
                Paper.paperEdge.withAlphaComponent(0.4).setStroke()
                shape.lineWidth = 0.5
                shape.setLineDash([1.5, 1.5], count: 2, phase: 0)
                shape.stroke()
            } else {
                Self.heatColors[day.level].setFill()
                shape.fill()
            }
            if day.start == today {
                Paper.ink.setStroke()
                shape.lineWidth = 1.2
                shape.stroke()
            }
        }
        if case .day(let i)? = yearHover, yearDays.indices.contains(i) {
            let shape = NSBezierPath(roundedRect: cellRect(i, yl).insetBy(dx: -0.5, dy: -0.5), xRadius: 2, yRadius: 2)
            Paper.ink.setStroke()
            shape.lineWidth = 1.6
            shape.stroke()
        }

        // Sotto la mappa: a sinistra cosa c'è sotto il cursore, a destra la scala dei colori.
        text(yearHoverText, at: NSRect(x: Self.margin, y: yl.legendY, width: contentWidth - 150, height: 16),
             font: NSFont.systemFont(ofSize: 12.5), color: yearHover == nil ? Paper.inkLight : Paper.ink)
        let right = Self.margin + contentWidth
        text("più", at: NSRect(x: right - 22, y: yl.legendY, width: 22, height: 14), font: small, color: Paper.inkLight, alignment: .right)
        var x = right - 28
        for level in stride(from: 4, through: 0, by: -1) {
            x -= 13
            Self.heatColors[level].setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: yl.legendY + 2, width: 10, height: 10), xRadius: 2, yRadius: 2).fill()
        }
        text("meno", at: NSRect(x: x - 34, y: yl.legendY, width: 30, height: 14), font: small, color: Paper.inkLight, alignment: .right)

        drawYearTiles(yl)
        drawSubjects()
        if showsTrend { drawTrend(yl) }
    }

    fileprivate static let subjectRowHeight: CGFloat = 24

    /// Dove va «Per materia», da `y`; restituisce dove finisce (con lo spazio sotto). Niente se nel periodo non c'è studio.
    fileprivate func layoutSubjects(_ l: inout SummaryLayout, from y: CGFloat) -> CGFloat {
        guard !summary.bySubject.isEmpty else { return y }
        l.subjectsY = y
        l.subjectRowsY = y + 26
        return l.subjectRowsY + CGFloat(summary.bySubject.count) * Self.subjectRowHeight + 22
    }

    /// Le ore di ogni materia del periodo: il nome, una barra del suo colore (lunga in proporzione alla più studiata) e il tempo.
    fileprivate func drawSubjects() {
        guard let titleY = layout.subjectsY else { return }
        text("Per materia", at: NSRect(x: Self.margin, y: titleY, width: 260, height: 18), font: NSFont.systemFont(ofSize: 13, weight: .medium))
        let rows = summary.bySubject
        let most = CGFloat(max(rows.first?.seconds ?? 1, 1))
        let nameWidth: CGFloat = 150, timeWidth: CGFloat = 70
        let barX = Self.margin + nameWidth + 8, barWidth = contentWidth - nameWidth - timeWidth - 16
        let font = NSFont.systemFont(ofSize: 12.5)
        for (i, row) in rows.enumerated() {
            let y = layout.subjectRowsY + CGFloat(i) * Self.subjectRowHeight
            let tint = color(for: row.subject)
            tint.setFill()
            NSBezierPath(ovalIn: NSRect(x: Self.margin, y: y + 5, width: 9, height: 9)).fill()
            text(row.subject, at: NSRect(x: Self.margin + 15, y: y + 1, width: nameWidth - 15, height: 17), font: font, color: Paper.ink)
            let track = NSRect(x: barX, y: y + 5, width: barWidth, height: 9)
            Paper.track.setFill()
            NSBezierPath(roundedRect: track, xRadius: 4.5, yRadius: 4.5).fill()
            tint.setFill()
            let width = max(barWidth * CGFloat(row.seconds) / most, 9)
            NSBezierPath(roundedRect: NSRect(x: barX, y: track.minY, width: width, height: track.height), xRadius: 4.5, yRadius: 4.5).fill()
            text(StudyStats.duration(seconds: row.seconds), at: NSRect(x: Self.margin + contentWidth - timeWidth, y: y + 1, width: timeWidth, height: 17),
                 font: font, color: Paper.inkLight, alignment: .right)
        }
    }

    private func drawYearTiles(_ yl: YearLayout) {
        let tiles = YearStats.tiles(yearHighlights, calendar: calendar)
        let width = (contentWidth - 16) / 3
        for (i, tile) in tiles.enumerated() {
            let rect = NSRect(x: Self.margin + CGFloat(i) * (width + 8), y: yl.tilesY, width: width, height: 54)
            let shape = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
            NSColor.white.withAlphaComponent(0.5).setFill()
            shape.fill()
            Paper.paperEdge.withAlphaComponent(0.5).setStroke()
            shape.lineWidth = 0.8
            shape.stroke()
            text(tile.value, at: NSRect(x: rect.minX + 6, y: rect.minY + 7, width: rect.width - 12, height: 24), font: Paper.markerFont(19), alignment: .center)
            text(tile.caption, at: NSRect(x: rect.minX + 6, y: rect.minY + 33, width: rect.width - 12, height: 14),
                 font: NSFont.systemFont(ofSize: 11), color: Paper.inkLight, alignment: .center)
        }
    }

    private func drawTrend(_ yl: YearLayout) {
        guard let titleY = yl.trendY else { return }
        text("Andamento per settimana", at: NSRect(x: Self.margin, y: titleY, width: 260, height: 18), font: NSFont.systemFont(ofSize: 13, weight: .medium))
        let most = trendWeeks.map { $0.seconds }.max() ?? 0
        text(YearStats.trendCaption(maxSeconds: most),
             at: NSRect(x: Self.margin + 250, y: titleY + 1, width: contentWidth - 250, height: 16),
             font: NSFont.systemFont(ofSize: 11.5), color: Paper.inkLight, alignment: .right)

        let color = trendColor
        drawTrendChips(yl.chips)

        let bars = yl.bars
        let maxSeconds = max(most, 1)
        let slot = bars.width / CGFloat(max(trendWeeks.count, 1))
        let barWidth = max(slot * 0.7, 2)
        for (i, week) in trendWeeks.enumerated() {
            let height = week.seconds == 0 ? 2 : max(CGFloat(week.seconds) / CGFloat(maxSeconds) * bars.height, 3)
            let x = bars.minX + slot * CGFloat(i) + (slot - barWidth) / 2
            let hovered: Bool
            if case .week(let h)? = yearHover { hovered = h == i } else { hovered = false }
            (week.seconds == 0 ? Paper.paperEdge.withAlphaComponent(0.35) : color.withAlphaComponent(hovered ? 1 : 0.75)).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: bars.maxY - height, width: barWidth, height: height), xRadius: min(barWidth / 2, 2), yRadius: min(barWidth / 2, 2)).fill()
        }
        Paper.paperEdge.withAlphaComponent(0.6).setFill()
        NSRect(x: bars.minX, y: bars.maxY, width: bars.width, height: 1).fill()
        // I mesi sotto le barre, dove una settimana comincia un mese nuovo (e c'è posto per il nome).
        var lastLabelRight = -CGFloat.infinity
        var previousMonth = 0
        for (i, week) in trendWeeks.enumerated() {
            // La prima settimana comincia a volte nell'anno prima (29 dicembre): il suo mese è gennaio.
            let month = calendar.component(.month, from: max(week.start, period.start))
            defer { previousMonth = month }
            guard month != previousMonth else { continue }
            let x = bars.minX + slot * CGFloat(i)
            guard x >= lastLabelRight + 4 else { continue }
            text(YearStats.monthLabel(month), at: NSRect(x: x, y: yl.axisY, width: 30, height: 14), font: NSFont.systemFont(ofSize: 10.5), color: Paper.inkLight)
            lastLabelRight = x + 24
        }
    }

    private var yearHoverText: String {
        switch yearHover {
        case .day(let i)?:
            return yearDays.indices.contains(i) ? YearStats.dayText(yearDays[i], calendar: calendar) : ""
        case .week(let i)?:
            return trendWeeks.indices.contains(i) ? YearStats.weekText(trendWeeks[i], calendar: calendar) : ""
        case nil:
            return "Clicca un giorno per aprirlo"
        }
    }

    // MARK: - Mouse

    private func yearHover(at point: NSPoint) -> YearHover? {
        guard let yl = layout.year else { return nil }
        let today = calendar.startOfDay(for: now())
        if yl.grid.contains(point) {
            let column = Int((point.x - yl.grid.minX) / yl.pitch), row = Int((point.y - yl.grid.minY) / yl.pitch)
            let index = column * 7 + row - yl.firstRow
            if yearDays.indices.contains(index), yearDays[index].start <= today { return .day(index) }
        } else if showsTrend, !trendWeeks.isEmpty, yl.bars.insetBy(dx: 0, dy: -6).contains(point) {
            let slot = yl.bars.width / CGFloat(trendWeeks.count)
            return .week(min(max(Int((point.x - yl.bars.minX) / slot), 0), trendWeeks.count - 1))
        }
        return nil
    }

    private func chipIndex(at point: NSPoint) -> Int? {
        (kind == .year ? layout.year?.chips ?? [] : layout.chartChips).firstIndex { $0.rect.contains(point) }
    }

    fileprivate func pageHovered(at point: NSPoint?) {
        if kind == .week || kind == .month {
            let hover = point.flatMap { chartDay(at: $0) }
            if hover != chartHover {
                chartHover = hover
                page.needsDisplay = true
            }
            (hover != nil || point.flatMap { chipIndex(at: $0) } != nil ? NSCursor.pointingHand : NSCursor.arrow).set()
            return
        }
        guard kind == .year else { return }
        let hover = point.flatMap { yearHover(at: $0) }
        let overChip = point.flatMap { chipIndex(at: $0) } != nil
        if hover != yearHover {
            yearHover = hover
            page.needsDisplay = true
        }
        var clickable = overChip
        if case .day? = hover { clickable = true }
        (clickable ? NSCursor.pointingHand : NSCursor.arrow).set()
    }

    fileprivate func pageClicked(at point: NSPoint) {
        if kind == .week || kind == .month {
            if let i = chipIndex(at: point) {
                trendSubject = layout.chartChips[i].subject
                chartDays = YearStats.days(sessions: log.sessions, period: period, subject: trendSubject, calendar: calendar)
                page.needsDisplay = true
            } else if let i = chartDay(at: point) {
                openDay(chartDays[i].start)
            }
            return
        }
        guard kind == .year, let yl = layout.year else { return }
        if let i = chipIndex(at: point) {
            trendSubject = yl.chips[i].subject
            trendWeeks = YearStats.weeklyTrend(sessions: log.sessions, period: period, subject: trendSubject, through: now(), calendar: calendar)
            page.needsDisplay = true
        } else if case .day(let i)? = yearHover(at: point), yearDays.indices.contains(i) {
            openDay(yearDays[i].start)
        }
    }

    /// Un giorno della mappa o delle barre si apre in «Oggi», con le sue sessioni.
    private func openDay(_ start: Date) {
        kind = .day
        segmented.selectedSegment = PeriodKind.day.rawValue
        trendSubject = nil
        period = StudyPeriod.containing(start, kind: .day, calendar: calendar)
        reload()
    }
}

/// Il diario: le sessioni una per una, con la nota e la faccia. Per un giorno solo, in cima c'è la striscia delle
/// ore con un blocco colorato per ogni focus; per una settimana o un mese le sessioni stanno sotto il loro giorno.
private final class DiaryView: NSView {
    override var isFlipped: Bool { true }
    var onSelect: ((UUID) -> Void)?

    private enum Entry {
        case strip
        case header(day: Date, seconds: Int)
        case session(StudySession)
    }

    private var entries: [(entry: Entry, rect: NSRect)] = []
    private let sessions: [StudySession]
    private let kind: PeriodKind
    private let calendar: Calendar
    private let dayFormatter = DateFormatter()
    private let timeFormatter = DateFormatter()

    init(sessions: [StudySession], kind: PeriodKind, calendar: Calendar, width: CGFloat) {
        self.sessions = sessions
        self.kind = kind
        self.calendar = calendar
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        for f in [dayFormatter, timeFormatter] {
            f.locale = Locale(identifier: "it_IT")
            f.timeZone = calendar.timeZone
        }
        dayFormatter.dateFormat = "EEEE d MMMM"
        timeFormatter.dateFormat = "HH:mm"
        appearance = NSAppearance(named: .aqua)
        layoutEntries(width: width)
    }

    required init?(coder: NSCoder) { nil }

    private func layoutEntries(width: CGFloat) {
        var y: CGFloat = 4
        entries = []
        if kind == .day {
            entries.append((.strip, NSRect(x: 0, y: y, width: width, height: 58)))
            y += 70
        }
        var currentDay: Date?
        for (i, session) in sessions.enumerated() {
            if kind != .day {
                let day = calendar.startOfDay(for: session.startTime(in: calendar))
                if currentDay != day {
                    currentDay = day
                    let seconds = sessions.filter { calendar.startOfDay(for: $0.startTime(in: calendar)) == day }
                        .reduce(0) { $0 + $1.seconds }
                    y += i == 0 ? 0 : 10
                    entries.append((.header(day: day, seconds: seconds), NSRect(x: 0, y: y, width: width, height: 34)))
                    y += 36
                }
            }
            let extraLines = (session.note == nil ? 0 : 1) + (Self.focusNotesLine(session) == nil ? 0 : 1)
            let height: CGFloat = 34 + CGFloat(extraLines) * 16
            entries.append((.session(session), NSRect(x: 0, y: y, width: width, height: height)))
            y += height
        }
        setFrameSize(NSSize(width: width, height: y + 12))
    }

    /// Le note scritte durante il focus, su una riga ("Note: una · due"), o nil se non ce ne sono.
    private static func focusNotesLine(_ session: StudySession) -> String? {
        guard let notes = session.notes, !notes.isEmpty else { return nil }
        return "Note: " + notes.joined(separator: "  ·  ")
    }

    private func color(for session: StudySession) -> NSColor {
        session.subject.map { Paper.color(forSubject: $0) } ?? Paper.inkLight.withAlphaComponent(0.5)
    }

    private func text(_ string: String, in rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .left) {
        let para = NSMutableParagraphStyle()
        para.alignment = alignment
        para.lineBreakMode = .byTruncatingTail
        (string as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
    }

    override func draw(_ dirtyRect: NSRect) {
        for item in entries where item.rect.intersects(dirtyRect) {
            switch item.entry {
            case .strip: drawStrip(in: item.rect)
            case .header(let day, let seconds): drawHeader(day: day, seconds: seconds, in: item.rect)
            case .session(let session): drawSession(session, in: item.rect)
            }
        }
    }

    /// Le ore del giorno in orizzontale, con un blocco per ogni focus (colore della materia).
    private func drawStrip(in rect: NSRect) {
        guard !sessions.isEmpty else { return }
        func hours(_ s: StudySession) -> (start: Double, end: Double) {
            let t = s.startTime(in: calendar)
            let c = calendar.dateComponents([.hour, .minute], from: t)
            let start = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
            return (start, start + Double(s.seconds) / 3600)
        }
        let spans = sessions.map(hours)
        let lo = max(min(8, Int(spans.map { $0.start }.min() ?? 8)), 0)
        let hi = min(max(18, Int(ceil(spans.map { $0.end }.max() ?? 18))), 24)
        let inner = NSRect(x: rect.minX + 12, y: rect.minY, width: rect.width - 24, height: rect.height)
        let span = Double(max(hi - lo, 1))
        let baseline = inner.minY + 36

        for (i, session) in sessions.enumerated() {
            let x = inner.minX + CGFloat((spans[i].start - Double(lo)) / span) * inner.width
            let w = max(CGFloat((spans[i].end - spans[i].start) / span) * inner.width, 6)
            color(for: session).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: baseline - 26, width: w, height: 26), xRadius: 5, yRadius: 5).fill()
        }
        Paper.paperEdge.setStroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: inner.minX, y: baseline + 0.5))
        line.line(to: NSPoint(x: inner.maxX, y: baseline + 0.5))
        line.lineWidth = 1
        line.stroke()
        let step = (hi - lo) > 12 ? 3 : 2
        var h = lo
        while h <= hi {
            let x = inner.minX + CGFloat(Double(h - lo) / span) * inner.width
            text("\(h)", in: NSRect(x: x - 14, y: baseline + 6, width: 28, height: 14),
                 font: NSFont.systemFont(ofSize: 10.5), color: Paper.inkLight, alignment: .center)
            h += step
        }
    }

    private func drawHeader(day: Date, seconds: Int, in rect: NSRect) {
        let title = dayFormatter.string(from: day)
        text(title.prefix(1).uppercased() + title.dropFirst(), in: NSRect(x: rect.minX + 12, y: rect.minY + 6, width: rect.width - 130, height: 24),
             font: Paper.markerFont(16), color: Paper.ink)
        text(StudyStats.duration(seconds: seconds), in: NSRect(x: rect.maxX - 112, y: rect.minY + 9, width: 100, height: 18),
             font: NSFont.systemFont(ofSize: 12.5), color: Paper.inkLight, alignment: .right)
        Paper.paperEdge.setStroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: rect.minX + 12, y: rect.maxY - 0.5))
        line.line(to: NSPoint(x: rect.maxX - 12, y: rect.maxY - 0.5))
        line.lineWidth = 1
        line.stroke()
    }

    private func drawSession(_ session: StudySession, in rect: NSRect) {
        let dotY = rect.minY + 12
        color(for: session).setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.minX + 12, y: dotY, width: 9, height: 9)).fill()
        text(timeFormatter.string(from: session.startTime(in: calendar)),
             in: NSRect(x: rect.minX + 30, y: rect.minY + 8, width: 48, height: 18),
             font: NSFont.systemFont(ofSize: 13), color: Paper.inkLight)

        let right = rect.maxX - 12
        let durationWidth: CGFloat = 112
        let minutes = (session.seconds + 30) / 60
        let status = session.completed ? "\(minutes) min" : "\(minutes) min · interrotto"
        text(status, in: NSRect(x: right - durationWidth, y: rect.minY + 8, width: durationWidth, height: 18),
             font: NSFont.systemFont(ofSize: 12), color: session.completed ? Paper.inkLight : Paper.accent, alignment: .right)
        var textRight = right - durationWidth - 6
        if let rating = session.rating {
            FaceIcon.draw(rating, in: NSRect(x: right - durationWidth - 28, y: rect.minY + 8, width: 18, height: 18), flipped: true)
            textRight -= 26
        }
        let textX = rect.minX + 84
        text(session.subject ?? Subject.none, in: NSRect(x: textX, y: rect.minY + 8, width: max(textRight - textX, 40), height: 18),
             font: NSFont.systemFont(ofSize: 13.5, weight: .medium), color: Paper.ink)
        var lineY = rect.minY + 27
        if let note = session.note {
            text(note, in: NSRect(x: textX, y: lineY, width: max(textRight - textX, 40), height: 16),
                 font: NSFont.systemFont(ofSize: 12), color: Paper.inkLight)
            lineY += 16
        }
        if let line = Self.focusNotesLine(session) {
            text(line, in: NSRect(x: textX, y: lineY, width: max(right - textX, 40), height: 16),
                 font: NSFont.systemFont(ofSize: 12), color: Paper.inkLight)
        }
        // Linea tratteggiata sotto, come le righe di un quaderno.
        Paper.paperEdge.withAlphaComponent(0.5).setStroke()
        let dash = NSBezierPath()
        dash.move(to: NSPoint(x: rect.minX + 12, y: rect.maxY - 0.5))
        dash.line(to: NSPoint(x: rect.maxX - 12, y: rect.maxY - 0.5))
        dash.setLineDash([3, 3], count: 2, phase: 0)
        dash.lineWidth = 1
        dash.stroke()
    }

    // MARK: - Mouse

    private func sessionID(at point: NSPoint) -> UUID? {
        for item in entries {
            if case .session(let s) = item.entry, item.rect.contains(point) { return s.id }
        }
        return nil
    }

    override func resetCursorRects() {
        for item in entries {
            if case .session = item.entry { addCursorRect(item.rect, cursor: .pointingHand) }
        }
    }

    override func mouseDown(with event: NSEvent) {
        if let id = sessionID(at: convert(event.locationInWindow, from: nil)) { onSelect?(id) }
    }
}

/// Tiene la finestra delle statistiche: la crea alla prima richiesta e poi la riporta davanti.
final class DashboardController {
    private var window: NSWindow?
    private var view: DashboardView?
    /// Chiamata dal pulsante «‹ Menu» nella pagina: la finestra si chiude e si torna alla scheda del menu.
    var onBack: (() -> Void)?

    func show(kind: PeriodKind = .day) {
        if window == nil {
            let view = DashboardView(log: .shared)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: DashboardView.size),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = Profile.shared.statsTitle
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
        window?.title = Profile.shared.statsTitle
        view?.select(kind)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
