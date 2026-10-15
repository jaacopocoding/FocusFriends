import Foundation

/// La serie di giorni di studio, con un giorno di tolleranza.
///
/// Un giorno senza studio non azzera la serie: la «ghiaccia». Il numero resta fermo, e se il giorno dopo si studia la
/// serie riparte da lì. Due giorni di fila senza studio la azzerano. Il ghiaccio si può usare una volta ogni
/// `freezeInterval` giorni, altrimenti basterebbe studiare a giorni alterni. Si ricava tutto dai giorni di studio.
/// Solo Foundation: si collauda da solo (tests/main.swift).
enum StudyStreak {
    /// Dopo un giorno ghiacciato ne devono passare altrettanti prima di poterne ghiacciare un altro.
    static let freezeInterval = 7

    struct Result: Equatable {
        /// Per ogni giorno con studio: i giorni di fila raggiunti quel giorno (si contano solo i giorni di studio).
        var perDay: [Date: Int]
        /// I giorni di fila a oggi.
        var days: Int
        /// Ieri non si è studiato ma la serie è salva (ghiacciata): studiando oggi continua.
        var isFrozen: Bool
        /// Oggi si è già studiato.
        var studiedToday: Bool
    }

    static func analyze(studyDays: Set<Date>, now: Date, calendar: Calendar = StudyPeriod.calendar()) -> Result {
        let today = calendar.startOfDay(for: now)
        guard let first = studyDays.min() else {
            return Result(perDay: [:], days: 0, isFrozen: false, studiedToday: false)
        }
        let last = max(today, studyDays.max() ?? today)

        var perDay: [Date: Int] = [:]
        var streak = 0
        var frozen = false
        var previousWasStudy = false
        var lastFreeze: Date?
        var day = first
        while day <= last {
            if studyDays.contains(day) {
                streak += 1
                perDay[day] = streak
                previousWasStudy = true
                frozen = false
            } else if day < today {
                // Un giorno passato senza studio: si ghiaccia (una sola volta di fila, e non più di una ogni 7 giorni)
                // oppure la serie finisce.
                let freezeReady = lastFreeze.map {
                    (calendar.dateComponents([.day], from: $0, to: day).day ?? 0) >= freezeInterval
                } ?? true
                if streak > 0 && previousWasStudy && freezeReady {
                    lastFreeze = day
                    frozen = true
                } else {
                    streak = 0
                    frozen = false
                }
                previousWasStudy = false
            }
            // Oggi ancora senza studio: la giornata non è finita, non c'è niente da giudicare.
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return Result(perDay: perDay, days: streak, isFrozen: frozen, studiedToday: studyDays.contains(today))
    }

    static func analyze(sessions: [StudySession], now: Date, calendar: Calendar = StudyPeriod.calendar()) -> Result {
        let days = Set(sessions.map { calendar.startOfDay(for: $0.startTime(in: calendar)) })
        return analyze(studyDays: days, now: now, calendar: calendar)
    }
}

/// I punti del giardino: un punto per ogni ora di studio, ma ogni minuto vale di più se la serie di giorni è lunga.
/// Contano tutti i minuti, anche quelli dei focus interrotti. Si ricavano dal registro, come tutto il resto.
/// Solo Foundation: si collauda da solo (tests/main.swift).
enum GardenPoints {
    /// I minuti pesati che fanno un punto.
    static let minutesPerPoint = 60.0
    /// Da quanti giorni di fila, quanto vale ogni minuto.
    static let multipliers: [(days: Int, factor: Double)] = [(1, 1.0), (3, 1.25), (7, 1.5), (14, 2.0)]

    static func multiplier(forStreak days: Int) -> Double {
        var factor = 1.0
        for step in multipliers where days >= step.days { factor = step.factor }
        return factor
    }

    /// Quanto vale un minuto di studio oggi: se oggi si è già studiato è il valore raggiunto, altrimenti quello
    /// che avrebbe studiando adesso.
    static func multiplierToday(_ streak: StudyStreak.Result) -> Double {
        multiplier(forStreak: streak.studiedToday ? streak.days : streak.days + 1)
    }

    /// I minuti di studio, ognuno moltiplicato per il valore della serie del suo giorno.
    static func weightedMinutes(sessions: [StudySession], now: Date, calendar: Calendar = StudyPeriod.calendar()) -> Double {
        let streak = StudyStreak.analyze(sessions: sessions, now: now, calendar: calendar)
        var perDay: [Date: Double] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.startTime(in: calendar))
            perDay[day, default: 0] += Double(max(session.seconds, 0)) / 60
        }
        return perDay.reduce(0) { total, entry in
            total + entry.value * multiplier(forStreak: streak.perDay[entry.key] ?? 1)
        }
    }

    /// I punti guadagnati in tutto.
    static func earned(sessions: [StudySession], now: Date, calendar: Calendar = StudyPeriod.calendar()) -> Int {
        points(forWeightedMinutes: weightedMinutes(sessions: sessions, now: now, calendar: calendar))
    }

    static func points(forWeightedMinutes minutes: Double) -> Int {
        max(Int(minutes / minutesPerPoint), 0)
    }

    /// Quanto manca al prossimo punto, da 0 a 1 (quanto è già pieno).
    static func progressToNextPoint(weightedMinutes minutes: Double) -> Double {
        max(minutes, 0).truncatingRemainder(dividingBy: minutesPerPoint) / minutesPerPoint
    }

    /// Quanti punti restano: quelli guadagnati meno quelli spesi (mai sotto zero: se si cancellano delle sessioni
    /// gli oggetti sbloccati restano, ma non se ne comprano altri finché non si recupera).
    static func balance(earned: Int, spent: Int) -> Int {
        max(earned - spent, 0)
    }

    /// «1,25», «1,5», «2»: il moltiplicatore come si scrive in italiano.
    static func text(forMultiplier factor: Double) -> String {
        String(format: "%g", factor).replacingOccurrences(of: ".", with: ",")
    }

    /// Una frase per la fine del focus: i punti in più per il giardino, o quanto manca al prossimo.
    /// `before` e `after` sono i minuti pesati prima e dopo il focus; `factor` il valore del minuto di oggi.
    static func finishLine(beforeMinutes before: Double, afterMinutes after: Double, factor: Double) -> String {
        let gained = points(forWeightedMinutes: after) - points(forWeightedMinutes: before)
        let boost = factor > 1 ? " (con la serie ogni minuto vale ×\(text(forMultiplier: factor)))" : ""
        if gained >= 1 {
            return (gained == 1 ? "Un punto in più per il giardino" : "\(gained) punti in più per il giardino") + boost + "."
        }
        let missing = minutesPerPoint - max(after, 0).truncatingRemainder(dividingBy: minutesPerPoint)
        let minutes = max(Int((missing / max(factor, 1)).rounded(.up)), 1)
        return "Il giardino cresce: ancora \(minutes) minuti per il prossimo punto."
    }
}
