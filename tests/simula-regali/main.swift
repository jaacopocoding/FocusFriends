import Foundation

// Quanto ci vuole a completare l'album con le regole di GardenDrops (Sources/FocusFriends/GardenDrops.swift), per tre modi di studiare.
// Utenti inventati, tanti: la mediana e la coda. Serve a tarare i numeri del gioco: non fa parte dell'app né delle prove.
// Si lancia con tests/simula-regali.sh [quanti oggetti ha l'album: 36 (quelli di adesso) o di più, con le stesse proporzioni di rarità].
var cal = StudyPeriod.calendar()
cal.timeZone = TimeZone(identifier: "Europe/Rome")!
func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))! }

struct Habit { var name: String; var studyChance: Double; var focusPerDay: ClosedRange<Int>; var minutes: [Int] }
let habits = [
    Habit(name: "tranquillo: 4 giorni su 7, 1–2 focus da 25–50", studyChance: 4.0 / 7, focusPerDay: 1...2, minutes: [25, 30, 50]),
    Habit(name: "regolare: 6 giorni su 7, 2–3 focus", studyChance: 6.0 / 7, focusPerDay: 2...3, minutes: [25, 50]),
    Habit(name: "intenso: tutti i giorni, 3–5 focus", studyChance: 1, focusPerDay: 3...5, minutes: [25, 50]),
]
// L'album di prova: i 36 di adesso, oppure uno più grande con le stesse proporzioni di rarità (45% comuni, 42% rari, 13% leggendari).
let size = Int(CommandLine.arguments.dropFirst().first ?? "36") ?? 36
var pool = GardenCatalog.items
if size > 36 {
    pool = (0..<size).map { i in
        let share = Double(i) / Double(size)
        let price = i < 4 ? 0 : share < 0.45 ? 2 : share < 0.87 ? 5 : 9
        return GardenItem(id: "prova\(i)", name: "p\(i)", category: .flowers, height: 50, price: price)
    }
}
let total = pool.count
var generator = SystemRandomNumberGenerator()
let start = date(2026, 1, 1)
let horizon = 365
let milestones = [0.5, 0.75, 1.0]

for habit in habits {
    var firstDays: [[Int?]] = [[], [], []]       // per i traguardi del 50%, 75%, 100% dell'album
    var firstRare: [Int] = [], firstLegendary: [Int] = []
    var gifts: [Int] = [], empty: [Double] = []
    let users = 200
    for _ in 0..<users {
        var sessions: [StudySession] = []
        for day in 0..<horizon {
            guard Double.random(in: 0..<1, using: &generator) < habit.studyChance else { continue }
            let d = cal.date(byAdding: .day, value: day, to: start)!
            for k in 0..<Int.random(in: habit.focusPerDay, using: &generator) {
                let minutes = habit.minutes.randomElement(using: &generator)!
                let at = d.addingTimeInterval(Double(8 * 3600 + k * 5400))
                // il 12% dei focus si interrompe: non dà regali
                let completed = Double.random(in: 0..<1, using: &generator) > 0.12
                sessions.append(StudySession(start: at, localStart: StudySession.localString(for: at, calendar: cal), seconds: minutes * 60, plannedMinutes: minutes, completed: completed, subject: nil))
            }
        }
        let drops = GardenDrops.simulate(sessions: sessions, now: cal.date(byAdding: .day, value: horizon, to: start)!, calendar: cal, pool: pool)
        var found = Set(pool.filter { $0.isStarter }.map { $0.id })
        var reached = [Int?](repeating: nil, count: 3)
        var rareDay: Int?, legendaryDay: Int?
        var given = 0, nothing = 0
        for (session, drop) in drops {
            let day = cal.dateComponents([.day], from: start, to: session.startTime(in: cal)).day ?? 0
            guard let drop else { nothing += 1; continue }
            given += 1
            found.insert(drop.item)
            if drop.rarity >= .rare, rareDay == nil, drop.isNew { rareDay = day }
            if drop.rarity == .legendary, legendaryDay == nil { legendaryDay = day }
            for (i, m) in milestones.enumerated() where reached[i] == nil && Double(found.count) >= m * Double(total) { reached[i] = day }
        }
        for i in 0..<3 { firstDays[i].append(reached[i]) }
        if let rareDay { firstRare.append(rareDay) }
        if let legendaryDay { firstLegendary.append(legendaryDay) }
        gifts.append(given)
        empty.append(Double(nothing) / Double(max(given + nothing, 1)))
    }
    func summary(_ values: [Int?]) -> String {
        let done = values.compactMap { $0 }.sorted()
        guard !done.isEmpty else { return "mai (entro un anno)" }
        let median = done[done.count / 2], slow = done[min(done.count - 1, Int(Double(done.count) * 0.9))]
        return "giorno \(median) (90%: \(slow)) — lo raggiunge il \(Int(100 * Double(done.count) / Double(values.count)))%"
    }
    let sortedGifts = gifts.sorted()
    print("== \(habit.name)")
    print("   regali in un anno: mediana \(sortedGifts[sortedGifts.count / 2]); focus senza niente: \(Int(100 * empty.reduce(0, +) / Double(empty.count)))% dei tiri")
    print("   metà dell'album (\(total / 2)): \(summary(firstDays[0]))")
    print("   tre quarti: \(summary(firstDays[1]))")
    print("   album completo (\(total)): \(summary(firstDays[2]))")
    let r = firstRare.sorted(), l = firstLegendary.sorted()
    print("   primo raro nuovo: giorno \(r.isEmpty ? -1 : r[r.count / 2]); primo leggendario: giorno \(l.isEmpty ? -1 : l[l.count / 2])")
}
