import AppKit

/// La finestra delle statistiche: tre schede (Oggi, Settimana, Mese) con i totali, un grafico per giorno
/// (o per ora), le materie e l'elenco delle sessioni. "Oggi" è anche il riepilogo della giornata.
final class DashboardView: NSView {
    static let size = NSSize(width: 620, height: 660)
    private static let margin: CGFloat = 28

    override var isFlipped: Bool { true }

    private let log: SessionLog
    private let now: () -> Date
    private let calendar = StudyPeriod.calendar()

    private var kind: PeriodKind = .day
    private var period: StudyPeriod
    private var summary = StudySummary()
    private var streak = 0
    /// I rettangoli delle righe dell'elenco, per cliccarle (modifica o elimina).
    private var rowHits: [(rect: NSRect, id: UUID)] = []

    private let segmented = NSSegmentedControl(labels: ["Oggi", "Settimana", "Mese"], trackingMode: .selectOne, target: nil, action: nil)
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private let exportButton = NSButton()
    private let deleteButton = NSButton()

    init(log: SessionLog, now: @escaping () -> Date = Date.init) {
        self.log = log
        self.now = now
        self.period = StudyPeriod.containing(now(), kind: .day)
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        // La carta è sempre chiara: i controlli devono avere l'aspetto chiaro anche con il Mac in modalità scura.
        appearance = NSAppearance(named: .aqua)

        segmented.selectedSegment = 0
        segmented.segmentStyle = .rounded
        segmented.target = self
        segmented.action = #selector(kindChanged)
        segmented.frame = NSRect(x: Self.margin, y: 18, width: 250, height: 26)
        addSubview(segmented)

        for (button, symbol, action) in [(previousButton, "chevron.left", #selector(goPrevious)), (nextButton, "chevron.right", #selector(goNext))] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.isBordered = false
            button.contentTintColor = Paper.ink
            button.target = self
            button.action = action
            addSubview(button)
        }
        previousButton.frame = NSRect(x: Self.margin, y: 56, width: 32, height: 28)
        nextButton.frame = NSRect(x: Self.size.width - Self.margin - 32, y: 56, width: 32, height: 28)

        exportButton.attributedTitle = NSAttributedString(string: "Esporta CSV…", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: Paper.inkLight,
        ])
        exportButton.isBordered = false
        exportButton.target = self
        exportButton.action = #selector(exportCSV)
        exportButton.frame = NSRect(x: Self.size.width - Self.margin - 120, y: 18, width: 120, height: 26)
        addSubview(exportButton)

        deleteButton.attributedTitle = NSAttributedString(string: "Cancella tutto…", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: Paper.accent,
        ])
        deleteButton.isBordered = false
        deleteButton.target = self
        deleteButton.action = #selector(deleteEverything)
        deleteButton.frame = NSRect(x: Self.size.width - Self.margin - 120 - 124, y: 18, width: 124, height: 26)
        addSubview(deleteButton)

        log.addObserver { [weak self] in self?.reload() }
        reload()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Dati

    /// Ricalcola tutto (dopo un cambio di scheda, di periodo o del registro).
    func reload() {
        let today = now()
        summary = StudyStats.summary(sessions: log.sessions, period: period, calendar: calendar)
        streak = StudyStats.streak(sessions: log.sessions, now: today, calendar: calendar)
        nextButton.isEnabled = !period.contains(today) && period.end <= today.addingTimeInterval(86_400 * 366)
        nextButton.alphaValue = period.contains(today) ? 0.25 : 1
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
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

    @objc private func goPrevious() {
        period = period.shifted(by: -1, calendar: calendar)
        reload()
    }

    @objc private func goNext() {
        guard !period.contains(now()) else { return }
        period = period.shifted(by: 1, calendar: calendar)
        reload()
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

    private var bannerLines: (String, String) {
        let isCurrent = period.contains(now())
        switch kind {
        case .day:
            let dayName = formatted(period.start, "EEEE")
            let line = StudyStats.dayLine(summary, isToday: isCurrent, dayName: dayName.prefix(1).uppercased() + dayName.dropFirst())
            return (line, isCurrent ? StudyStats.encouragement(totalSeconds: summary.totalSeconds) : "")
        case .week, .month:
            let name = kind == .week ? (isCurrent ? "Questa settimana" : "In questa settimana") : (isCurrent ? "Questo mese" : "In questo mese")
            guard summary.focusCount > 0 else { return ("\(name) non hai ancora fatto nessun focus.", "") }
            let days = summary.buckets.filter { $0.seconds > 0 }.count
            let average = summary.totalSeconds / max(days, 1)
            let focus = summary.focusCount == 1 ? "1 focus" : "\(summary.focusCount) focus"
            return ("\(name) hai fatto \(focus): \(StudyStats.duration(seconds: summary.totalSeconds)) di studio.",
                    "In media \(StudyStats.duration(seconds: average)) nei \(days) giorni in cui hai studiato.")
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
        Paper.paper.setFill()
        bounds.fill()
        let width = Self.size.width
        let m = Self.margin
        rowHits = []

        // Periodo, al centro tra le frecce
        text(periodTitle, at: NSRect(x: m + 40, y: 58, width: width - 2 * m - 80, height: 26),
             font: Paper.markerFont(20), alignment: .center)

        // Riga di riepilogo
        let banner = bannerLines
        let bannerRect = NSRect(x: m, y: 96, width: width - 2 * m, height: 50)
        let bannerShape = NSBezierPath(roundedRect: bannerRect, xRadius: 12, yRadius: 12)
        Paper.accent.withAlphaComponent(0.12).setFill()
        bannerShape.fill()
        text(banner.0, at: NSRect(x: bannerRect.minX + 14, y: bannerRect.minY + 8, width: bannerRect.width - 28, height: 22),
             font: Paper.markerFont(17))
        if !banner.1.isEmpty {
            text(banner.1, at: NSRect(x: bannerRect.minX + 14, y: bannerRect.minY + 29, width: bannerRect.width - 28, height: 16),
                 font: NSFont.systemFont(ofSize: 12), color: Paper.inkLight)
        }

        // Tre tessere
        let tileWidth = (width - 2 * m - 24) / 3
        let tiles: [(String, String)] = [
            (StudyStats.duration(seconds: summary.totalSeconds), "di studio"),
            ("\(summary.focusCount)", (summary.focusCount == 1 ? "focus" : "focus")
                + (summary.interruptedCount == 1 ? " · 1 interrotto" : summary.interruptedCount > 1 ? " · \(summary.interruptedCount) interrotti" : "")),
            ("\(streak)", streak == 1 ? "giorno di fila" : "giorni di fila"),
        ]
        for (i, tile) in tiles.enumerated() {
            let rect = NSRect(x: m + CGFloat(i) * (tileWidth + 12), y: 158, width: tileWidth, height: 70)
            let shape = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
            NSColor.white.withAlphaComponent(0.55).setFill()
            shape.fill()
            Paper.paperEdge.setStroke()
            shape.lineWidth = 1
            shape.stroke()
            text(tile.0, at: NSRect(x: rect.minX + 12, y: rect.minY + 8, width: rect.width - 24, height: 32), font: Paper.markerFont(26))
            text(tile.1, at: NSRect(x: rect.minX + 12, y: rect.minY + 44, width: rect.width - 24, height: 16),
                 font: NSFont.systemFont(ofSize: 11.5), color: Paper.inkLight)
        }

        drawChart(top: 240)
        drawSubjects(top: 392)
        drawSessions(top: 524)
    }

    private func sectionTitle(_ title: String, y: CGFloat) {
        text(title, at: NSRect(x: Self.margin, y: y, width: 300, height: 18),
             font: NSFont.systemFont(ofSize: 12, weight: .semibold), color: Paper.inkLight)
    }

    /// Le barre: minuti per ora (giorno) o per giorno (settimana, mese).
    private func drawChart(top: CGFloat) {
        let width = Self.size.width
        let m = Self.margin
        sectionTitle(kind == .day ? "MINUTI PER ORA" : "MINUTI PER GIORNO", y: top)
        let area = NSRect(x: m, y: top + 24, width: width - 2 * m, height: 90)
        let buckets = summary.buckets
        let maxSeconds = max(buckets.map { $0.seconds }.max() ?? 0, 1)

        guard summary.totalSeconds > 0 else {
            text("Nessun focus in questo periodo. Avvia un Pomofocus e comparirà qui!",
                 at: NSRect(x: area.minX, y: area.minY + 34, width: area.width, height: 20),
                 font: NSFont.systemFont(ofSize: 13), color: Paper.inkLight, alignment: .center)
            return
        }

        let slot = area.width / CGFloat(buckets.count)
        let barWidth = max(min(slot * 0.68, 26), 3)
        let today = calendar.startOfDay(for: now())
        for (i, bucket) in buckets.enumerated() {
            let x = area.minX + slot * CGFloat(i) + (slot - barWidth) / 2
            let height = bucket.seconds == 0 ? 0 : max(CGFloat(bucket.seconds) / CGFloat(maxSeconds) * area.height, 3)
            let bar = NSRect(x: x, y: area.maxY - height, width: barWidth, height: height)
            let isNow = kind == .day
                ? calendar.component(.hour, from: bucket.start) == calendar.component(.hour, from: now()) && period.contains(now())
                : calendar.startOfDay(for: bucket.start) == today
            (isNow ? Paper.accent : Paper.accent.withAlphaComponent(0.6)).setFill()
            NSBezierPath(roundedRect: bar, xRadius: min(3, barWidth / 2), yRadius: min(3, barWidth / 2)).fill()
            if kind == .week, bucket.seconds > 0 {
                text("\((bucket.seconds + 30) / 60)", at: NSRect(x: x - 8, y: bar.minY - 15, width: barWidth + 16, height: 14),
                     font: NSFont.systemFont(ofSize: 10.5), color: Paper.inkLight, alignment: .center)
            }
        }
        // Linea di base e nomi
        Paper.paperEdge.setStroke()
        let base = NSBezierPath()
        base.move(to: NSPoint(x: area.minX, y: area.maxY + 0.5))
        base.line(to: NSPoint(x: area.maxX, y: area.maxY + 0.5))
        base.lineWidth = 1
        base.stroke()
        for (i, bucket) in buckets.enumerated() {
            let label: String?
            switch kind {
            case .day:
                let hour = calendar.component(.hour, from: bucket.start)
                label = hour % 6 == 0 ? "\(hour)" : nil
            case .week:
                label = formatted(bucket.start, "EEE")
            case .month:
                let day = calendar.component(.day, from: bucket.start)
                label = (day == 1 || day % 5 == 0) ? "\(day)" : nil
            }
            guard let label else { continue }
            let x = area.minX + slot * CGFloat(i)
            text(label, at: NSRect(x: x - 6, y: area.maxY + 4, width: slot + 12, height: 14),
                 font: NSFont.systemFont(ofSize: 10.5), color: Paper.inkLight, alignment: .center)
        }
    }

    /// Una barra per materia, con il tempo e la percentuale.
    private func drawSubjects(top: CGFloat) {
        let width = Self.size.width
        let m = Self.margin
        sectionTitle("PER MATERIA", y: top)
        guard !summary.bySubject.isEmpty else { return }

        var rows = Array(summary.bySubject.prefix(4))
        if summary.bySubject.count > 4 {
            let rest = summary.bySubject.dropFirst(4)
            rows.append((subject: "Altre (\(rest.count))", seconds: rest.reduce(0) { $0 + $1.seconds }))
        }
        let total = max(summary.totalSeconds, 1)
        let maxSeconds = max(rows.map { $0.seconds }.max() ?? 1, 1)
        let barLeft = m + 150
        let barRight = width - m - 120
        for (i, row) in rows.enumerated() {
            let y = top + 24 + CGFloat(i) * 25
            text(row.subject, at: NSRect(x: m, y: y, width: 140, height: 18), font: NSFont.systemFont(ofSize: 13))
            let track = NSRect(x: barLeft, y: y + 3, width: barRight - barLeft, height: 12)
            Paper.track.setFill()
            NSBezierPath(roundedRect: track, xRadius: 6, yRadius: 6).fill()
            let fillWidth = max(track.width * CGFloat(row.seconds) / CGFloat(maxSeconds), 6)
            let color = row.subject == Subject.none || row.subject.hasPrefix("Altre (") ? Paper.inkLight.withAlphaComponent(0.55) : Paper.color(forSubject: row.subject)
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: fillWidth, height: track.height), xRadius: 6, yRadius: 6).fill()
            let percent = Int((Double(row.seconds) * 100 / Double(total)).rounded())
            text("\(StudyStats.duration(seconds: row.seconds)) · \(percent)%",
                 at: NSRect(x: barRight + 10, y: y, width: 110, height: 18),
                 font: NSFont.systemFont(ofSize: 12), color: Paper.inkLight)
        }
    }

    /// Le ultime sessioni: toccandone una si cambia la materia o la si toglie.
    private func drawSessions(top: CGFloat) {
        let width = Self.size.width
        let m = Self.margin
        sectionTitle("SESSIONI", y: top)
        guard !summary.sessions.isEmpty else { return }
        let shown = summary.sessions.prefix(4)
        for (i, session) in shown.enumerated() {
            let y = top + 24 + CGFloat(i) * 23
            let rect = NSRect(x: m - 6, y: y - 2, width: width - 2 * m + 12, height: 22)
            rowHits.append((rect: rect, id: session.id))
            let when = kind == .day ? formatted(session.startTime(in: calendar), "HH:mm") : formatted(session.startTime(in: calendar), "EEE d MMM, HH:mm")
            let subject = session.subject ?? Subject.none
            let dot = NSBezierPath(ovalIn: NSRect(x: m, y: y + 5, width: 9, height: 9))
            (session.subject == nil ? Paper.inkLight.withAlphaComponent(0.5) : Paper.color(forSubject: subject)).setFill()
            dot.fill()
            text(when, at: NSRect(x: m + 18, y: y, width: 130, height: 18), font: NSFont.systemFont(ofSize: 13), color: Paper.inkLight)
            text(subject, at: NSRect(x: m + 150, y: y, width: 250, height: 18), font: NSFont.systemFont(ofSize: 13))
            let minutes = (session.seconds + 30) / 60
            let status = session.completed ? "\(minutes) min" : "\(minutes) min · interrotto"
            text(status, at: NSRect(x: width - m - 150, y: y, width: 150, height: 18),
                 font: NSFont.systemFont(ofSize: 12), color: session.completed ? Paper.inkLight : Paper.accent, alignment: .right)
        }
        if summary.sessions.count > shown.count {
            let extra = summary.sessions.count - shown.count
            text(extra == 1 ? "… e un'altra sessione" : "… e altre \(extra) sessioni", at: NSRect(x: m, y: top + 24 + CGFloat(shown.count) * 23, width: 300, height: 16),
                 font: NSFont.systemFont(ofSize: 12), color: Paper.inkLight)
        }
    }

    // MARK: - Mouse

    override func resetCursorRects() {
        for hit in rowHits { addCursorRect(hit.rect, cursor: .pointingHand) }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = rowHits.first(where: { $0.rect.contains(point) }),
              let session = log.sessions.first(where: { $0.id == hit.id }) else { return }
        edit(session)
    }

    private func edit(_ session: StudySession) {
        let alert = NSAlert()
        alert.messageText = "Modifica sessione"
        let minutes = (session.seconds + 30) / 60
        alert.informativeText = "\(formatted(session.startTime(in: calendar), "EEEE d MMMM, HH:mm")) · \(minutes) min"

        let field = NSTextField(frame: NSRect(x: 0, y: 30, width: 280, height: 24))
        field.stringValue = session.subject ?? ""
        field.placeholderString = "Materia"
        // Per correggere una materia scritta male (o unirne due) in tutte le sessioni in un colpo solo.
        let everywhere = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        everywhere.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
        if let subject = session.subject {
            everywhere.title = "Cambia la materia in tutte le sessioni «\(subject)»"
        } else {
            everywhere.isHidden = true
        }
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 58))
        container.addSubview(field)
        container.addSubview(everywhere)
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
    }

    // MARK: - Esportazione

    @objc private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "focusfriends-sessioni.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? Self.csv(for: log.sessions).write(to: url, atomically: true, encoding: .utf8)
    }

    static func csv(for sessions: [StudySession]) -> String {
        func quoted(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let iso = ISO8601DateFormatter()
        var lines = ["inizio,inizio_locale,minuti,minuti_previsti,completa,materia,personaggio"]
        for s in sessions {
            lines.append([
                iso.string(from: s.start), s.localStart ?? "", "\((s.seconds + 30) / 60)", "\(s.plannedMinutes)",
                s.completed ? "si" : "no", quoted(s.subject ?? ""), s.pet ?? "",
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Tiene la finestra delle statistiche: la crea alla prima richiesta e poi la riporta davanti.
final class DashboardController {
    private var window: NSWindow?
    private var view: DashboardView?

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
