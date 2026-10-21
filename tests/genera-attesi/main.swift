import Foundation

// Rifà tests/fixtures/attesi/*.json: per ogni cartella di dati di esempio, quello che la versione per Mac ne ricava
// con un «adesso» fisso (14 ottobre 2026, ore 20:00, fuso Europe/Rome). Le altre versioni dell'app (Windows) devono
// dare gli stessi risultati. Si lancia con tests/genera-attesi.sh.
//
// Ogni cartella viene copiata in una cartella temporanea prima di leggerla: l'app può riscrivere, migrare o spostare
// file, e gli esempi non devono cambiare.

let args = CommandLine.arguments
guard args.count == 3 else { print("uso: genera-attesi <cartella degli esempi> <cartella degli attesi>"); exit(2) }
let fixtures = URL(fileURLWithPath: args[1]), outputDirectory = URL(fileURLWithPath: args[2])
let fm = FileManager.default
let rome = TimeZone(identifier: "Europe/Rome")!
var cal = StudyPeriod.calendar()
cal.timeZone = rome
let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 20, minute: 0))!
let pets = ["pianty", "porcellino", "ciccio", "gattino"]       // l'ordine di Pet.all

func r(_ x: Double) -> Double { (x * 1000).rounded() / 1000 }
func v(_ x: String?) -> Any { x ?? NSNull() }
let dayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = rome
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

func normalized(_ path: String) -> String {
    path.replacingOccurrences(of: #"corrotto-\d+"#, with: "corrotto-<epoch>", options: .regularExpression)
}

func summaryJSON(_ s: StudySummary) -> [String: Any] {
    [
        "secondiTotali": s.totalSeconds, "focus": s.focusCount, "completati": s.completedCount, "interrotti": s.interruptedCount,
        "perMateria": s.bySubject.map { ["materia": $0.subject, "secondi": $0.seconds] as [String: Any] },
        "barre": s.buckets.map { $0.seconds },
        "voti": ["good": s.ratingCounts[.good] ?? 0, "soso": s.ratingCounts[.soso] ?? 0, "poor": s.ratingCounts[.poor] ?? 0],
    ]
}

func relativeFiles(in directory: URL) -> [String] {
    let base = directory.resolvingSymlinksInPath().path
    var found: [String] = []
    if let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) {
        for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            found.append(normalized(String(url.resolvingSymlinksInPath().path.dropFirst(base.count + 1))))
        }
    }
    return found.sorted()
}

// ---- le frasi di contesto (Remarks.swift): i saluti, il riepilogo, i numeri e i traguardi, in alcuni momenti fissi e con i dati della cartella

let contextMoments: [(Int, Int, Int, Int, Int)] = [(2026, 10, 12, 9, 30), (2026, 10, 13, 15, 0), (2026, 10, 14, 20, 0), (2026, 10, 15, 2, 30),
                                                   (2026, 10, 18, 10, 0), (2026, 10, 26, 8, 0)]
let contextDue = "Oggi scade «Esercizi di analisi». Un focus adesso?"

func contextJSON(sessions: [StudySession]) -> [String: Any] {
    func ctx(_ at: Date, name: String? = "Jacopo", todos: Int = 0, due: String? = nil) -> Remarks.Context {
        Remarks.Context(now: at, calendar: cal, name: name, sessions: sessions, openTodoCount: todos, due: due)
    }
    var moments: [[String: Any]] = []
    for (y, mo, d, h, mi) in contextMoments {
        let at = cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
        let withDue = Remarks.launchGreeting(ctx(at, todos: 2, due: contextDue), variant: 0)
        let recap = Remarks.weeklyRecap(ctx(at))
        moments.append([
            "adesso": String(format: "%04d-%02d-%02dT%02d:%02d", y, mo, d, h, mi),
            "saluti": (0..<6).map { Remarks.launchGreeting(ctx(at, todos: 2), variant: $0).text },
            "salutoSenzaNome": Remarks.launchGreeting(ctx(at, name: nil), variant: 0).text,
            "salutoConScadenza": ["testo": withDue.text, "copreIlPromemoria": withDue.coversReminder] as [String: Any],
            "risveglio": (0..<6).map { (i: Int) -> Any in v(Remarks.wakeGreeting(ctx(at, todos: 2), away: 7200, variant: i)?.text) },
            "risveglioBreve": v(Remarks.wakeGreeting(ctx(at), away: 1800, variant: 0)?.text),
            "riepilogo": recap == nil ? NSNull() as Any : ["chiave": recap!.key, "testo": recap!.text] as [String: Any],
            "numeri": (0..<3).map { (i: Int) -> Any in v(Remarks.insight(ctx(at), variant: i)) },
        ])
    }
    // I traguardi: man mano che il registro cresce (ogni sessione, dalla più vecchia), quali frasi scattano.
    let ordered = sessions.sorted { $0.start != $1.start ? $0.start < $1.start : $0.id.uuidString < $1.id.uuidString }
    var milestones: [[String: Any]] = []
    for i in ordered.indices {
        if let text = Remarks.milestone(before: Array(ordered[..<i]), after: Array(ordered[...i]), now: ordered[i].start, calendar: cal) {
            milestones.append(["dopo": i + 1, "frase": text])
        }
    }
    return ["momenti": moments, "traguardi": milestones]
}

/// Gli anniversari («un mese insieme»…) su date inventate: per ogni primo giorno e ogni giorno dopo, la frase se scatta.
func anniversaryJSON() -> [[String: Any]] {
    func session(_ y: Int, _ m: Int, _ d: Int) -> StudySession {
        let start = cal.date(from: DateComponents(year: y, month: m, day: d, hour: 10))!
        return StudySession(start: start, localStart: StudySession.localString(for: start, calendar: cal), seconds: 3000, plannedMinutes: 50, completed: true, subject: nil)
    }
    var found: [[String: Any]] = []
    for first in [(2026, 1, 31), (2026, 1, 30), (2026, 1, 29), (2024, 2, 29), (2025, 12, 15), (2026, 8, 31), (2026, 3, 31), (2026, 2, 28)] {
        let firstSession = session(first.0, first.1, first.2)
        var day = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: firstSession.start))!
        let end = cal.date(from: DateComponents(year: 2029, month: 1, day: 1))!
        while day < end {
            let c = cal.dateComponents([.year, .month, .day], from: day)
            let today = session(c.year!, c.month!, c.day!)
            let at = cal.date(byAdding: .hour, value: 2, to: today.start)!
            if let text = Remarks.milestone(before: [firstSession], after: [firstSession, today], now: at, calendar: cal) {
                found.append(["primo": String(format: "%04d-%02d-%02d", first.0, first.1, first.2),
                              "oggi": String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!), "frase": text])
            }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
    }
    return found
}

try? fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
var written = 0
for entry in try fm.contentsOfDirectory(atPath: fixtures.path).sorted() {
    let source = fixtures.appendingPathComponent(entry)
    var isDirectory: ObjCBool = false
    // «impostazioni-*»: sul Mac le preferenze stanno in UserDefaults, quindi non c'è un atteso da ricavare (vedi FORMATI.md §6).
    guard entry != "attesi", !entry.hasPrefix("impostazioni"), fm.fileExists(atPath: source.path, isDirectory: &isDirectory),
          isDirectory.boolValue else { continue }
    let tmp = fm.temporaryDirectory.appendingPathComponent("ff-attesi-\(UUID().uuidString)")
    try fm.copyItem(at: source, to: tmp)
    func has(_ name: String) -> Bool { fm.fileExists(atPath: tmp.appendingPathComponent(name).path) }

    var result: [String: Any] = ["cartella": entry, "adesso": "2026-10-14T20:00 Europe/Rome"]
    var sessions: [StudySession] = []

    // ---- registro e focus in corso
    if has("sessioni.json") || has("in-corso.json") {
        let log = SessionLog(directory: tmp, now: { now }, timeZone: rome)
        var problems: [String] = []
        log.onProblem = { problems.append(normalized($0)) }
        var part: [String: Any] = [:]
        let hadProgress = has("in-corso.json")
        if hadProgress {
            if let recovered = log.recoverInterrupted() {
                part["recuperata"] = ["secondi": recovered.seconds, "minutiPrevisti": recovered.plannedMinutes, "completa": recovered.completed,
                                      "materia": v(recovered.subject), "personaggio": v(recovered.pet), "note": recovered.notes ?? [],
                                      "inizioLocale": v(recovered.localStart)] as [String: Any]
            } else {
                part["recuperata"] = NSNull()
            }
            part["inCorsoRimasto"] = has("in-corso.json")
        }
        sessions = log.sessions
        part["numero"] = sessions.count
        part["solaLettura"] = log.isReadOnly
        part["secondiTotali"] = sessions.reduce(0) { $0 + $1.seconds }
        part["materie"] = Array(Set(sessions.compactMap { $0.subject })).sorted()
        part["conOraLocale"] = sessions.filter { $0.localStart != nil }.count
        part["avvisi"] = problems
        // (una sessione recuperata ha un id nuovo a ogni lettura: l'ordine si confronta solo per quelle lette dal file)
        if !hadProgress { part["ordineId"] = sessions.map { String($0.id.uuidString.suffix(4)) } }
        result["registro"] = part

        if !sessions.isEmpty {
            var stats: [String: Any] = [:]
            for (name, kind) in [("giorno", PeriodKind.day), ("settimana", .week), ("mese", .month)] {
                let period = StudyPeriod.containing(now, kind: kind, calendar: cal)
                stats[name] = summaryJSON(StudyStats.summary(sessions: sessions, period: period, calendar: cal))
            }
            let streak = StudyStreak.analyze(sessions: sessions, now: now, calendar: cal)
            var perDay: [String: Int] = [:]
            for (day, count) in streak.perDay { perDay[dayFormatter.string(from: day)] = count }
            stats["serie"] = ["giorni": streak.days, "ghiacciata": streak.isFrozen, "hoStudiatoOggi": streak.studiedToday, "perGiorno": perDay] as [String: Any]
            let weighted = GardenPoints.weightedMinutes(sessions: sessions, now: now, calendar: cal)
            stats["punti"] = ["minutiPesati": r(weighted), "guadagnati": GardenPoints.points(forWeightedMinutes: weighted),
                              "verso il prossimo": r(GardenPoints.progressToNextPoint(weightedMinutes: weighted)),
                              "valoreMinutoOggi": GardenPoints.multiplierToday(streak)] as [String: Any]
            stats["frasi"] = StudyStats.insights(sessions: sessions, calendar: cal)
            stats["csv"] = SessionCSV.csv(for: sessions)
            result["statistiche"] = stats
            result["contesto"] = contextJSON(sessions: sessions)
        }
    }

    // ---- profilo
    var profile: Profile?
    if has("profilo.json") {
        let p = Profile(directory: tmp)
        var problems: [String] = []
        p.onProblem = { problems.append(normalized($0)) }
        var part: [String: Any] = ["nome": v(p.name), "introduzioneVista": p.introSeen,
                                   "sbloccati": p.unlocked.map { Array($0).sorted() } ?? NSNull(), "primoCompagno": v(p.firstCompanion),
                                   "avvisi": problems, "titoloGiardino": p.gardenTitle, "titoloStatistiche": p.statsTitle]
        var usable: [String: Bool] = [:]
        for pet in pets { usable[pet] = p.isCompanionUnlocked(pet) }
        part["compagniUsabili"] = usable
        if !sessions.isEmpty {
            let focuses = CompanionRewards.focuses(totalSeconds: sessions.reduce(0) { $0 + $1.seconds })
            part["focusPieni"] = focuses
            part["compagniMeritati"] = CompanionRewards.earned(first: p.firstCompanion, all: pets, focuses: focuses).sorted()
        }
        p.keepAllCompanions(pets)
        part["sbloccatiDopoKeepAll"] = p.unlocked.map { Array($0).sorted() } ?? NSNull()
        result["profilo"] = part
        profile = p
    } else if entry.hasPrefix("profilo") {
        result["profilo"] = ["nota": "nessun file"]
    }
    _ = profile

    // ---- giardino
    if has("giardino.json") {
        let g = Garden(directory: tmp)
        var problems: [String] = []
        g.onProblem = { problems.append(normalized($0)) }
        var part: [String: Any] = [
            "sbloccatiConPunti": Array(g.unlocked).sorted(), "speso": g.spent, "avvisi": problems,
            "copie": g.placements.map { ["oggetto": $0.item, "x": r($0.x), "y": r($0.y)] as [String: Any] },
            "compagni": g.companionSpots.mapValues { ["x": r($0.x), "y": r($0.y)] },
            "oggettiUsabili": GardenCatalog.items.filter { g.isUnlocked($0.id) }.map { $0.id },
        ]
        if !sessions.isEmpty {
            let earned = GardenPoints.earned(sessions: sessions, now: now, calendar: cal)
            part["saldo"] = GardenPoints.balance(earned: earned, spent: g.spent)
        }
        result["giardino"] = part
    }

    // ---- cose da fare
    if has("dafare.json") {
        let list = ToDoList(directory: tmp, now: { now })
        var problems: [String] = []
        list.onProblem = { problems.append(normalized($0)) }
        let today = ToDoDay.string(for: now, calendar: cal)
        let iso = ISO8601DateFormatter()
        var reminders: [String: Any] = [:]
        for offset in [-1, 0, 1] {
            let day = ToDoDay.adding(days: offset, to: today)!
            reminders[day] = v(ToDoReminder.message(for: list.items, today: day))
        }
        result["daFare"] = [
            "voci": list.items.count, "daFare": list.openCount, "solaLettura": list.isReadOnly, "avvisi": problems,
            "gruppi": list.sections(today: today).map { section in
                ["gruppo": section.group.title, "voci": section.items.map { item in
                    ["testo": item.text, "scadenza": v(item.due), "etichetta": v(item.due.map { ToDoDay.label(due: $0, today: today) }),
                     "materia": v(item.subject)] as [String: Any]
                }] as [String: Any]
            },
            "fatte": list.doneItems.map { ["testo": $0.text, "fattaIl": iso.string(from: $0.doneAt!)] as [String: Any] },
            "promemoria": reminders,
        ] as [String: Any]
    }

    result["fileDopo"] = relativeFiles(in: tmp)
    let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try (data + Data("\n".utf8)).write(to: outputDirectory.appendingPathComponent("\(entry).json"))
    written += 1
    try? fm.removeItem(at: tmp)
}
let anniversaries = try JSONSerialization.data(withJSONObject: ["anniversari": anniversaryJSON()], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
try (anniversaries + Data("\n".utf8)).write(to: outputDirectory.appendingPathComponent("_contesto-anniversari.json"))
print("Scritti \(written) file in \(outputDirectory.path)")
