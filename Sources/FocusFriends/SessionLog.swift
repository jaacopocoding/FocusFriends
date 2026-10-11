import Foundation

// Il registro delle sessioni di studio e le statistiche che se ne ricavano.
// Solo Foundation: così si può collaudare da solo (vedi tests/main.swift).

/// Un focus: quando è iniziato, quanto è durato davvero e su quale materia.
struct StudySession: Codable, Equatable {
    var id: UUID
    var start: Date
    /// Secondi di focus davvero svolti (per un focus interrotto sono meno di quelli previsti).
    var seconds: Int
    var plannedMinutes: Int
    var completed: Bool
    var subject: String?
    /// Con quale personaggio è stato fatto ("pianty", "porcellino", "ciccio"). Vuoto per le sessioni
    /// registrate prima che esistesse questo campo.
    var pet: String?

    init(id: UUID = UUID(), start: Date, seconds: Int, plannedMinutes: Int, completed: Bool, subject: String?, pet: String? = nil) {
        self.id = id
        self.start = start
        self.seconds = seconds
        self.plannedMinutes = plannedMinutes
        self.completed = completed
        self.subject = subject
        self.pet = pet
    }
}

/// Le regole del giardino: ogni focus è una piantina, e cresce con la parte di focus che hai fatto.
/// Sono le stesse regole della crescita dal vivo durante il timer (un quinto del focus per stadio):
/// quello che vedi crescere è esattamente quello che trovi nel giardino.
enum GardenRules {
    static let stageCount = 5

    /// Quanta parte del focus previsto è stata fatta (0...1). Un focus finito vale sempre 1.
    static func progress(of session: StudySession) -> Double {
        if session.completed { return 1 }
        let planned = Double(max(session.plannedMinutes, 1) * 60)
        return min(max(Double(session.seconds) / planned, 0), 1)
    }

    /// Lo stadio (1...5) della piantina: da 0 a 20% è il seme, da 80% in su la pianta adulta.
    static func stage(for session: StudySession) -> Int {
        min(Int(progress(of: session) * Double(stageCount)) + 1, stageCount)
    }
}

enum Subject {
    /// Come si chiama, nelle statistiche, chi non ha scritto la materia.
    static let none = "Senza materia"
    static let maxLength = 40

    /// Toglie gli spazi in eccesso; vuota = nessuna materia.
    static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let joined = words.joined(separator: " ")
        guard !joined.isEmpty else { return nil }
        return String(joined.prefix(maxLength))
    }
}

/// Il file con tutte le sessioni, più un piccolo file "in corso" per non perdere un focus se l'app si chiude di colpo.
final class SessionLog {
    /// Un focus interrotto sotto il minuto non conta.
    static let minimumSeconds = 60

    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FocusFriends")
    }

    static let shared = SessionLog(directory: SessionLog.defaultDirectory)

    private(set) var sessions: [StudySession] = []
    private let file: URL
    private let progressFile: URL
    private var lastHeartbeat = Date.distantPast
    /// Chi vuole sapere quando il registro cambia (le finestre delle statistiche e del giardino).
    private var observers: [() -> Void] = []

    func addObserver(_ observer: @escaping () -> Void) {
        observers.append(observer)
    }

    init(directory: URL) {
        file = directory.appendingPathComponent("sessioni.json")
        progressFile = directory.appendingPathComponent("in-corso.json")
        load()
    }

    // MARK: - Lettura e scrittura

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func load() {
        guard let data = try? Data(contentsOf: file) else { return }
        do {
            sessions = try Self.decoder().decode([StudySession].self, from: data)
        } catch {
            // File rovinato: lo metto da parte invece di perderlo, e si riparte da vuoto.
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = file.deletingLastPathComponent().appendingPathComponent("sessioni.corrotto-\(stamp).json")
            try? FileManager.default.moveItem(at: file, to: aside)
            sessions = []
        }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? Self.encoder().encode(sessions) {
            try? data.write(to: file, options: .atomic)
        }
        observers.forEach { $0() }
    }

    // MARK: - Modifiche

    /// Aggiunge una sessione (se dura almeno un minuto) e ritorna quella salvata.
    @discardableResult
    func add(start: Date, seconds: Int, plannedMinutes: Int, completed: Bool, subject: String?, pet: String? = nil) -> StudySession? {
        guard seconds >= Self.minimumSeconds else { return nil }
        let session = StudySession(
            start: start, seconds: seconds, plannedMinutes: plannedMinutes,
            completed: completed, subject: Subject.clean(subject), pet: pet
        )
        sessions.append(session)
        sessions.sort { $0.start < $1.start }
        save()
        return session
    }

    func remove(id: UUID) {
        sessions.removeAll { $0.id == id }
        save()
    }

    func setSubject(id: UUID, subject: String?) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].subject = Subject.clean(subject)
        save()
    }

    /// Le materie usate, dalla più recente: per i suggerimenti quando si avvia un focus.
    func recentSubjects(limit: Int = 6) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for session in sessions.reversed() {
            guard let subject = session.subject, !seen.contains(subject.lowercased()) else { continue }
            seen.insert(subject.lowercased())
            result.append(subject)
            if result.count == limit { break }
        }
        return result
    }

    // MARK: - Focus in corso

    private struct InProgress: Codable {
        var start: Date
        var plannedMinutes: Int
        var subject: String?
        var pet: String?
        var lastSeen: Date
    }

    func beginInProgress(start: Date, plannedMinutes: Int, subject: String?, pet: String? = nil) {
        writeProgress(InProgress(start: start, plannedMinutes: plannedMinutes, subject: subject, pet: pet, lastSeen: Date()))
    }

    /// Segna che l'app è ancora viva (al massimo una volta ogni 30 secondi).
    func heartbeat(now: Date = Date()) {
        guard now.timeIntervalSince(lastHeartbeat) >= 30, var progress = readProgress() else { return }
        lastHeartbeat = now
        progress.lastSeen = now
        writeProgress(progress)
    }

    func finishInProgress() {
        try? FileManager.default.removeItem(at: progressFile)
        lastHeartbeat = .distantPast
    }

    /// All'avvio: se l'app si era chiusa di colpo durante un focus, lo salva come interrotto.
    @discardableResult
    func recoverInterrupted() -> StudySession? {
        guard let progress = readProgress() else { return nil }
        finishInProgress()
        let seconds = Int(progress.lastSeen.timeIntervalSince(progress.start))
        let capped = min(seconds, progress.plannedMinutes * 60)
        return add(start: progress.start, seconds: capped, plannedMinutes: progress.plannedMinutes,
                   completed: false, subject: progress.subject, pet: progress.pet)
    }

    private func readProgress() -> InProgress? {
        guard let data = try? Data(contentsOf: progressFile) else { return nil }
        return try? Self.decoder().decode(InProgress.self, from: data)
    }

    private func writeProgress(_ progress: InProgress) {
        try? FileManager.default.createDirectory(at: progressFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? Self.encoder().encode(progress) {
            try? data.write(to: progressFile, options: .atomic)
        }
    }
}

// MARK: - Statistiche

enum PeriodKind: Int {
    case day, week, month
}

/// Un giorno, una settimana (da lunedì) o un mese, con inizio incluso e fine esclusa.
struct StudyPeriod: Equatable {
    var kind: PeriodKind
    var start: Date
    var end: Date

    static func calendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2            // la settimana parte dal lunedì
        c.minimumDaysInFirstWeek = 4
        c.locale = Locale(identifier: "it_IT")
        return c
    }

    static func containing(_ date: Date, kind: PeriodKind, calendar: Calendar = StudyPeriod.calendar()) -> StudyPeriod {
        let component: Calendar.Component
        switch kind {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        }
        let interval = calendar.dateInterval(of: component, for: date) ?? DateInterval(start: date, duration: 86_400)
        return StudyPeriod(kind: kind, start: interval.start, end: interval.end)
    }

    /// Il periodo `count` posti più avanti (o indietro, se negativo).
    func shifted(by count: Int, calendar: Calendar = StudyPeriod.calendar()) -> StudyPeriod {
        let component: Calendar.Component
        switch kind {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        }
        let moved = calendar.date(byAdding: component, value: count, to: start) ?? start
        return StudyPeriod.containing(moved, kind: kind, calendar: calendar)
    }

    func contains(_ date: Date) -> Bool { date >= start && date < end }
}

struct StudyBucket: Equatable {
    var start: Date
    var seconds: Int
}

struct StudySummary {
    var totalSeconds = 0
    var focusCount = 0
    var completedCount = 0
    var interruptedCount = 0
    /// Per materia, dal più studiato.
    var bySubject: [(subject: String, seconds: Int)] = []
    /// Per ora (se il periodo è un giorno) o per giorno (settimana e mese).
    var buckets: [StudyBucket] = []
    /// Le sessioni del periodo, dalla più recente.
    var sessions: [StudySession] = []
}

enum StudyStats {
    static func summary(sessions: [StudySession], period: StudyPeriod, calendar: Calendar = StudyPeriod.calendar()) -> StudySummary {
        // Una sessione va al periodo in cui è iniziata (anche se passa la mezzanotte).
        let inPeriod = sessions.filter { period.contains($0.start) }
        var summary = StudySummary()
        summary.sessions = inPeriod.sorted { $0.start > $1.start }
        summary.focusCount = inPeriod.count
        summary.completedCount = inPeriod.filter { $0.completed }.count
        summary.interruptedCount = summary.focusCount - summary.completedCount
        summary.totalSeconds = inPeriod.reduce(0) { $0 + $1.seconds }

        var bySubject: [String: Int] = [:]
        var order: [String] = []
        for s in inPeriod {
            let name = s.subject ?? Subject.none
            if bySubject[name] == nil { order.append(name) }
            bySubject[name, default: 0] += s.seconds
        }
        summary.bySubject = order
            .map { (subject: $0, seconds: bySubject[$0] ?? 0) }
            .sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.subject < $1.subject }

        let step: Calendar.Component = period.kind == .day ? .hour : .day
        var cursor = period.start
        var buckets: [StudyBucket] = []
        while cursor < period.end {
            let next = calendar.date(byAdding: step, value: 1, to: cursor) ?? period.end
            let seconds = inPeriod.filter { $0.start >= cursor && $0.start < next }.reduce(0) { $0 + $1.seconds }
            buckets.append(StudyBucket(start: cursor, seconds: seconds))
            cursor = next
        }
        summary.buckets = buckets
        return summary
    }

    /// Giorni consecutivi con almeno un focus, fino a oggi. Se oggi non c'è ancora niente conta da ieri,
    /// così la serie non si azzera la mattina.
    static func streak(sessions: [StudySession], now: Date, calendar: Calendar = StudyPeriod.calendar()) -> Int {
        let days = Set(sessions.map { calendar.startOfDay(for: $0.start) })
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    // MARK: - Testi

    /// "3 h 20", "45 min", "2 h", "0 min".
    static func duration(seconds: Int) -> String {
        let minutes = (seconds + 30) / 60
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(String(format: "%02d", m))"
    }

    /// La riga del riepilogo: "Oggi hai fatto 5 focus: 3 h 20 di studio."
    static func dayLine(_ summary: StudySummary, isToday: Bool, dayName: String) -> String {
        let when = isToday ? "Oggi" : dayName
        guard summary.focusCount > 0 else {
            return isToday ? "Oggi non hai ancora fatto nessun focus." : "\(when) non hai fatto nessun focus."
        }
        let focus = summary.focusCount == 1 ? "1 focus" : "\(summary.focusCount) focus"
        return "\(when) hai fatto \(focus): \(duration(seconds: summary.totalSeconds)) di studio."
    }

    /// Una parola gentile in base a quanto si è studiato nel giorno.
    static func encouragement(totalSeconds: Int) -> String {
        switch totalSeconds / 60 {
        case 0: return "Quando vuoi, io sono qui."
        case 1..<45: return "Un bell'inizio: ogni minuto conta."
        case 45..<120: return "Che bel lavoro! Ora una pausa te la sei meritata."
        case 120..<240: return "Una giornata di studio bella piena. Complimenti!"
        default: return "Una giornata di studio davvero lunga: ricordati di riposare."
        }
    }
}
