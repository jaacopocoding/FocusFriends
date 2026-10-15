import AppKit

/// Un'etichetta della legenda delle materie.
private struct LegendItem {
    var text: String
    var color: NSColor
    var width: CGFloat
}

/// Le posizioni verticali delle parti del riepilogo, calcolate dai dati (vedi DashboardView.buildLayout).
private struct SummaryLayout {
    var chartTop: CGFloat?
    var barY: CGFloat?
    var legend: [(items: [LegendItem], y: CGFloat)] = []
    var streakY: CGFloat?
    var reflectY: CGFloat?
    var insightsY: CGFloat?
    /// Dove finisce il riepilogo (in coordinate della pagina): sotto c'è il pulsante della tendina.
    var contentEnd: CGFloat = 130
}

/// La pagina che scorre: il riepilogo, il pulsante della tendina e, aperte, le sessioni.
private final class PageView: NSView {
    override var isFlipped: Bool { true }
    weak var owner: DashboardView?

    override func draw(_ dirtyRect: NSRect) {
        owner?.drawSummary()
    }
}

/// La finestra delle statistiche. Il riepilogo è calmo: un grande numero, una barra con le materie, i giorni di
/// fila e come è andata. «Mostra le sessioni» apre il diario: le sessioni una per una, con la nota e la faccia.
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
    /// Le frasi su "quando rendi meglio" (da tutte le sessioni con un voto) e quante sessioni hanno un voto.
    private var insights: [String] = []
    private var totalRated = 0
    private var layout = SummaryLayout()
    /// La tendina delle sessioni è aperta (sotto il riepilogo, nella stessa pagina).
    private var showsDiary = false
    private let scroll = NSScrollView()
    private let page = PageView()
    private var diary: DiaryView?
    /// Dove comincia la pagina che scorre, nella finestra (sotto l'intestazione).
    private static let pageTop: CGFloat = 96
    private static let footerHeight: CGFloat = 56

    private let segmented = NSSegmentedControl(labels: ["Oggi", "Settimana", "Mese"], trackingMode: .selectOne, target: nil, action: nil)
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
        segmented.frame = NSRect(x: (width - 260) / 2, y: 18, width: 260, height: 26)
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
        insights = StudyStats.insights(sessions: log.sessions, calendar: calendar)
        totalRated = log.sessions.filter { $0.rating != nil }.count
        nextButton.isEnabled = !period.contains(today) && period.end <= today.addingTimeInterval(86_400 * 366)
        nextButton.alphaValue = period.contains(today) ? 0.25 : 1
        layout = buildLayout()
        if summary.sessions.isEmpty { showsDiary = false }
        relayoutPage()
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        needsDisplay = true
        page.needsDisplay = true
    }

    func select(_ newKind: PeriodKind) {
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

    /// Sistema la pagina: il pulsante sotto il riepilogo, la tendina sotto il pulsante, e l'altezza che scorre.
    private func relayoutPage() {
        updateSessionsButton()
        diary?.removeFromSuperview()
        diary = nil
        let width = Self.size.width
        let visibleHeight = Self.size.height - Self.pageTop - Self.footerHeight
        var end = layout.contentEnd
        if !summary.sessions.isEmpty {
            let buttonY = layout.contentEnd + 22
            sessionsButton.frame.origin = NSPoint(x: (width - sessionsButton.frame.width) / 2, y: buttonY)
            end = buttonY + 28
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
        sessionsButton.isHidden = summary.sessions.isEmpty
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
        case .week, .month:
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

    /// Le materie del periodo: fino a sei, il resto in "Altre (n)".
    private var subjectRows: [(subject: String, seconds: Int)] {
        var rows = Array(summary.bySubject.prefix(6))
        if summary.bySubject.count > 6 {
            let rest = summary.bySubject.dropFirst(6)
            rows.append((subject: "Altre (\(rest.count))", seconds: rest.reduce(0) { $0 + $1.seconds }))
        }
        return rows
    }

    private func buildLayout() -> SummaryLayout {
        var l = SummaryLayout()
        guard summary.totalSeconds > 0 else { return l }
        var y: CGFloat = 130
        if kind != .day {
            l.chartTop = y
            y += 56 + 20 + 22
        }
        l.barY = y
        y += 18 + 16

        // La legenda: i nomi a capo quando non c'è più posto, ogni riga centrata.
        let font = NSFont.systemFont(ofSize: 12)
        let items = subjectRows.map { row -> LegendItem in
            let text = "\(row.subject) \(StudyStats.duration(seconds: row.seconds))"
            let width = ceil((text as NSString).size(withAttributes: [.font: font]).width) + 14
            return LegendItem(text: text, color: color(for: row.subject), width: width)
        }
        var line: [LegendItem] = []
        var lineWidth: CGFloat = 0
        for item in items {
            if lineWidth + item.width > contentWidth, !line.isEmpty {
                l.legend.append((items: line, y: y))
                y += 20
                line = []
                lineWidth = 0
            }
            line.append(item)
            lineWidth += item.width + 12
        }
        if !line.isEmpty {
            l.legend.append((items: line, y: y))
            y += 20
        }

        if streak > 0 {
            y += 18
            l.streakY = y
            y += 24
        }
        if summary.ratedCount > 0 {
            y += 16
            l.reflectY = y
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

        if let top = layout.chartTop { drawMiniChart(top: top) }
        if let y = layout.barY { drawSubjectBar(y: y) }
        for line in layout.legend { drawLegendLine(line.items, y: line.y) }
        if let y = layout.streakY { drawStreak(y: y) }
        if let y = layout.reflectY { drawRatings(y: y) }
        if let y = layout.insightsY {
            for (i, line) in insights.enumerated() {
                text(line, at: NSRect(x: Self.margin, y: y + CGFloat(i) * 18, width: contentWidth, height: 16),
                     font: NSFont.systemFont(ofSize: 12.5), color: Paper.ink, alignment: .center)
            }
        }
    }

    /// Le barre sottili, una per giorno: niente numeri, solo la forma della settimana o del mese.
    private func drawMiniChart(top: CGFloat) {
        let buckets = summary.buckets
        let maxSeconds = max(buckets.map { $0.seconds }.max() ?? 0, 1)
        let area = NSRect(x: Self.margin, y: top, width: contentWidth, height: 56)
        let slot = area.width / CGFloat(max(buckets.count, 1))
        let barWidth = max(min(slot * 0.55, 22), 3)
        let today = calendar.startOfDay(for: now())
        for (i, bucket) in buckets.enumerated() {
            let x = area.minX + slot * CGFloat(i) + (slot - barWidth) / 2
            let height = bucket.seconds == 0 ? 3 : max(CGFloat(bucket.seconds) / CGFloat(maxSeconds) * area.height, 5)
            let isToday = calendar.startOfDay(for: bucket.start) == today
            (bucket.seconds == 0 ? Paper.paperEdge.withAlphaComponent(0.35)
                : isToday ? Paper.accent : Paper.accent.withAlphaComponent(0.55)).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: area.maxY - height, width: barWidth, height: height),
                         xRadius: min(barWidth / 2, 4), yRadius: min(barWidth / 2, 4)).fill()

            let label: String?
            switch kind {
            case .week: label = formatted(bucket.start, "EEE")
            case .month:
                let day = calendar.component(.day, from: bucket.start)
                label = (day == 1 || day % 5 == 0) ? "\(day)" : nil
            case .day: label = nil
            }
            if let label {
                text(label, at: NSRect(x: x - 10, y: area.maxY + 5, width: barWidth + 20, height: 14),
                     font: NSFont.systemFont(ofSize: 10.5), color: Paper.inkLight, alignment: .center)
            }
        }
    }

    /// Una sola barra, a segmenti, con le materie del periodo.
    private func drawSubjectBar(y: CGFloat) {
        let rect = NSRect(x: Self.margin + 20, y: y, width: contentWidth - 40, height: 18)
        let rows = subjectRows
        let total = max(rows.reduce(0) { $0 + $1.seconds }, 1)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).addClip()
        Paper.track.setFill()
        rect.fill()
        let gap: CGFloat = 2
        let usable = rect.width - gap * CGFloat(max(rows.count - 1, 0))
        var x = rect.minX
        for row in rows {
            let w = max(usable * CGFloat(row.seconds) / CGFloat(total), 5)
            color(for: row.subject).setFill()
            NSRect(x: x, y: rect.minY, width: w, height: rect.height).fill()
            x += w + gap
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawLegendLine(_ items: [LegendItem], y: CGFloat) {
        let total = items.reduce(0) { $0 + $1.width } + 12 * CGFloat(max(items.count - 1, 0))
        var x = (Self.size.width - total) / 2
        for item in items {
            item.color.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: y + 4, width: 9, height: 9)).fill()
            text(item.text, at: NSRect(x: x + 14, y: y, width: item.width, height: 17),
                 font: NSFont.systemFont(ofSize: 12), color: Paper.ink)
            x += item.width + 12
        }
    }

    private func drawStreak(y: CGFloat) {
        let label = (streak == 1 ? "1 giorno di fila" : "\(streak) giorni di fila") + (streakFrozen ? " · ghiacciata: studia oggi" : "")
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let textWidth = ceil((label as NSString).size(withAttributes: [.font: font]).width)
        let x = (Self.size.width - (22 + textWidth)) / 2
        let iconColor = streakFrozen ? NSColor(calibratedRed: 0.30, green: 0.55, blue: 0.82, alpha: 1) : Paper.accent
        if let flame = Paper.symbolImage(streakFrozen ? "snowflake" : "flame", size: 15, color: iconColor) {
            let s = flame.size
            flame.draw(in: NSRect(x: x, y: y + 12 - s.height / 2, width: s.width, height: s.height), from: .zero,
                       operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        text(label, at: NSRect(x: x + 22, y: y + 3, width: textWidth + 4, height: 18), font: font, color: Paper.ink)
    }

    /// Quante volte bene, così così, poca testa nel periodo.
    private func drawRatings(y: CGFloat) {
        let font = NSFont.systemFont(ofSize: 13)
        let parts = FocusRating.allCases.map { rating -> (FocusRating, String) in
            (rating, "\(rating.title) \(summary.ratingCounts[rating] ?? 0)")
        }
        let widths = parts.map { ceil(($0.1 as NSString).size(withAttributes: [.font: font]).width) + 28 }
        let total = widths.reduce(0, +) + 16 * CGFloat(parts.count - 1)
        var x = (Self.size.width - total) / 2
        for (i, part) in parts.enumerated() {
            FaceIcon.draw(part.0, in: NSRect(x: x, y: y, width: 20, height: 20), flipped: true)
            text(part.1, at: NSRect(x: x + 26, y: y + 1, width: widths[i], height: 18), font: font,
                 color: (summary.ratingCounts[part.0] ?? 0) > 0 ? Paper.ink : Paper.inkLight)
            x += widths[i] + 16
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
