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
