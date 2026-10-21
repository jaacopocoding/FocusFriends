import Foundation

/// Le frasi «di contesto» del compagno: il saluto di quando si avvia l'app o si torna dallo sleep, i numeri dello studio detti a voce
/// (il riepilogo della settimana, le frasi «quando rendi meglio») e i traguardi (giorni di fila, focus, ore, anni insieme).
/// Tutto si ricava dal registro e dall'ora: niente da salvare, tranne quale riepilogo della settimana è già stato detto.
/// Italiano senza genere (niente «bentornato» o «contento» riferiti a chi studia). Solo Foundation: si collauda da solo (tests/main.swift).
enum Remarks {
    /// Quello che serve a sapere come far parlare il compagno adesso.
    struct Context {
        var now: Date
        var calendar: Calendar
        var name: String?
        var sessions: [StudySession]
        /// Le cose da fare ancora aperte.
        var openTodoCount = 0
        /// La frase sulle scadenze di oggi o di domani (`ToDoReminder.message`), se c'è.
        var due: String?

        init(now: Date, calendar: Calendar = StudyPeriod.calendar(), name: String?, sessions: [StudySession], openTodoCount: Int = 0, due: String? = nil) {
            self.now = now
            self.calendar = calendar
            self.name = name
            self.sessions = sessions
            self.openTodoCount = openTodoCount
            self.due = due
        }
    }

    /// Una frase, e se dice già le scadenze (allora non serve ripeterle subito dopo).
    struct Remark: Equatable {
        var text: String
        var coversReminder = false
    }

    enum DayPart {
        case morning, afternoon, evening, night
    }

    /// 5–12 mattina, 12–18 pomeriggio, 18–23 sera, il resto notte.
    static func dayPart(hour: Int) -> DayPart {
        switch hour {
        case 5..<12: return .morning
        case 12..<18: return .afternoon
        case 18..<23: return .evening
        default: return .night
        }
    }

    // MARK: - Saluti

    private static func studied(on day: Date, in ctx: Context) -> Int {
        let period = StudyPeriod.containing(day, kind: .day, calendar: ctx.calendar)
        return StudyStats.summary(sessions: ctx.sessions, period: period, calendar: ctx.calendar).totalSeconds
    }

    /// «cosa» al singolare o al plurale: «1 cosa da fare», «3 cose da fare».
    private static func todoLine(_ count: Int) -> String {
        count == 1 ? "Hai 1 cosa da fare." : "Hai \(count) cose da fare."
    }

    /// Il saluto di quando si avvia l'app. `variant` sceglie tra le frasi possibili (così si prova sempre lo stesso risultato).
    static func launchGreeting(_ ctx: Context, variant: Int) -> Remark {
        let hour = ctx.calendar.component(.hour, from: ctx.now)
        let part = dayPart(hour: hour)
        let weekday = ctx.calendar.component(.weekday, from: ctx.now)          // 1 = domenica
        let name = ctx.name

        if part == .night {
            let who = name.map { "\($0), è tardi" } ?? "È tardi"
            let lines = ["\(who). Un ultimo focus e poi a dormire?", "\(who): la testa ha bisogno di riposo, non solo di studio."]
            return Remark(text: lines[positive(variant, lines.count)])
        }
        let hello: String
        switch part {
        case .morning: hello = weekday == 1 ? "Buona domenica" : "Buongiorno"
        case .afternoon: hello = weekday == 1 ? "Buona domenica" : "Buon pomeriggio"
        default: hello = "Buonasera"
        }
        let head = name.map { "\(hello), \($0)!" } ?? "\(hello)!"

        // Se oggi o domani scade qualcosa, è la prima cosa da dire.
        if let due = ctx.due { return Remark(text: "\(head) \(due)", coversReminder: true) }

        var lines: [String] = []
        let todaySeconds = studied(on: ctx.now, in: ctx)
        if let yesterday = ctx.calendar.date(byAdding: .day, value: -1, to: ctx.now), part != .evening {
            let seconds = studied(on: yesterday, in: ctx)
            if seconds >= 60 && todaySeconds == 0 { lines.append("Ieri hai studiato \(StudyStats.duration(seconds: seconds)): si riparte?") }
        }
        if todaySeconds >= 60 { lines.append("Oggi hai già studiato \(StudyStats.duration(seconds: todaySeconds)).") }
        let streak = StudyStreak.analyze(sessions: ctx.sessions, now: ctx.now, calendar: ctx.calendar)
        if streak.days >= 2 { lines.append("Sei a \(streak.days) giorni di fila.") }
        if ctx.openTodoCount > 0 { lines.append(todoLine(ctx.openTodoCount)) }
        if lines.isEmpty { lines.append("Si comincia quando vuoi.") }
        return Remark(text: "\(head) \(lines[positive(variant, lines.count)])")
    }

    /// Il saluto di quando si torna dallo sleep (`away` = quanto si è stati via). Niente se è passato poco: `nil`.
    static func wakeGreeting(_ ctx: Context, away: TimeInterval, variant: Int) -> Remark? {
        guard away >= minimumAway else { return nil }
        let hello = ["Rieccoti!", "Eccoti di nuovo!", "Ti stavo aspettando!"][positive(variant, 3)]
        if let due = ctx.due { return Remark(text: "\(hello) \(due)", coversReminder: true) }
        var lines: [String] = []
        let todaySeconds = studied(on: ctx.now, in: ctx)
        if todaySeconds >= 60 { lines.append("Oggi sei a \(StudyStats.duration(seconds: todaySeconds)).") }
        if ctx.openTodoCount > 0 { lines.append(todoLine(ctx.openTodoCount)) }
        return Remark(text: lines.isEmpty ? hello : "\(hello) \(lines[positive(variant / 3, lines.count)])")
    }

    /// Meno di un'ora di sleep non merita un saluto.
    static let minimumAway: TimeInterval = 3600

    // MARK: - I numeri a voce

    /// Il riepilogo della settimana appena passata, da dire il lunedì (fino al mercoledì, se non l'hai ancora sentito). `key` identifica la settimana,
    /// per non dirlo due volte. `nil` se non è un giorno adatto o la settimana scorsa non hai studiato.
    static func weeklyRecap(_ ctx: Context) -> (key: String, text: String)? {
        let weekday = ctx.calendar.component(.weekday, from: ctx.now)
        guard [2, 3, 4].contains(weekday) else { return nil }
        let thisWeek = StudyPeriod.containing(ctx.now, kind: .week, calendar: ctx.calendar)
        let last = thisWeek.shifted(by: -1, calendar: ctx.calendar)
        let summary = StudyStats.summary(sessions: ctx.sessions, period: last, calendar: ctx.calendar)
        guard summary.totalSeconds >= 60 else { return nil }
        var perDay: [Date: Int] = [:]
        for s in summary.sessions { perDay[ctx.calendar.startOfDay(for: s.startTime(in: ctx.calendar)), default: 0] += s.seconds }
        let days = perDay.count
        let focus = summary.focusCount == 1 ? "1 focus" : "\(summary.focusCount) focus"
        var text = "Settimana scorsa: \(StudyStats.duration(seconds: summary.totalSeconds)) in \(days == 1 ? "1 giorno" : "\(days) giorni"), \(focus)."
        if days > 1, let best = perDay.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }) {
            let name = StudyStats.weekdayName(ctx.calendar.component(.weekday, from: best.key))
            text += " Il giorno più forte: \(name) (\(StudyStats.duration(seconds: best.value)))."
        }
        return (ToDoDay.string(for: last.start, calendar: ctx.calendar), text)
    }

    /// Una delle frasi «quando rendi meglio» delle statistiche, o `nil` se non ce ne sono ancora.
    static func insight(_ ctx: Context, variant: Int) -> String? {
        let lines = StudyStats.insights(sessions: ctx.sessions, calendar: ctx.calendar)
        return lines.isEmpty ? nil : lines[positive(variant, lines.count)]
    }

    // MARK: - Traguardi

    static let streakMilestones = [3, 7, 14, 30, 60, 100]
    static let focusMilestones = [10, 25, 50, 100, 250, 500, 1000]
    static let hourMilestones = [10, 25, 50, 100, 250, 500]

    /// Una frase se con l'ultimo focus si è passato un traguardo: giorni di fila, numero di focus, ore di studio, o «un mese insieme».
    /// `before` sono le sessioni senza quella appena finita, `after` con lei. Una sola frase (la prima trovata, in quest'ordine).
    static func milestone(before: [StudySession], after: [StudySession], now: Date, calendar: Calendar = StudyPeriod.calendar()) -> String? {
        let streakBefore = StudyStreak.analyze(sessions: before, now: now, calendar: calendar).days
        let streakAfter = StudyStreak.analyze(sessions: after, now: now, calendar: calendar).days
        if let m = streakMilestones.last(where: { streakBefore < $0 && streakAfter >= $0 }) {
            switch m {
            case 3: return "Tre giorni di fila!"
            case 7: return "Sette giorni di fila! Una settimana intera."
            case 14: return "Due settimane di fila: che costanza!"
            case 30: return "Trenta giorni di fila! Un mese intero."
            case 60: return "Sessanta giorni di fila: incredibile."
            default: return "Cento giorni di fila!"
            }
        }
        if let m = focusMilestones.last(where: { before.count < $0 && after.count >= $0 }) {
            return m == 10 ? "10 focus insieme!" : "\(m) focus: un traguardo tondo!"
        }
        let hoursBefore = before.reduce(0) { $0 + $1.seconds } / 3600
        let hoursAfter = after.reduce(0) { $0 + $1.seconds } / 3600
        if let m = hourMilestones.last(where: { hoursBefore < $0 && hoursAfter >= $0 }) {
            return m >= 100 ? "\(m) ore passate insieme a me. Grazie!" : "\(m) ore di studio insieme!"
        }
        // «Oggi è un mese che studiamo insieme»: lo stesso giorno del mese del primo focus, la prima volta che si studia oggi.
        if let first = after.map({ $0.startTime(in: calendar) }).min() {
            let today = calendar.startOfDay(for: now)
            let studiedBefore = before.contains { calendar.startOfDay(for: $0.startTime(in: calendar)) == today }
            // I mesi si contano sul calendario (non con `dateComponents`, che da un 31 gennaio al 28 febbraio dice zero).
            let months = (calendar.component(.year, from: today) * 12 + calendar.component(.month, from: today))
                - (calendar.component(.year, from: first) * 12 + calendar.component(.month, from: first))
            if !studiedBefore, months >= 1, anniversaryDay(of: first, in: today, calendar: calendar) {
                if months == 1 { return "Oggi è un mese che studiamo insieme." }
                if months == 12 { return "Oggi è un anno che studiamo insieme!" }
                if months % 12 == 0 { return "Oggi sono \(months / 12) anni che studiamo insieme!" }
                return "Oggi sono \(months) mesi che studiamo insieme."
            }
        }
        return nil
    }

    /// Oggi è «lo stesso giorno del mese» di `first` (se quel giorno nel mese corrente non c'è, l'ultimo del mese).
    private static func anniversaryDay(of first: Date, in today: Date, calendar: Calendar) -> Bool {
        let wanted = calendar.component(.day, from: first)
        let length = calendar.range(of: .day, in: .month, for: today)?.count ?? 31
        return calendar.component(.day, from: today) == min(wanted, length)
    }

    // MARK: - Aiuti

    /// Un indice valido anche per varianti negative o più grandi del numero di frasi.
    private static func positive(_ variant: Int, _ count: Int) -> Int {
        ((variant % count) + count) % count
    }
}
