import Foundation

// Il registro delle sessioni di studio e le statistiche che se ne ricavano.
// Solo Foundation: così si può collaudare da solo (vedi tests/main.swift).

/// Un focus: quando è iniziato, quanto è durato davvero e su quale materia.
struct StudySession: Codable, Equatable {
    var id: UUID
    var start: Date
    /// L'ora "sull'orologio" in cui è iniziato, senza fuso ("2026-10-14T09:30"). Serve a non far cambiare
    /// giorno (o ora) a una sessione se poi cambia il fuso orario o l'ora legale: le statistiche usano questa.
    var localStart: String?
    /// Secondi di focus davvero svolti (per un focus interrotto sono meno di quelli previsti).
    var seconds: Int
    var plannedMinutes: Int
    var completed: Bool
    var subject: String?
    /// Con quale personaggio è stato fatto ("pianty", "porcellino", "ciccio"). Vuoto per le sessioni
    /// registrate prima che esistesse questo campo.
    var pet: String?

    init(id: UUID = UUID(), start: Date, localStart: String? = nil, seconds: Int, plannedMinutes: Int,
         completed: Bool, subject: String?, pet: String? = nil) {
        self.id = id
        self.start = start
        self.localStart = localStart
        self.seconds = seconds
        self.plannedMinutes = plannedMinutes
        self.completed = completed
        self.subject = subject
        self.pet = pet
    }

    /// L'istante in cui è iniziata, letto "sull'orologio" nel fuso del calendario dato: se la sessione ha
    /// l'ora locale registrata vale quella, altrimenti l'istante assoluto.
    func startTime(in calendar: Calendar) -> Date {
        guard let local = localStart, let wall = Self.parse(local, calendar: calendar) else { return start }
        return wall
    }

    /// "2026-10-14T09:30" per l'istante dato, nel fuso del calendario.
    static func localString(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    private static func parse(_ text: String, calendar: Calendar) -> Date? {
        // Formato fisso: aaaa-mm-ggThh:mm (16 caratteri)
        let chars = Array(text)
        guard chars.count == 16, chars[4] == "-", chars[7] == "-", chars[10] == "T", chars[13] == ":",
              let y = Int(String(chars[0..<4])), let mo = Int(String(chars[5..<7])), let d = Int(String(chars[8..<10])),
              let h = Int(String(chars[11..<13])), let mi = Int(String(chars[14..<16])) else { return nil }
        return calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))
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

    /// La chiave con cui due scritture sono la stessa materia: senza maiuscole e senza accenti
    /// ("Anatomia", "anatomia" e "ANATOMIA" sono la stessa; "Fisica" e "Física" pure).
    static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT"))
    }
}

/// Il file di dati: la versione del formato e le sessioni. (Prima della versione 1 il file era la sola lista.)
private struct LogFile: Codable {
    var version: Int
    var sessions: [StudySession]
}

/// Il file con tutte le sessioni, più un piccolo file "in corso" per non perdere un focus se l'app si chiude di colpo.
///
/// Cartella dei dati:
///   sessioni.json        { "version": 1, "sessions": [...] }
///   in-corso.json        il focus in corso (sparisce quando finisce)
///   backup/              una copia al giorno (le ultime 7), fatta prima della prima modifica della giornata
final class SessionLog {
    /// La versione del formato di `sessioni.json` che questa app scrive.
    static let formatVersion = 1
    /// Un focus interrotto sotto il minuto non conta.
    static let minimumSeconds = 60
    /// Quante copie di sicurezza tenere.
    static let backupsToKeep = 7

    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FocusFriends")
    }

    static let shared = SessionLog(directory: SessionLog.defaultDirectory)

    private(set) var sessions: [StudySession] = []
    /// Il file è di una versione più nuova di quella che conosco: lo leggo ma non lo riscrivo (non perdo niente).
    private(set) var isReadOnly = false
    private let directory: URL
    private let file: URL
    private let progressFile: URL
    private let backupDirectory: URL
    private let now: () -> Date
    private let timeZone: TimeZone
    private var lastHeartbeat = Date.distantPast
    /// Chi vuole sapere quando il registro cambia (le finestre delle statistiche e del giardino).
    private var observers: [() -> Void] = []

    func addObserver(_ observer: @escaping () -> Void) {
        observers.append(observer)
    }

    init(directory: URL, now: @escaping () -> Date = Date.init, timeZone: TimeZone = .current) {
        self.directory = directory
        self.now = now
        self.timeZone = timeZone
        file = directory.appendingPathComponent("sessioni.json")
        progressFile = directory.appendingPathComponent("in-corso.json")
        backupDirectory = directory.appendingPathComponent("backup")
        load()
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
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
        let decoder = Self.decoder()
        var needsSave = false

        if let wrapped = try? decoder.decode(LogFile.self, from: data) {
            sessions = wrapped.sessions
            if wrapped.version > Self.formatVersion { isReadOnly = true }
        } else if let legacy = try? decoder.decode([StudySession].self, from: data) {
            // Formato precedente (la sola lista): tengo una copia intatta e passo al nuovo.
            try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            try? data.write(to: backupDirectory.appendingPathComponent("sessioni-formato0.json"), options: .atomic)
            sessions = legacy
            needsSave = true
        } else {
            // File rovinato: lo metto da parte invece di perderlo, e si riparte da vuoto.
            let stamp = Int(now().timeIntervalSince1970)
            let aside = directory.appendingPathComponent("sessioni.corrotto-\(stamp).json")
            try? FileManager.default.moveItem(at: file, to: aside)
            sessions = []
            return
        }

        if normalize() { needsSave = true }
        if needsSave && !isReadOnly { save() }
    }

    /// Mette in ordine i dati letti: ogni materia con la scrittura più recente (e non una per ogni maiuscola),
    /// e l'ora locale dove manca. Ritorna true se ha cambiato qualcosa.
    private func normalize() -> Bool {
        var changed = false
        var spelling: [String: String] = [:]
        for session in sessions.sorted(by: { $0.start < $1.start }) {
            if let subject = session.subject { spelling[Subject.key(subject)] = subject }   // l'ultima vince
        }
        for i in sessions.indices {
            if let subject = sessions[i].subject, let canonical = spelling[Subject.key(subject)], canonical != subject {
                sessions[i].subject = canonical
                changed = true
            }
            if sessions[i].localStart == nil {
                sessions[i].localStart = StudySession.localString(for: sessions[i].start, calendar: calendar)
                changed = true
            }
        }
        return changed
    }

    private func save() {
        guard !isReadOnly else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        makeDailyBackupIfNeeded()
        let wrapped = LogFile(version: Self.formatVersion, sessions: sessions)
        if let data = try? Self.encoder().encode(wrapped) {
            try? data.write(to: file, options: .atomic)
        }
        observers.forEach { $0() }
    }

    // MARK: - Copie di sicurezza

    /// Prima della prima modifica della giornata copia il file così com'era (cioè com'è finito ieri) e tiene
    /// solo le ultime `backupsToKeep`.
    private func makeDailyBackupIfNeeded() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: file.path) else { return }
        let c = calendar.dateComponents([.year, .month, .day], from: now())
        let name = String(format: "sessioni-%04d-%02d-%02d.json", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        let target = backupDirectory.appendingPathComponent(name)
        guard !fm.fileExists(atPath: target.path) else { return }
        try? fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        try? fm.copyItem(at: file, to: target)

        let daily = ((try? fm.contentsOfDirectory(atPath: backupDirectory.path)) ?? [])
            .filter { $0.hasPrefix("sessioni-2") && $0.hasSuffix(".json") }
            .sorted()
        if daily.count > Self.backupsToKeep {
            for old in daily.prefix(daily.count - Self.backupsToKeep) {
                try? fm.removeItem(at: backupDirectory.appendingPathComponent(old))
            }
        }
    }

    // MARK: - Modifiche

    /// La scrittura di una materia da usare: se esiste già con maiuscole o accenti diversi, vale quella più recente.
    private func canonicalSubject(_ cleaned: String?) -> String? {
        guard let cleaned else { return nil }
        let key = Subject.key(cleaned)
        for session in sessions.reversed() {                    // dalla più recente
            if let existing = session.subject, Subject.key(existing) == key { return existing }
        }
        return cleaned
    }

    /// Aggiunge una sessione (se dura almeno un minuto) e ritorna quella salvata.
    @discardableResult
    func add(start: Date, seconds: Int, plannedMinutes: Int, completed: Bool, subject: String?, pet: String? = nil) -> StudySession? {
        guard seconds >= Self.minimumSeconds, !isReadOnly else { return nil }
        let session = StudySession(
            start: start, localStart: StudySession.localString(for: start, calendar: calendar),
            seconds: seconds, plannedMinutes: plannedMinutes, completed: completed,
            subject: canonicalSubject(Subject.clean(subject)), pet: pet
        )
        sessions.append(session)
        sessions.sort { $0.start < $1.start }
        save()
        return session
    }

    func remove(id: UUID) {
        guard !isReadOnly else { return }
        sessions.removeAll { $0.id == id }
        save()
    }

    func setSubject(id: UUID, subject: String?) {
        guard !isReadOnly, let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].subject = canonicalSubject(Subject.clean(subject))
        save()
    }

    /// Rinomina una materia in tutte le sessioni (anche quelle scritte con maiuscole diverse). Se esiste già
    /// una materia con il nuovo nome, le due si uniscono. Ritorna quante sessioni sono cambiate.
    @discardableResult
    func renameSubject(from old: String, to new: String?) -> Int {
        guard !isReadOnly else { return 0 }
        let oldKey = Subject.key(old)
        let target = canonicalSubject(Subject.clean(new))
        var changed = 0
        for i in sessions.indices {
            guard let subject = sessions[i].subject, Subject.key(subject) == oldKey, subject != target else { continue }
            sessions[i].subject = target
            changed += 1
        }
        if changed > 0 { save() }
        return changed
    }

    /// Cancella tutto: le sessioni, il focus in corso e le copie di sicurezza. Non si può annullare.
    func deleteAll() {
        let fm = FileManager.default
        sessions = []
        isReadOnly = false
        try? fm.removeItem(at: file)
        try? fm.removeItem(at: progressFile)
        try? fm.removeItem(at: backupDirectory)
        lastHeartbeat = .distantPast
        observers.forEach { $0() }
    }

    /// Le materie usate, dalla più recente: per i suggerimenti quando si avvia un focus.
    func recentSubjects(limit: Int = 6) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for session in sessions.reversed() {
            guard let subject = session.subject, !seen.contains(Subject.key(subject)) else { continue }
            seen.insert(Subject.key(subject))
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
        writeProgress(InProgress(start: start, plannedMinutes: plannedMinutes, subject: subject, pet: pet, lastSeen: now()))
    }

    /// Segna che l'app è ancora viva (al massimo una volta ogni 30 secondi).
    func heartbeat(now current: Date? = nil) {
        let moment = current ?? now()
        guard moment.timeIntervalSince(lastHeartbeat) >= 30, var progress = readProgress() else { return }
        lastHeartbeat = moment
        progress.lastSeen = moment
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
        // Una sessione va al periodo in cui è iniziata (anche se passa la mezzanotte), secondo l'ora
        // "sull'orologio" a cui l'ha registrata (non cambia se poi cambia il fuso orario).
        let inPeriod = sessions.filter { period.contains($0.startTime(in: calendar)) }
        var summary = StudySummary()
        summary.sessions = inPeriod.sorted { $0.startTime(in: calendar) > $1.startTime(in: calendar) }
        summary.focusCount = inPeriod.count
        summary.completedCount = inPeriod.filter { $0.completed }.count
        summary.interruptedCount = summary.focusCount - summary.completedCount
        summary.totalSeconds = inPeriod.reduce(0) { $0 + $1.seconds }

        // Le materie si raggruppano senza distinguere maiuscole e accenti; si mostra la scrittura più recente.
        var secondsByKey: [String: Int] = [:]
        var displayByKey: [String: String] = [:]
        var order: [String] = []
        for s in inPeriod.sorted(by: { $0.startTime(in: calendar) < $1.startTime(in: calendar) }) {
            let name = s.subject ?? Subject.none
            let key = s.subject.map { Subject.key($0) } ?? "\u{0}senza-materia"
            if secondsByKey[key] == nil { order.append(key) }
            secondsByKey[key, default: 0] += s.seconds
            displayByKey[key] = name
        }
        summary.bySubject = order
            .map { (subject: displayByKey[$0] ?? Subject.none, seconds: secondsByKey[$0] ?? 0) }
            .sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.subject < $1.subject }

        let step: Calendar.Component = period.kind == .day ? .hour : .day
        var cursor = period.start
        var buckets: [StudyBucket] = []
        while cursor < period.end {
            let next = calendar.date(byAdding: step, value: 1, to: cursor) ?? period.end
            let seconds = inPeriod.filter {
                let t = $0.startTime(in: calendar)
                return t >= cursor && t < next
            }.reduce(0) { $0 + $1.seconds }
            buckets.append(StudyBucket(start: cursor, seconds: seconds))
            cursor = next
        }
        summary.buckets = buckets
        return summary
    }

    /// Giorni consecutivi con almeno un focus, fino a oggi. Se oggi non c'è ancora niente conta da ieri,
    /// così la serie non si azzera la mattina.
    static func streak(sessions: [StudySession], now: Date, calendar: Calendar = StudyPeriod.calendar()) -> Int {
        let days = Set(sessions.map { calendar.startOfDay(for: $0.startTime(in: calendar)) })
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
