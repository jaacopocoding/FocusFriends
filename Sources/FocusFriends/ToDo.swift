import Foundation

/// Il giorno di una scadenza: «AAAA-MM-GG» sul calendario del computer, senza ora e senza fuso. Così una scadenza
/// resta quella scritta anche se cambia il fuso orario, e il file si legge uguale sul Mac e su Windows.
enum ToDoDay {
    static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// «AAAA-MM-GG», solo se è un giorno che esiste (non il 31 giugno).
    static func isValid(_ text: String) -> Bool {
        parts(text) != nil
    }

    private static func parts(_ text: String) -> (year: Int, month: Int, day: Int)? {
        let pieces = text.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces[0].count == 4, pieces[1].count == 2, pieces[2].count == 2,
              pieces.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(pieces[0]), let month = Int(pieces[1]), let day = Int(pieces[2]) else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let date = utc.date(from: DateComponents(year: year, month: month, day: day)),
              utc.dateComponents([.year, .month, .day], from: date) == DateComponents(year: year, month: month, day: day) else { return nil }
        return (year, month, day)
    }

    static func string(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    /// Quanti giorni da `from` a `to` (negativo = prima). nil se uno dei due non è un giorno valido.
    static func days(from: String, to: String) -> Int? {
        guard let a = parts(from), let b = parts(to) else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let dateA = utc.date(from: DateComponents(year: a.year, month: a.month, day: a.day)),
              let dateB = utc.date(from: DateComponents(year: b.year, month: b.month, day: b.day)) else { return nil }
        return utc.dateComponents([.day], from: dateA, to: dateB).day
    }

    static func adding(days: Int, to day: String) -> String? {
        guard let p = parts(day) else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let date = utc.date(from: DateComponents(year: p.year, month: p.month, day: p.day)),
              let moved = utc.date(byAdding: .day, value: days, to: date) else { return nil }
        return string(for: moved, calendar: utc)
    }

    private static let weekdays = ["dom", "lun", "mar", "mer", "gio", "ven", "sab"]
    private static let months = ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"]

    /// Come si scrive una scadenza vicino alla voce: «ieri», «oggi», «domani», «ven 23» (entro la settimana), «26 ott»
    /// (e l'anno, se non è questo).
    static func label(due: String, today: String) -> String {
        guard let diff = days(from: today, to: due), let p = parts(due), let t = parts(today) else { return due }
        switch diff {
        case -1: return "ieri"
        case 0: return "oggi"
        case 1: return "domani"
        case 2...6:
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            let date = utc.date(from: DateComponents(year: p.year, month: p.month, day: p.day))!
            return "\(weekdays[utc.component(.weekday, from: date) - 1]) \(p.day)"
        default:
            let base = "\(p.day) \(months[p.month - 1])"
            return p.year == t.year ? base : "\(base) \(p.year)"
        }
    }
}

/// Il testo di una voce: spazi in eccesso e caratteri di controllo tolti, al massimo `maxLength` caratteri; vuoto = niente.
enum ToDoText {
    static let maxLength = 120

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

/// Cosa dice il compagno delle scadenze: solo quelle di oggi e di domani (le scadute non si rinfacciano).
enum ToDoReminder {
    /// Quanto è lungo, al massimo, il testo di una voce dentro il fumetto.
    static let maxQuoted = 36

    /// La frase per oggi (se c'è qualcosa che scade oggi) o, altrimenti, per domani; nil se non c'è niente di cui parlare.
    static func message(for items: [ToDoItem], today: String) -> String? {
        let open = items.filter { !$0.isDone }.sorted { $0.createdAt < $1.createdAt }
        if let text = sentence(open.filter { $0.due == today }, when: "Oggi", singular: "scade", plural: "scadono") { return text }
        guard let tomorrow = ToDoDay.adding(days: 1, to: today) else { return nil }
        return sentence(open.filter { $0.due == tomorrow }, when: "Domani", singular: "scade", plural: "scadono")
    }

    private static func sentence(_ items: [ToDoItem], when: String, singular: String, plural: String) -> String? {
        guard let first = items.first else { return nil }
        let quoted = "«\(shortened(first.text))»"
        if items.count == 1 { return "\(when) \(singular) \(quoted). Un focus adesso?" }
        let others = items.count - 1
        return "\(when) \(plural) \(items.count) cose: \(quoted) e \(others == 1 ? "un'altra" : "altre \(others)")."
    }

    /// Il testo accorciato (se serve) a una parola intera, con i puntini.
    private static func shortened(_ text: String) -> String {
        guard text.count > maxQuoted else { return text }
        var cut = String(text.prefix(maxQuoted - 1))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > maxQuoted / 2 {
            cut = String(cut[..<space])
        }
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Una cosa da fare: un testo, e se serve un giorno di scadenza e una materia.
struct ToDoItem: Codable, Equatable {
    var id: UUID
    var text: String
    /// «AAAA-MM-GG» (vedi `ToDoDay`); nil = senza scadenza.
    var due: String?
    var subject: String?
    var createdAt: Date
    /// Quando è stata segnata come fatta; nil = ancora da fare.
    var doneAt: Date?

    var isDone: Bool { doneAt != nil }
}

enum ToDoGroup: Int {
    case overdue, today, upcoming, noDate

    var title: String {
        switch self {
        case .overdue: return "Scadute"
        case .today: return "Oggi"
        case .upcoming: return "Prossime"
        case .noDate: return "Senza data"
        }
    }
}

struct ToDoSection: Equatable {
    var group: ToDoGroup
    var items: [ToDoItem]
}

/// La lista delle cose da fare: sta in `dafare.json` accanto ai dati (formato in FORMATI.md §5). Le voci fatte restano
/// una settimana e poi spariscono. Solo Foundation: si collauda da solo (tests/main.swift).
final class ToDoList {
    static let formatVersion = 1
    /// Quante voci al massimo (aperte e fatte da poco).
    static let maxItems = 200
    /// Quanti giorni restano le voci fatte.
    static let keepDoneDays = 7

    static let shared = ToDoList(directory: SessionLog.defaultDirectory)

    enum AddResult: Equatable {
        case added(ToDoItem)
        /// Il testo è vuoto (dopo averlo pulito).
        case empty
        /// Ci sono già `maxItems` voci.
        case full
    }

    private struct Contents: Codable {
        var version: Int
        var items: [ToDoItem]
    }

    private let file: URL
    private let now: () -> Date
    private(set) var items: [ToDoItem] = []
    /// Il file c'è ma non si legge, o è di una versione più nuova: lo leggo e non lo riscrivo.
    private(set) var isReadOnly = false
    private var observers: [() -> Void] = []
    private var writeFailureReported = false

    var onProblem: ((String) -> Void)? {
        didSet {
            guard let handler = onProblem, !pendingProblems.isEmpty else { return }
            let pending = pendingProblems
            pendingProblems = []
            pending.forEach(handler)
        }
    }
    private var pendingProblems: [String] = []

    private func report(_ message: String) {
        if let handler = onProblem { handler(message) } else { pendingProblems.append(message) }
    }

    init(directory: URL, now: @escaping () -> Date = Date.init) {
        self.file = directory.appendingPathComponent("dafare.json")
        self.now = now
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        guard let data = try? Data(contentsOf: file) else {
            isReadOnly = true
            report("Il file delle cose da fare non si legge: non lo modifico.")
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let contents = try? decoder.decode(Contents.self, from: data) {
            if contents.version > Self.formatVersion {
                isReadOnly = true
                report("Il file delle cose da fare è di una versione più nuova dell'app: lo leggo ma non lo modifico.")
            }
            items = contents.items.compactMap(Self.sanitized)
            if !isReadOnly { purgeOldDone() }
        } else {
            let aside = directory.appendingPathComponent("dafare.corrotto-\(Int(Date().timeIntervalSince1970)).json")
            do {
                try FileManager.default.moveItem(at: file, to: aside)
                report("Il file delle cose da fare era rovinato: l'ho messo da parte come \(aside.lastPathComponent).")
            } catch {
                isReadOnly = true
                report("Il file delle cose da fare è rovinato e non riesco a metterlo da parte: non lo modifico.")
            }
        }
    }

    /// Una voce letta dal file, ripulita: testo vuoto = si scarta, scadenza che non esiste = si toglie, materia pulita.
    private static func sanitized(_ item: ToDoItem) -> ToDoItem? {
        guard let text = ToDoText.clean(item.text) else { return nil }
        var clean = item
        clean.text = text
        clean.due = item.due.flatMap { ToDoDay.isValid($0) ? $0 : nil }
        clean.subject = Subject.clean(item.subject)
        return clean
    }

    func addObserver(_ observer: @escaping () -> Void) {
        observers.append(observer)
    }

    // MARK: - Modifiche

    @discardableResult
    func add(text: String, due: String? = nil, subject: String? = nil) -> AddResult {
        guard let cleaned = ToDoText.clean(text) else { return .empty }
        guard items.count < Self.maxItems else { return .full }
        let item = ToDoItem(id: UUID(), text: cleaned, due: due.flatMap { ToDoDay.isValid($0) ? $0 : nil },
                            subject: Subject.clean(subject), createdAt: now(), doneAt: nil)
        items.append(item)
        save()
        return .added(item)
    }

    /// Segna come fatta (o rimette tra quelle da fare).
    func toggleDone(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].doneAt = items[index].isDone ? nil : now()
        save()
    }

    func remove(id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        save()
    }

    /// Toglie le voci fatte da più di `keepDoneDays` giorni. Non scrive: lo fa chi chiama.
    @discardableResult
    private func purgeOldDone() -> Bool {
        let limit = now().addingTimeInterval(-Double(Self.keepDoneDays) * 86_400)
        let before = items.count
        items.removeAll { item in item.doneAt.map { $0 < limit } ?? false }
        return items.count != before
    }

    // MARK: - Per la scheda

    var openItems: [ToDoItem] { items.filter { !$0.isDone } }
    var openCount: Int { openItems.count }

    /// Le voci fatte, la più recente per prima.
    var doneItems: [ToDoItem] {
        items.filter(\.isDone).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
    }

    /// Scadute e di oggi: quelle che chiedono attenzione.
    func urgentCount(today: String) -> Int {
        openItems.filter { item in item.due.map { (ToDoDay.days(from: today, to: $0) ?? 1) <= 0 } ?? false }.count
    }

    /// Le voci da fare, raggruppate (le sezioni vuote non ci sono): scadute (le più vecchie prima), di oggi, prossime
    /// (le più vicine prima), senza data. A parità, la più vecchia per prima.
    func sections(today: String) -> [ToDoSection] {
        func groupOf(_ item: ToDoItem) -> ToDoGroup {
            guard let due = item.due, let diff = ToDoDay.days(from: today, to: due) else { return .noDate }
            return diff < 0 ? .overdue : diff == 0 ? .today : .upcoming
        }
        let open = openItems
        return [ToDoGroup.overdue, .today, .upcoming, .noDate].compactMap { group in
            let inGroup = open.filter { groupOf($0) == group }
                .sorted { a, b in
                    if a.due != b.due { return (a.due ?? "") < (b.due ?? "") }
                    return a.createdAt < b.createdAt
                }
            return inGroup.isEmpty ? nil : ToDoSection(group: group, items: inGroup)
        }
    }

    /// La scadenza più vicina tra quelle da fare (oggi, domani…), per il fumetto del compagno.
    func nextDue() -> ToDoItem? {
        openItems.filter { $0.due != nil }.min { ($0.due ?? "", $0.createdAt) < ($1.due ?? "", $1.createdAt) }
    }

    // MARK: - Salvataggio

    private func save() {
        purgeOldDone()
        guard !isReadOnly else {
            observers.forEach { $0() }
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(Contents(version: Self.formatVersion, items: items)).write(to: file, options: .atomic)
            writeFailureReported = false
        } catch {
            if !writeFailureReported {
                writeFailureReported = true
                report("Non riesco a salvare le cose da fare: \(error.localizedDescription).")
            }
        }
        observers.forEach { $0() }
    }
}
