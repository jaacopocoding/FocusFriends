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
    /// "Com'è andata?" a fine focus. Facoltativo (formato 2).
    var rating: FocusRating?
    /// Cosa hai fatto ("cap. 4, nervi cranici"). Facoltativa (formato 2).
    var note: String?
    /// Le note scritte durante il focus, una per riga (formato 3).
    var notes: [String]?

    init(id: UUID = UUID(), start: Date, localStart: String? = nil, seconds: Int, plannedMinutes: Int,
         completed: Bool, subject: String?, pet: String? = nil, rating: FocusRating? = nil, note: String? = nil,
         notes: [String]? = nil) {
        self.id = id
        self.start = start
        self.localStart = localStart
        self.seconds = seconds
        self.plannedMinutes = plannedMinutes
        self.completed = completed
        self.subject = subject
        self.pet = pet
        self.rating = rating
        self.note = note
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id, start, localStart, seconds, plannedMinutes, completed, subject, pet, rating, note, notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        start = try c.decode(Date.self, forKey: .start)
        localStart = try c.decodeIfPresent(String.self, forKey: .localStart)
        seconds = try c.decode(Int.self, forKey: .seconds)
        plannedMinutes = try c.decode(Int.self, forKey: .plannedMinutes)
        completed = try c.decode(Bool.self, forKey: .completed)
        subject = try c.decodeIfPresent(String.self, forKey: .subject)
        pet = try c.decodeIfPresent(String.self, forKey: .pet)
        // Un voto che non conosco (scritto da una versione futura) non deve rendere illeggibile il file.
        rating = try? c.decodeIfPresent(FocusRating.self, forKey: .rating)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        notes = try c.decodeIfPresent([String].self, forKey: .notes)
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

/// Le regole del giardino: si conta il tempo di studio della giornata. Ogni 50 minuti è una pianta adulta; quello
/// che avanza cresce in una piantina allo stadio di mezzo (da 1 a 4: l'adulta, la 5, è solo a 50 minuti pieni).
/// Contano tutti i minuti studiati, anche di un focus interrotto.
enum GardenRules {
    static let stageCount = 5
    static let minutesPerPlant = 50
    static let secondsPerPlant = minutesPerPlant * 60
    /// Sotto questo resto (in secondi) non nasce ancora niente: serve almeno un minuto.
    static let minimumRemainder = 60

    /// Quanto di una materia c'è in una piantina.
    struct SubjectShare: Equatable {
        var subject: String?
        var seconds: Int
    }

    /// Una piantina del giardino di un giorno.
    struct DayPlant: Equatable {
        /// 1...5; 5 solo per i 50 minuti pieni.
        var stage: Int
        /// I secondi di studio che la fanno crescere (3000 se è adulta).
        var seconds: Int
        /// Le materie che l'hanno fatta crescere, dalla più presente.
        var subjects: [SubjectShare]
        /// Il personaggio con cui è stata fatta di più (sceglie il disegno della piantina).
        var pet: String?

        var isAdult: Bool { stage == GardenRules.stageCount }
        /// La materia prevalente (il pallino sotto il vaso).
        var subject: String? { subjects.first?.subject }
    }

    /// Lo stadio (1...4) di una piantina che ha `seconds` secondi di crescita (meno di 50 minuti).
    static func intermediateStage(forSeconds seconds: Int) -> Int {
        let fraction = Double(max(seconds, 0)) / Double(secondsPerPlant)
        return min(max(Int(fraction * Double(stageCount)) + 1, 1), stageCount - 1)
    }

    /// Le piantine di una giornata: il tempo di studio, in ordine di inizio, riempie una pianta dopo l'altra.
    /// Prima le adulte (una ogni 50 minuti), poi, se avanza almeno un minuto, quella che sta crescendo.
    static func plants(of sessions: [StudySession], calendar: Calendar = StudyPeriod.calendar()) -> [DayPlant] {
        let ordered = sessions.sorted { $0.startTime(in: calendar) < $1.startTime(in: calendar) }
        var subjectSeconds: [[String: Int]] = [[:]]
        var petSeconds: [[String: Int]] = [[:]]
        var subjectName: [String: String] = [:]          // chiave -> scrittura (vuota = nessuna materia)
        var position = 0
        for session in ordered {
            let key = session.subject.map { Subject.key($0) } ?? ""
            subjectName[key] = session.subject ?? ""
            var left = session.seconds
            while left > 0 {
                let chunk = position / secondsPerPlant
                while subjectSeconds.count <= chunk {
                    subjectSeconds.append([:])
                    petSeconds.append([:])
                }
                let take = min(left, secondsPerPlant - position % secondsPerPlant)
                subjectSeconds[chunk][key, default: 0] += take
                petSeconds[chunk][session.pet ?? "pianty", default: 0] += take
                position += take
                left -= take
            }
        }

        func make(_ chunk: Int, stage: Int, seconds: Int) -> DayPlant {
            let shares = (subjectSeconds[chunk].sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key })
                .map { entry -> SubjectShare in
                    let name = subjectName[entry.key] ?? ""
                    return SubjectShare(subject: name.isEmpty ? nil : name, seconds: entry.value)
                }
            let pet = petSeconds[chunk].sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.first?.key
            return DayPlant(stage: stage, seconds: seconds, subjects: shares, pet: pet)
        }

        let full = position / secondsPerPlant
        let rest = position % secondsPerPlant
        var result = (0..<full).map { make($0, stage: stageCount, seconds: secondsPerPlant) }
        if rest >= minimumRemainder {
            result.append(make(full, stage: intermediateStage(forSeconds: rest), seconds: rest))
        }
        return result
    }

    /// Una frase per la fine del focus: è nata una pianta adulta, oppure quella di oggi è cresciuta.
    /// `before` e `after` sono i secondi di studio della giornata prima e dopo il focus.
    static func finishLine(before: Int, after: Int) -> String {
        if after / secondsPerPlant > before / secondsPerPlant {
            return "Nel giardino è nata una pianta adulta."
        }
        let left = max(minutesPerPlant - (after % secondsPerPlant + 59) / 60, 1)
        return "La piantina di oggi è cresciuta: ancora \(left) minuti per la prossima."
    }
}

/// La stagione di una data (meteorologica, emisfero nord): cambia l'aspetto del prato del giardino.
enum Season: String, CaseIterable {
    case spring, summer, autumn, winter

    static func of(_ date: Date, calendar: Calendar = StudyPeriod.calendar()) -> Season {
        switch calendar.component(.month, from: date) {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .autumn
        default: return .winter
        }
    }

    var title: String {
        switch self {
        case .spring: return "Primavera"
        case .summer: return "Estate"
        case .autumn: return "Autunno"
        case .winter: return "Inverno"
        }
    }
}

/// "Com'è andata?": tre livelli, abbastanza per vedere i modelli senza dover pensare.
enum FocusRating: String, Codable, CaseIterable {
    case good, soso, poor

    var title: String {
        switch self {
        case .good: return "Bene"
        case .soso: return "Così così"
        case .poor: return "Poca testa"
        }
    }
}

/// La riga facoltativa "cosa hai fatto" di un focus.
enum SessionNote {
    static let maxLength = 80

    /// Spazi in eccesso e caratteri di controllo tolti, al massimo `maxLength` caratteri; vuota = nessuna nota.
    static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map { word in
            String(String.UnicodeScalarView(word.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
        }
        let joined = words.filter { !$0.isEmpty }.joined(separator: " ")
        guard !joined.isEmpty else { return nil }
        return String(joined.prefix(maxLength))
    }
}

/// Le note scritte durante un focus: una riga per nota, poche e brevi.
enum FocusNotes {
    static let maxLength = 160
    static let maxCount = 40

    /// Pulisce una nota (spazi, caratteri di controllo, lunghezza); vuota = nessuna.
    static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map { word in
            String(String.UnicodeScalarView(word.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
        }
        let joined = words.filter { !$0.isEmpty }.joined(separator: " ")
        guard !joined.isEmpty else { return nil }
        return String(joined.prefix(maxLength))
    }

    /// Una lista pulita: senza note vuote, al massimo `maxCount`. Vuota = nil (così il campo non c'è nel file).
    static func clean(list: [String]?) -> [String]? {
        guard let list else { return nil }
        let cleaned = list.compactMap { clean($0) }
        return cleaned.isEmpty ? nil : Array(cleaned.prefix(maxCount))
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
///   sessioni.json        { "version": 3, "sessions": [...] }
///   in-corso.json        il focus in corso (sparisce quando finisce)
///   backup/              una copia al giorno (le ultime 7), fatta prima della prima modifica della giornata
final class SessionLog {
    /// La versione del formato di `sessioni.json` che questa app scrive.
    /// 2: le sessioni possono avere `rating` e `note`. 3: e `notes` (le note scritte durante il focus).
    static let formatVersion = 3
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

    /// Chiamata quando qualcosa non va con i dati (un file non si legge, una scrittura fallisce...): il testo è per
    /// chi usa l'app. I problemi che nascono in `init`, prima che qualcuno si registri, arrivano appena ci si registra.
    var onProblem: ((String) -> Void)? {
        didSet {
            guard let handler = onProblem, !pendingProblems.isEmpty else { return }
            let pending = pendingProblems
            pendingProblems = []
            pending.forEach(handler)
        }
    }
    private var pendingProblems: [String] = []
    /// I problemi già segnalati e non ancora risolti: ognuno si segnala una volta sola, finché non passa.
    private var activeProblems: Set<String> = []

    private func report(_ message: String) {
        if let handler = onProblem { handler(message) } else { pendingProblems.append(message) }
    }

    /// Segnala un problema una volta sola, finché non si risolve (`recover`).
    private func fail(_ key: String, _ message: String) {
        if activeProblems.insert(key).inserted { report(message) }
    }

    private func recover(_ key: String) {
        activeProblems.remove(key)
    }

    /// L'ultima scrittura di `sessioni.json` non è riuscita: in memoria c'è più di quello che c'è sul disco.
    /// Ogni modifica successiva riscrive tutto, quindi basta una scrittura riuscita per rimettere a posto.
    private(set) var hasUnsavedChanges = false

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
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        guard let data = try? Data(contentsOf: file) else {
            // C'è ma non si legge: non è come se non ci fosse, perché la prossima scrittura lo sostituirebbe.
            isReadOnly = true
            report("Il file delle sessioni non si legge: non lo modifico. Controlla i permessi della cartella FocusFriends.")
            return
        }
        let decoder = Self.decoder()
        var needsSave = false

        if let wrapped = try? decoder.decode(LogFile.self, from: data) {
            sessions = wrapped.sessions
            if wrapped.version > Self.formatVersion {
                isReadOnly = true
                report("I dati sono di una versione più nuova di questa app: li leggo ma non li modifico, e i nuovi focus non vengono salvati.")
            } else if wrapped.version < Self.formatVersion {
                // Passo a un formato nuovo: tengo intatta la copia di quello vecchio.
                try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
                try? data.write(to: backupDirectory.appendingPathComponent("sessioni-formato\(wrapped.version).json"), options: .atomic)
                needsSave = true
            }
        } else if let legacy = try? decoder.decode([StudySession].self, from: data) {
            // Formato precedente (la sola lista): tengo una copia intatta e passo al nuovo.
            try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            try? data.write(to: backupDirectory.appendingPathComponent("sessioni-formato0.json"), options: .atomic)
            sessions = legacy
            needsSave = true
        } else if let salvaged = Self.salvage(data, decoder: decoder) {
            // Qualche sessione non si legge: tengo le altre, e il file com'era resta come copia.
            sessions = salvaged.sessions
            if salvaged.version > Self.formatVersion {
                isReadOnly = true
                report("I dati sono di una versione più nuova dell'app e alcune sessioni non si leggono: non li modifico.")
            } else if salvaged.dropped == 0 {
                needsSave = true
            } else {
                let name = "sessioni.corrotto-\(Int(now().timeIntervalSince1970)).json"
                if (try? data.write(to: directory.appendingPathComponent(name), options: .atomic)) != nil {
                    needsSave = true
                    report("\(salvaged.dropped) sessioni non erano leggibili: le altre sono a posto, e il file com'era è in \(name).")
                } else {
                    isReadOnly = true
                    report("Alcune sessioni non si leggono e non riesco a tenerne una copia: non modifico il file.")
                }
            }
        } else {
            // File rovinato: lo metto da parte invece di perderlo, e si riparte da vuoto.
            let name = "sessioni.corrotto-\(Int(now().timeIntervalSince1970)).json"
            let aside = directory.appendingPathComponent(name)
            do {
                try FileManager.default.moveItem(at: file, to: aside)
                report("Il file delle sessioni era rovinato: l'ho messo da parte come \(name) e riparto da zero.")
            } catch {
                // Non riesco a spostarlo: non lo sovrascrivo.
                isReadOnly = true
                report("Il file delle sessioni è rovinato e non riesco a metterlo da parte: non lo modifico.")
            }
            sessions = []
            return
        }

        if normalize() { needsSave = true }
        if needsSave && !isReadOnly { save() }
    }

    /// Decodifica una sessione alla volta: ritorna quelle leggibili, la versione del file e quante non lo erano, oppure
    /// nil se il contenuto non è nemmeno un elenco di sessioni.
    private static func salvage(_ data: Data, decoder: JSONDecoder) -> (sessions: [StudySession], version: Int, dropped: Int)? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let version: Int
        let items: [Any]
        if let dictionary = object as? [String: Any], let list = dictionary["sessions"] as? [Any] {
            version = dictionary["version"] as? Int ?? 0
            items = list
        } else if let list = object as? [Any] {
            version = 0
            items = list
        } else {
            return nil
        }
        var readable: [StudySession] = []
        for item in items {
            guard JSONSerialization.isValidJSONObject(item),
                  let bytes = try? JSONSerialization.data(withJSONObject: item),
                  let session = try? decoder.decode(StudySession.self, from: bytes) else { continue }
            readable.append(session)
        }
        return (readable, version, items.count - readable.count)
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
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            makeDailyBackupIfNeeded()
            let wrapped = LogFile(version: Self.formatVersion, sessions: sessions)
            try Self.encoder().encode(wrapped).write(to: file, options: .atomic)
            hasUnsavedChanges = false
            recover("save")
        } catch {
            hasUnsavedChanges = true
            fail("save", "Non riesco a salvare le sessioni sul disco (\(error.localizedDescription)): finché l'app resta aperta le vedi, ma se si chiude le perdo.")
        }
        // Le viste mostrano lo stato in memoria, che è cambiato in ogni caso.
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
        do {
            try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            try fm.copyItem(at: file, to: target)
            recover("backup")
        } catch {
            fail("backup", "Non riesco a fare la copia di sicurezza di oggi delle sessioni.")
            return
        }

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
    func add(start: Date, seconds: Int, plannedMinutes: Int, completed: Bool, subject: String?, pet: String? = nil,
             notes: [String]? = nil) -> StudySession? {
        guard seconds >= Self.minimumSeconds, !isReadOnly else { return nil }
        let session = StudySession(
            start: start, localStart: StudySession.localString(for: start, calendar: calendar),
            seconds: seconds, plannedMinutes: plannedMinutes, completed: completed,
            subject: canonicalSubject(Subject.clean(subject)), pet: pet, notes: FocusNotes.clean(list: notes)
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

    /// "Com'è andata" e "cosa hai fatto" di una sessione (nil = niente).
    func setReflection(id: UUID, rating: FocusRating?, note: String?) {
        guard !isReadOnly, let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].rating = rating
        sessions[index].note = SessionNote.clean(note)
        save()
    }

    /// Le note del focus di una sessione (una per riga; vuote = nessuna).
    func setNotes(id: UUID, notes: [String]?) {
        guard !isReadOnly, let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].notes = FocusNotes.clean(list: notes)
        save()
    }

    /// L'ultima nota scritta, con la sua materia: "L'ultima volta su Anatomia: nervi cranici".
    func lastNote() -> (subject: String?, note: String)? {
        for session in sessions.reversed() {
            if let note = session.note, !note.isEmpty { return (session.subject, note) }
        }
        return nil
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
        var notes: [String]?
        /// I secondi in cui il timer è stato fermo (le pause già finite), da non contare come studio.
        var pausedSeconds: Int?
        /// Da quando è fermo adesso (nil = sta andando).
        var pausedSince: Date?
    }

    func beginInProgress(start: Date, plannedMinutes: Int, subject: String?, pet: String? = nil, notes: [String] = []) {
        var progress = InProgress(start: start, plannedMinutes: plannedMinutes, subject: subject, pet: pet, lastSeen: now(),
                                  notes: notes.isEmpty ? nil : notes)
        // Lo stesso focus che si aggiorna (per esempio con «+5 minuti»): il tempo fermo non si perde.
        // (le date nel file hanno i secondi interi: si confronta con una tolleranza)
        if let old = readProgress(), abs(old.start.timeIntervalSince(start)) < 1 {
            progress.pausedSeconds = old.pausedSeconds
            progress.pausedSince = old.pausedSince
        }
        writeProgress(progress)
    }

    /// Quanto è rimasto fermo il focus in corso: `seconds` di pause già finite e, se è fermo adesso, da quando.
    func updateInProgressPause(seconds: Int, since: Date?) {
        guard var progress = readProgress() else { return }
        progress.pausedSeconds = seconds > 0 ? seconds : nil
        progress.pausedSince = since
        writeProgress(progress)
    }

    /// Le note del focus in corso: si salvano subito, così non si perdono se l'app si chiude di colpo.
    func updateInProgressNotes(_ notes: [String]) {
        guard var progress = readProgress() else { return }
        progress.notes = notes.isEmpty ? nil : notes
        writeProgress(progress)
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
        // Il tempo fermo non è studio: né le pause finite né quella in corso quando l'app si è chiusa.
        var stopped = Double(progress.pausedSeconds ?? 0)
        if let since = progress.pausedSince { stopped += max(0, progress.lastSeen.timeIntervalSince(since)) }
        let seconds = max(0, Int(progress.lastSeen.timeIntervalSince(progress.start) - stopped))
        let capped = min(seconds, progress.plannedMinutes * 60)
        let session = add(start: progress.start, seconds: capped, plannedMinutes: progress.plannedMinutes,
                          completed: false, subject: progress.subject, pet: progress.pet, notes: progress.notes)
        // Il segno "in corso" si toglie solo dopo averlo salvato; se il registro è in sola lettura resta dov'è
        // (sotto il minuto, invece, non c'è niente da conservare).
        if session != nil || !isReadOnly { finishInProgress() }
        return session
    }

    private func readProgress() -> InProgress? {
        guard let data = try? Data(contentsOf: progressFile) else { return nil }
        return try? Self.decoder().decode(InProgress.self, from: data)
    }

    private func writeProgress(_ progress: InProgress) {
        do {
            try FileManager.default.createDirectory(at: progressFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder().encode(progress).write(to: progressFile, options: .atomic)
            recover("progress")
        } catch {
            fail("progress", "Non riesco a salvare il focus in corso: se l'app si chiude di colpo non lo recupero.")
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
    /// Quante sessioni del periodo hanno ciascun voto.
    var ratingCounts: [FocusRating: Int] = [:]
    var ratedCount: Int { ratingCounts.values.reduce(0, +) }
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
        for session in inPeriod {
            if let rating = session.rating { summary.ratingCounts[rating, default: 0] += 1 }
        }

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

    /// I secondi di studio del giorno in cui è iniziata `session` (compresa lei).
    static func seconds(onDayOf session: StudySession, in sessions: [StudySession], calendar: Calendar = StudyPeriod.calendar()) -> Int {
        let day = calendar.startOfDay(for: session.startTime(in: calendar))
        return sessions.filter { calendar.startOfDay(for: $0.startTime(in: calendar)) == day }.reduce(0) { $0 + $1.seconds }
    }

    /// Giorni consecutivi con almeno un focus, fino a oggi. Se oggi non c'è ancora niente conta da ieri, così la serie
    /// non si azzera la mattina. Un giorno senza studio non la azzera: la ghiaccia (vedi `StudyStreak`).
    static func streak(sessions: [StudySession], now: Date, calendar: Calendar = StudyPeriod.calendar()) -> Int {
        StudyStreak.analyze(sessions: sessions, now: now, calendar: calendar).days
    }

    // MARK: - Quando rendi meglio

    /// Quante sessioni con un voto servono prima di tirare delle conclusioni.
    static let minimumRatedForInsights = 8
    /// Quante ne servono in un gruppo (una fascia, un giorno, una materia) per confrontarlo con gli altri.
    static let minimumPerGroup = 3
    /// Quanto deve distare un gruppo dalla media (in quota di "bene") per essere citato.
    static let minimumGap = 0.2

    /// Le fasce della giornata, per `hour` (0...23).
    static func daySlot(hour: Int) -> String {
        switch hour {
        case 6..<12: return "di mattina"
        case 12..<18: return "nel pomeriggio"
        case 18..<24: return "di sera"
        default: return "di notte"
        }
    }

    /// Fino a due frasi sul perché-quando-con-cosa i focus vanno meglio o peggio, con i conteggi, oppure
    /// niente se i dati sono pochi (meglio tacere che dire una cosa a caso).
    static func insights(sessions: [StudySession], calendar: Calendar = StudyPeriod.calendar()) -> [String] {
        let rated = sessions.filter { $0.rating != nil }
        guard rated.count >= minimumRatedForInsights else { return [] }
        let overall = Double(rated.filter { $0.rating == .good }.count) / Double(rated.count)

        struct Candidate { var gap: Double; var text: String; var dimension: Int }
        var candidates: [Candidate] = []

        func evaluate(dimension: Int, key: (StudySession) -> String?, display: (String) -> String,
                      best: (String, Int, Int) -> String, worst: (String, Int, Int) -> String) {
            var groups: [String: (good: Int, total: Int)] = [:]
            for s in rated {
                guard let k = key(s) else { continue }
                var g = groups[k] ?? (0, 0)
                g.total += 1
                if s.rating == .good { g.good += 1 }
                groups[k] = g
            }
            let usable = groups.filter { $0.value.total >= minimumPerGroup }
            // Dal migliore e dal peggiore: ordino anche per nome per avere sempre lo stesso risultato.
            let scored = usable.map { (key: $0.key, share: Double($0.value.good) / Double($0.value.total), good: $0.value.good, total: $0.value.total) }
                .sorted { $0.share != $1.share ? $0.share > $1.share : $0.key < $1.key }
            if let top = scored.first, top.share - overall >= minimumGap, scored.count > 1 {
                candidates.append(Candidate(gap: top.share - overall, text: best(display(top.key), top.good, top.total), dimension: dimension))
            }
            if let low = scored.last, overall - low.share >= minimumGap, scored.count > 1 {
                candidates.append(Candidate(gap: overall - low.share, text: worst(display(low.key), low.good, low.total), dimension: dimension))
            }
        }

        // Fascia della giornata
        evaluate(dimension: 0,
                 key: { daySlot(hour: calendar.component(.hour, from: $0.startTime(in: calendar))) },
                 display: { $0 },
                 best: { "Rendi meglio \($0): \($1) focus su \($2) sono andati bene." },
                 worst: { "Rendi meno \($0): \($1) focus su \($2) sono andati bene." })
        // Giorno della settimana
        evaluate(dimension: 1,
                 key: { "\(calendar.component(.weekday, from: $0.startTime(in: calendar)))" },
                 display: { weekdayName(Int($0) ?? 1) },
                 best: { "Il \($0) rendi meglio: \($1) focus su \($2) sono andati bene." },
                 worst: { "Il \($0) fai più fatica: \($1) focus su \($2) sono andati bene." })
        // Materia
        evaluate(dimension: 2,
                 key: { $0.subject.map { Subject.key($0) } },
                 display: { key in rated.first(where: { $0.subject.map { Subject.key($0) } == key })?.subject ?? key },
                 best: { "Con \($0) vai bene: \($1) focus su \($2) sono andati bene." },
                 worst: { "Con \($0) fai più fatica: \($1) focus su \($2) sono andati bene." })

        var result: [String] = []
        var usedDimensions = Set<Int>()
        for c in candidates.sorted(by: { $0.gap != $1.gap ? $0.gap > $1.gap : $0.text < $1.text }) {
            guard !usedDimensions.contains(c.dimension) else { continue }
            usedDimensions.insert(c.dimension)
            result.append(c.text)
            if result.count == 2 { break }
        }
        return result
    }

    /// Il giorno della settimana (1 = domenica, come in Calendar) in italiano.
    static func weekdayName(_ weekday: Int) -> String {
        ["domenica", "lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato"][max(0, min(6, weekday - 1))]
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

// MARK: - Esportazione

enum SessionCSV {
    static let header = "inizio,inizio_locale,minuti,minuti_previsti,completa,materia,personaggio,com_e_andata,nota,note_del_focus"

    /// Un campo di testo tra virgolette. Se comincia con un carattere che un foglio di calcolo prende per una
    /// formula (= + - @) gli metto davanti un apice, così non viene eseguito.
    static func quoted(_ text: String) -> String {
        var value = text
        if let first = value.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(first) { value = "'" + value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func csv(for sessions: [StudySession]) -> String {
        let iso = ISO8601DateFormatter()
        var lines = [header]
        for s in sessions {
            lines.append([
                iso.string(from: s.start), s.localStart ?? "", "\((s.seconds + 30) / 60)", "\(s.plannedMinutes)",
                s.completed ? "si" : "no", quoted(s.subject ?? ""), s.pet ?? "",
                s.rating?.rawValue ?? "", quoted(s.note ?? ""), quoted((s.notes ?? []).joined(separator: " | ")),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
