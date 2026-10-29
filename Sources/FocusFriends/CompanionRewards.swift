import Foundation

/// I compagni si sbloccano studiando: il primo lo scegli tu, il secondo arriva a 20 «focus pieni» e il terzo a 50.
/// Un focus pieno sono 50 minuti di studio (come una pianta adulta del giardino): contano tutti i minuti,
/// anche quelli dei focus interrotti, e un timer da 5 minuti non sblocca niente più in fretta.
/// Solo Foundation: non conosce personaggi né finestre, lavora su identificatori (con prove).
enum CompanionRewards {
    /// I minuti di studio che fanno un «focus pieno».
    static let minutesPerFocus = 50
    /// Quanti focus pieni servono, per posizione: il primo è libero, il secondo 20, il terzo 50.
    static let thresholds = [0, 20, 50]

    /// Quanti focus pieni sono nei secondi di studio dati.
    static func focuses(totalSeconds: Int) -> Int {
        max(0, totalSeconds) / (minutesPerFocus * 60)
    }

    /// I focus che servono per la posizione `position` (dopo il terzo: altri 50 per ognuno).
    static func threshold(at position: Int) -> Int {
        if position < 0 { return 0 }
        if position < thresholds.count { return thresholds[position] }
        return (thresholds.last ?? 0) + (position - thresholds.count + 1) * 50
    }

    /// L'ordine di sblocco: prima quello scelto, poi gli altri come stanno nel menu.
    static func order(first: String?, all: [String]) -> [String] {
        guard let first, all.contains(first) else { return all }
        return [first] + all.filter { $0 != first }
    }

    /// I compagni meritati con `focuses` focus pieni.
    static func earned(first: String?, all: [String], focuses: Int) -> Set<String> {
        var result: Set<String> = []
        for (position, id) in order(first: first, all: all).enumerated() where focuses >= threshold(at: position) {
            result.insert(id)
        }
        return result
    }

    /// Quanti focus pieni servono per sbloccare `id` (0 se è il primo o non c'è).
    static func need(for id: String, first: String?, all: [String]) -> Int {
        guard let position = order(first: first, all: all).firstIndex(of: id) else { return 0 }
        return threshold(at: position)
    }
}

/// Gli avatar della pagina «Avatar» del menu, nell'ordine in cui si sbloccano (prima il primo scelto), e i testi che dicono quanto manca:
/// chi non è ancora sbloccato resta senza nome (si vede solo una sagoma sfocata), quindi i testi non lo nominano mai.
/// Solo Foundation: lavora su identificatori (con prove).
enum AvatarRoster {
    struct Entry: Equatable {
        let id: String
        /// Quanti focus pieni servono per sbloccarlo (0 = fin dall'inizio).
        let need: Int
        let isUnlocked: Bool
    }

    /// Al posto del nome di un compagno che non c'è ancora.
    static let hiddenName = "???"

    /// Gli avatar nell'ordine di sblocco; `isUnlocked` dice se uno c'è già (il profilo: conta anche la modalità sviluppatore).
    static func entries(first: String?, all: [String], isUnlocked: (String) -> Bool) -> [Entry] {
        CompanionRewards.order(first: first, all: all).map {
            Entry(id: $0, need: CompanionRewards.need(for: $0, first: first, all: all), isUnlocked: isUnlocked($0))
        }
    }

    /// Il prossimo da sbloccare: il primo bloccato nell'ordine (è anche quello che chiede meno focus).
    static func next(in entries: [Entry]) -> Entry? {
        entries.first { !$0.isUnlocked }
    }

    /// Quanti focus pieni mancano (almeno uno: se sono già abbastanza, si sbloccherà al prossimo controllo).
    static func remaining(need: Int, have: Int) -> Int {
        max(need - have, 1)
    }

    /// «ancora 18 focus pieni», «ancora 1 focus pieno».
    static func remainingText(need: Int, have: Int) -> String {
        let rest = remaining(need: need, have: have)
        return rest == 1 ? "ancora 1 focus pieno" : "ancora \(rest) focus pieni"
    }

    /// «circa 15 h»: lo studio che manca, in ore (almeno una).
    static func hoursText(need: Int, have: Int) -> String {
        let minutes = remaining(need: need, have: have) * CompanionRewards.minutesPerFocus
        return "circa \(max(Int((Double(minutes) / 60).rounded()), 1)) h"
    }

    /// Quanta strada è fatta, da 0 a 1.
    static func progress(need: Int, have: Int) -> Double {
        need > 0 ? min(max(Double(have) / Double(need), 0), 1) : 1
    }

    /// Sotto la riga «Avatar» del menu: «Prossimo compagno: ancora 18 focus pieni».
    static func nextLine(need: Int, have: Int) -> String {
        "Prossimo compagno: \(remainingText(need: need, have: have))"
    }

    /// «2 con te · 2 da sbloccare».
    static func countLine(unlocked: Int, locked: Int) -> String {
        locked > 0 ? "\(unlocked) con te · \(locked) da sbloccare" : "\(unlocked) con te"
    }
}
