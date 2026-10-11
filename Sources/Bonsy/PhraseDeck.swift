import Foundation

/// Un mazzo di frasi: escono tutte, in ordine casuale, prima che una qualsiasi si ripeta.
/// Finito il mazzo se ne rimescola uno nuovo; la prima frase del nuovo mazzo non è mai uguale
/// all'ultima uscita. Se il file delle frasi cambia a metà mazzo, il mazzo si aggiorna: le frasi tolte
/// spariscono e quelle nuove entrano in posizioni a caso, senza far ripetere quelle già uscite.
struct PhraseDeck {
    private var remaining: [String] = []   // ancora da dire in questo giro, nell'ordine in cui usciranno
    private var seen: Set<String> = []     // già dette in questo giro
    private(set) var last: String?

    mutating func draw(from phrases: [String]) -> String? {
        let unique = Array(Set(phrases))
        guard !unique.isEmpty else { return nil }
        let known = Set(unique)

        // Allinea il mazzo al file: via le frasi tolte, dentro quelle nuove (in posizioni a caso).
        remaining = remaining.filter { known.contains($0) }
        seen = seen.filter { known.contains($0) }
        for phrase in known.subtracting(remaining).subtracting(seen) {
            remaining.insert(phrase, at: Int.random(in: 0...remaining.count))
        }

        // Mazzo finito: se ne rimescola uno nuovo.
        if remaining.isEmpty {
            remaining = unique.shuffled()
            seen = []
            if remaining.count > 1, remaining.first == last {
                remaining.swapAt(0, Int.random(in: 1..<remaining.count))
            }
        }

        let next = remaining.removeFirst()
        seen.insert(next)
        last = next
        return next
    }
}
