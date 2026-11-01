import Foundation

// Quanto ci vuole a sbloccare i compagni e a completare l'album con le regole di adesso, per tre modi di studiare (Sources/FocusFriends/GardenDrops.swift e CompanionRewards.swift).
// Le regole: un regalo ogni tot minuti di studio (60 il primo, 8 in più per ogni cosa trovata); i compagni si sbloccano a 20, 50, 100 e 150 focus pieni da 50 minuti, e solo le cose
// dei compagni sbloccati possono uscire (le isole chiuse non contano). Il primo compagno è Ciccio e gli altri vengono nell'ordine del menu.
// Utenti inventati, tanti: la mediana. Serve a tarare i numeri del gioco: non fa parte dell'app né delle prove.
// Si lancia con tests/simula-regali.sh
var cal = StudyPeriod.calendar()
cal.timeZone = TimeZone(identifier: "Europe/Rome")!

struct Habit { var name: String; var studyChance: Double; var focusPerDay: ClosedRange<Int>; var minutes: [Int] }
let habits = [
    Habit(name: "tranquillo: 4 giorni su 7, 1–2 focus da 25–50", studyChance: 4.0 / 7, focusPerDay: 1...2, minutes: [25, 30, 50]),
    Habit(name: "regolare: 6 giorni su 7, 2–3 focus", studyChance: 6.0 / 7, focusPerDay: 2...3, minutes: [25, 50]),
    Habit(name: "intenso: tutti i giorni, 3–5 focus", studyChance: 1, focusPerDay: 3...5, minutes: [25, 50]),
]
// L'ordine di sblocco (come nel menu, con il primo scelto in testa) e le isole di ognuno: i compagni sono quelli di `GardenIslands`.
let order = CompanionRewards.order(first: "ciccio", all: GardenIslands.all)
let all = GardenCatalog.items
let total = all.count
let horizon = 365
var generator = SystemRandomNumberGenerator()

struct Result {
    var unlockDays: [Int?]
    var half: Int?, threeQuarters: Int?, complete: Int?
    var emptyDays: Int
    var found: Int
    var firstMonthGifts: Int
}

func run(_ habit: Habit) -> Result {
    var state = GardenDropState.starting()
    var totalMinutes = 0, streak = 0, lastDay = -10, rolls = 0
    var result = Result(unlockDays: Array(repeating: nil, count: order.count), half: nil, threeQuarters: nil, complete: nil, emptyDays: 0, found: 0, firstMonthGifts: 0)
    var emptyDays = Set<Int>()
    for day in 0..<horizon where Double.random(in: 0..<1, using: &generator) < habit.studyChance {
        streak = day == lastDay + 1 ? streak + 1 : 1
        lastDay = day
        for _ in 0..<Int.random(in: habit.focusPerDay, using: &generator) {
            let minutes = habit.minutes.randomElement(using: &generator)!
            totalMinutes += minutes                       // contano tutti i minuti, anche quelli dei focus interrotti
            for position in order.indices where result.unlockDays[position] == nil && totalMinutes / CompanionRewards.minutesPerFocus >= CompanionRewards.threshold(at: position) {
                result.unlockDays[position] = day
            }
            guard Double.random(in: 0..<1, using: &generator) > 0.12, minutes >= 20 else { continue }      // il 12% dei focus si interrompe
            let open = Set(order.enumerated().filter { result.unlockDays[$0.offset] != nil }.map(\.element))
            let pool = all.filter { $0.island == nil || open.contains($0.island!) }
            if !GardenDrops.hasSomethingToFind(state: state, pool: pool), result.complete == nil { emptyDays.insert(day) }
            rolls += 1
            if GardenDrops.credit(sessionID: "S\(rolls)-\(generator.next())", streakDays: max(streak, 1), seconds: minutes * 60, state: &state, pool: pool) != nil {
                if day < 30 { result.firstMonthGifts += 1 }
                let count = state.found.count
                if result.half == nil, count * 2 >= total { result.half = day }
                if result.threeQuarters == nil, count * 4 >= total * 3 { result.threeQuarters = day }
                if result.complete == nil, count >= total { result.complete = day }
            }
        }
    }
    result.emptyDays = emptyDays.count
    result.found = state.found.count
    return result
}

func median(_ values: [Int?]) -> String {
    let done = values.compactMap { $0 }.sorted()
    guard !done.isEmpty else { return "mai (entro un anno)" }
    return "g\(done[done.count / 2])" + (done.count < values.count ? " [\(100 * done.count / values.count)%]" : "")
}

for habit in habits {
    let users = (0..<150).map { _ in run(habit) }
    print("== \(habit.name)")
    print("   sblocchi: " + (1..<order.count).map { position in "\(order[position]) \(median(users.map { $0.unlockDays[position] }))" }.joined(separator: " · "))
    print("   album (\(total)): metà \(median(users.map(\.half))) · tre quarti \(median(users.map(\.threeQuarters))) · completo \(median(users.map(\.complete))) · dopo un anno: \(users.map(\.found).sorted()[users.count / 2]) cose")
    print("   regali nel primo mese: \(users.map(\.firstMonthGifts).sorted()[users.count / 2]) · giorni di studio con tutto già trovato (in attesa di un compagno): \(users.map(\.emptyDays).sorted()[users.count / 2])")
}
