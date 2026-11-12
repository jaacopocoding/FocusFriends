// Disegna fuori schermo la finestra delle statistiche vera dell'app (DashboardView) in un PNG, con un anno di sessioni inventate in una cartella
// temporanea (i dati veri non si toccano), per le immagini della guida e del README.
// Si lancia da tools/banchi/render-statistiche.sh: render <cartella dei dati> <file.png> <oggi|settimana|mese|anno> [materia scelta] [x y del mouse]
import AppKit

@main
struct Render {
    static func main() {
        _ = NSApplication.shared
        let args = CommandLine.arguments
        let data = URL(fileURLWithPath: args[1])
        let out = args[2]
        let kind: PeriodKind = ["oggi": .day, "settimana": .week, "mese": .month, "anno": .year][args[3]] ?? .week
        let chosen = args.count > 4 && !args[4].isEmpty ? args[4] : nil
        let mouse = args.count > 6 ? NSPoint(x: Double(args[5])!, y: Double(args[6])!) : nil

        var calendar = StudyPeriod.calendar()
        calendar.timeZone = .current
        // «adesso»: un venerdì sera di novembre
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 19, minute: 30))!
        let log = SessionLog(directory: data, now: { now })
        if log.sessions.isEmpty { fill(log, until: now, calendar: calendar) }

        let view = DashboardView(log: log, now: { now })
        view.select(kind)
        if let chosen { view.chooseSubject(chosen) }
        if let mouse { view.pageHovered(at: mouse) }
        view.layoutSubtreeIfNeeded()
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
        print(args[3], view.bounds.size, rep.pixelsWide, "×", rep.pixelsHigh)
    }

    /// Un anno di studio inventato, sempre uguale (un generatore con il seme fisso): più fitto in autunno, con qualche giorno di vacanza.
    static func fill(_ log: SessionLog, until now: Date, calendar: Calendar) {
        var rng = Seeded(seed: 7)
        let subjects = ["Anatomia", "Fisiologia", "Biochimica", "Istologia"]
        let weights = [5, 4, 3, 1]
        let today = calendar.startOfDay(for: now)
        let first = calendar.date(from: DateComponents(year: 2026, month: 1, day: 7))!
        var day = first
        while day <= today {
            let month = calendar.component(.month, from: day)
            let weekday = calendar.component(.weekday, from: day)   // 1 = domenica
            let isToday = day == today
            let busy = month >= 9 ? 0.86 : (month == 8 ? 0.15 : 0.62)
            let weekend = weekday == 1 || weekday == 7
            if isToday || Double.random(in: 0..<1, using: &rng) < (weekend ? busy * 0.35 : busy) {
                let count = isToday ? 3 : Int.random(in: 1...(month >= 9 ? 5 : 3), using: &rng)
                var start = calendar.date(byAdding: .minute, value: Int.random(in: 8 * 60 + 30...10 * 60, using: &rng), to: day)!
                for _ in 0..<count {
                    let roll = Int.random(in: 0..<weights.reduce(0, +), using: &rng)
                    var acc = 0
                    let subject = subjects[weights.firstIndex { acc += $0; return roll < acc }!]
                    let planned = [30, 50, 50][Int.random(in: 0..<3, using: &rng)]
                    let completed = Double.random(in: 0..<1, using: &rng) < 0.9
                    let seconds = completed ? planned * 60 : Int.random(in: 10...(planned - 5), using: &rng) * 60
                    if isToday && start.addingTimeInterval(Double(seconds)) > now { break }
                    if let session = log.add(start: start, seconds: seconds, plannedMinutes: planned, completed: completed, subject: subject) {
                        let hour = calendar.component(.hour, from: start)
                        let good = subject == "Anatomia" || hour < 13 ? 0.75 : 0.45
                        let r = Double.random(in: 0..<1, using: &rng)
                        let rating: FocusRating? = r < good ? .good : (r < good + 0.2 ? .soso : (r < 0.97 ? .poor : nil))
                        log.setReflection(id: session.id, rating: rating, note: nil)
                    }
                    start = start.addingTimeInterval(Double(seconds + Int.random(in: 10...70, using: &rng) * 60))
                }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
    }
}

/// Un generatore pseudo-casuale con il seme fisso (SplitMix64): le immagini vengono uguali ogni volta.
struct Seeded: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
