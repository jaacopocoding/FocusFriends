import Foundation

/// La vista «Anno» delle statistiche: una mappa con un quadratino per giorno (come i contributi di GitHub) e l'andamento
/// per settimana, di tutte le materie o di una sola. Si ricava tutto dal registro: niente da salvare.
/// Solo Foundation: si collauda da solo (tests/main.swift) e deve dare gli stessi risultati della versione per Windows.
enum YearStats {
    // MARK: - I giorni della mappa

    /// Fino a quanti secondi di studio un giorno ha il livello 1, 2 e 3 (da 3 ore in su è il 4): meno di 30 minuti, meno di 90, meno di 180.
    /// Le soglie sono fisse, non relative ai tuoi giorni migliori: un giorno da due ore ha lo stesso colore in tutti gli anni.
    static let levelLimits = [30 * 60, 90 * 60, 180 * 60]

    /// Il colore del giorno, da 0 (niente) a 4 (tanto).
    static func level(seconds: Int) -> Int {
        guard seconds > 0 else { return 0 }
        if seconds < levelLimits[0] { return 1 }
        if seconds < levelLimits[1] { return 2 }
        if seconds < levelLimits[2] { return 3 }
        return 4
    }

    struct Day: Equatable {
        var start: Date
        var seconds: Int
        var focusCount: Int
        var level: Int
    }

    /// Un elemento per ogni giorno del periodo (anche senza studio), in ordine. Una sessione va al giorno in cui è iniziata.
    static func days(sessions: [StudySession], period: StudyPeriod, calendar: Calendar = StudyPeriod.calendar()) -> [Day] {
        var seconds: [Date: Int] = [:]
        var focus: [Date: Int] = [:]
        for s in sessions {
            let t = s.startTime(in: calendar)
            guard period.contains(t) else { continue }
            let day = calendar.startOfDay(for: t)
            seconds[day, default: 0] += s.seconds
            focus[day, default: 0] += 1
        }
        var result: [Day] = []
        var cursor = calendar.startOfDay(for: period.start)
        while cursor < period.end {
            let total = seconds[cursor] ?? 0
            result.append(Day(start: cursor, seconds: total, focusCount: focus[cursor] ?? 0, level: level(seconds: total)))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    // MARK: - La griglia

    /// Il lunedì della settimana in cui cade il primo giorno del periodo: da lì parte la prima colonna.
    private static func firstColumnStart(of period: StudyPeriod, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: period.start)?.start ?? calendar.startOfDay(for: period.start)
    }

    /// Dove sta un giorno nella griglia: una colonna per settimana (da lunedì) e una riga per giorno (lunedì = 0).
    static func cell(of day: Date, in period: StudyPeriod, calendar: Calendar = StudyPeriod.calendar()) -> (column: Int, row: Int) {
        let first = firstColumnStart(of: period, calendar: calendar)
        let offset = calendar.dateComponents([.day], from: first, to: calendar.startOfDay(for: day)).day ?? 0
        return (offset / 7, offset % 7)
    }

    /// Quante colonne ha la griglia (53, o 54 in un anno bisestile che comincia di domenica).
    static func columns(of period: StudyPeriod, calendar: Calendar = StudyPeriod.calendar()) -> Int {
        guard let last = calendar.date(byAdding: .day, value: -1, to: period.end) else { return 1 }
        return cell(of: last, in: period, calendar: calendar).column + 1
    }

    struct MonthMark: Equatable {
        /// 1...12
        var month: Int
        var column: Int
    }

    /// In quale colonna comincia ogni mese, per scriverne il nome sopra la griglia.
    static func monthStarts(in period: StudyPeriod, calendar: Calendar = StudyPeriod.calendar()) -> [MonthMark] {
        var marks: [MonthMark] = []
        var cursor = calendar.startOfDay(for: period.start)
        while cursor < period.end {
            let parts = calendar.dateComponents([.month, .day], from: cursor)
            if parts.day == 1 || marks.isEmpty {
                marks.append(MonthMark(month: parts.month ?? 1, column: cell(of: cursor, in: period, calendar: calendar).column))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return marks
    }

    // MARK: - I tre numeri

    struct Highlights: Equatable {
        /// In quanti giorni hai studiato.
        var studiedDays = 0
        /// La serie di giorni di fila più lunga raggiunta nell'anno (con il giorno di ghiaccio, come la serie di oggi).
        var longestStreak = 0
        /// Il giorno con più studio (a pari merito, il primo): `start` è il giorno.
        var bestDay: StudyBucket?
        /// Il mese con più studio (a pari merito, il primo): `start` è il suo primo giorno.
        var bestMonth: StudyBucket?
    }

    static func highlights(sessions: [StudySession], period: StudyPeriod, now: Date, calendar: Calendar = StudyPeriod.calendar()) -> Highlights {
        let all = days(sessions: sessions, period: period, calendar: calendar)
        var result = Highlights()
        let studied = all.filter { $0.seconds > 0 }
        result.studiedDays = studied.count
        if let best = studied.max(by: { $0.seconds != $1.seconds ? $0.seconds < $1.seconds : $0.start > $1.start }) {
            result.bestDay = StudyBucket(start: best.start, seconds: best.seconds)
        }
        var perMonth: [Int: Int] = [:]
        var monthStart: [Int: Date] = [:]
        for day in studied {
            let month = calendar.component(.month, from: day.start)
            perMonth[month, default: 0] += day.seconds
            if monthStart[month] == nil {
                monthStart[month] = calendar.dateInterval(of: .month, for: day.start)?.start ?? day.start
            }
        }
        if let best = perMonth.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }), let start = monthStart[best.key] {
            result.bestMonth = StudyBucket(start: start, seconds: best.value)
        }
        let streak = StudyStreak.analyze(sessions: sessions, now: now, calendar: calendar)
        result.longestStreak = streak.perDay.filter { period.contains($0.key) }.map { $0.value }.max() ?? 0
        return result
    }

    // MARK: - L'andamento per settimana

    /// Quante materie al massimo si possono scegliere per l'andamento (oltre a «Tutte»).
    static let maxTrendSubjects = 5
    /// Con meno settimane con studio di queste l'andamento non si mostra: non c'è un andamento da vedere.
    static let minimumTrendWeeks = 4

    /// Le materie tra cui scegliere (la scrittura più recente, le più studiate dell'anno), senza «Senza materia». Con meno di due
    /// materie non c'è niente da scegliere: elenco vuoto.
    static func trendSubjects(of summary: StudySummary) -> [String] {
        let named = summary.bySubject.filter { $0.subject != Subject.none }.map { $0.subject }
        return named.count < 2 ? [] : Array(named.prefix(maxTrendSubjects))
    }

    /// Le settimane (da lunedì) del periodo fino a `through`, con i secondi di studio di una materia (le scritture diverse della stessa
    /// materia contano insieme) o di tutte (`subject` nil). La prima e l'ultima settimana possono essere tagliate dai bordi dell'anno.
    static func weeklyTrend(sessions: [StudySession], period: StudyPeriod, subject: String?, through: Date,
                            calendar: Calendar = StudyPeriod.calendar()) -> [StudyBucket] {
        let key = subject.map { Subject.key($0) }
        let wanted = sessions.filter { s in
            guard period.contains(s.startTime(in: calendar)) else { return false }
            guard let key else { return true }
            return s.subject.map { Subject.key($0) == key } ?? false
        }
        let limit = min(period.end, through)
        var buckets: [StudyBucket] = []
        var cursor = firstColumnStart(of: period, calendar: calendar)
        while cursor < limit {
            let next = calendar.date(byAdding: .day, value: 7, to: cursor) ?? limit
            let seconds = wanted.filter {
                let t = $0.startTime(in: calendar)
                return t >= cursor && t < next
            }.reduce(0) { $0 + $1.seconds }
            buckets.append(StudyBucket(start: cursor, seconds: seconds))
            cursor = next
        }
        return buckets
    }

    /// Ha senso mostrare l'andamento? (almeno `minimumTrendWeeks` settimane con studio)
    static func showsTrend(_ weeks: [StudyBucket]) -> Bool {
        weeks.filter { $0.seconds > 0 }.count >= minimumTrendWeeks
    }
}
