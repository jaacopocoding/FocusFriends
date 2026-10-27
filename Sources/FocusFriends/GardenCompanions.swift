import Foundation

/// Una posa che un compagno fa nel giardino. Le immagini sono quelle che ha già (le stesse del compagno sul desktop, `assets/<id>/frame<n>.png`, tutte
/// sulla stessa tela dell'immagine ferma).
enum GardenPose: String, CaseIterable {
    case sleep, eat, popcorn, wings, groom

    /// Quanti fotogrammi al secondo: il sonno è un respiro lento, il resto più vivace.
    var framesPerSecond: Double {
        switch self {
        case .sleep: return 3
        case .eat: return 5
        case .popcorn: return 8
        case .wings: return 8
        case .groom: return 4
        }
    }

    /// Quanti secondi dura, da un minimo a un massimo: ogni volta è diverso.
    var duration: ClosedRange<Double> {
        switch self {
        case .sleep: return 14...24
        case .eat: return 8...13
        case .popcorn: return 6...10
        case .wings: return 7...11
        case .groom: return 8...12
        }
    }
}

/// A chi piace quale angolo: il compagno `pet` va vicino a `item` (una cosa di quell'angolo) e fa la posa. Solo Foundation, con prove.
struct GardenAffinity: Equatable {
    let pet: String
    let corner: String
    let item: String
    let pose: GardenPose
}

enum GardenCompanions {
    /// Cosa fanno i compagni negli angoli: il gattino dorme nel suo e nel salotto e si lecca la zampa all'angolo di lettura, il porcellino mangia nell'orto e al picnic e
    /// saltella a casa sua e alla festa, Ciccio sbatte le ali vicino al bagnetto, alla festa e alla musica del vento. Pianty non ha pose: sta dove sta.
    static let affinities: [GardenAffinity] = [
        GardenAffinity(pet: "gattino", corner: "gatto", item: "casetta-gatto", pose: .sleep),
        GardenAffinity(pet: "gattino", corner: "lettura", item: "panchina", pose: .groom),
        GardenAffinity(pet: "gattino", corner: "salotto", item: "cesto-cuscino", pose: .sleep),
        GardenAffinity(pet: "porcellino", corner: "orto", item: "aiuola", pose: .eat),
        GardenAffinity(pet: "porcellino", corner: "porcellino", item: "casetta-porcellino", pose: .popcorn),
        GardenAffinity(pet: "porcellino", corner: "festa", item: "picnic", pose: .popcorn),
        GardenAffinity(pet: "porcellino", corner: "picnic", item: "picnic", pose: .eat),
        GardenAffinity(pet: "ciccio", corner: "uccelli", item: "bagnetto", pose: .wings),
        GardenAffinity(pet: "ciccio", corner: "festa", item: "bandierine", pose: .wings),
        GardenAffinity(pet: "ciccio", corner: "vento", item: "altalena-uccelli", pose: .wings),
    ]

    /// Che numeri di fotogramma (da 1, come `frame<n>.png`) fanno una posa per un compagno; vuoto se non la fa.
    static func frames(pet: String, pose: GardenPose) -> [Int] {
        let range: ClosedRange<Int>?
        switch (pet, pose) {
        case ("gattino", .eat): range = 8...12
        case ("gattino", .sleep): range = 13...18
        case ("gattino", .groom): range = 19...23
        case ("porcellino", .eat): range = 6...10
        case ("porcellino", .sleep): range = 11...14
        case ("porcellino", .popcorn): range = 15...19
        case ("ciccio", .wings): range = 8...13
        default: range = nil
        }
        return range.map { Array($0) } ?? []
    }

    /// L'immagine (come si chiama nell'app: `<compagno>_frame<n>`) della posa al tempo `time`, o nil se quel compagno non la fa.
    static func resource(pet: String, pose: GardenPose, time: Double) -> String? {
        let numbers = frames(pet: pet, pose: pose)
        guard !numbers.isEmpty else { return nil }
        let step = Int((time * pose.framesPerSecond).rounded(.down))
        return "\(pet)_frame\(numbers[((step % numbers.count) + numbers.count) % numbers.count])"
    }

    /// Dove può stare un compagno per essere «vicino» a una cosa: le tessere attorno alle sue (anche in diagonale) che stanno dentro l'isola, in ordine di
    /// riga e di colonna.
    static func standingTiles(around footprint: [GardenTile], size: Int) -> [GardenTile] {
        let own = Set(footprint)
        var around = Set<GardenTile>()
        for tile in footprint {
            for dc in -1...1 {
                for dr in -1...1 {
                    let near = GardenTile(col: tile.col + dc, row: tile.row + dr)
                    if !own.contains(near) && GardenIsland.contains(near, size: size) { around.insert(near) }
                }
            }
        }
        return around.sorted { ($0.row, $0.col) < ($1.row, $1.col) }
    }

    /// La strada più corta (tessera per tessera, in su, in giù, a destra o a sinistra) per camminare da `from` a `to` senza passare su un oggetto: le
    /// tessere da percorrere, senza quella di partenza e con quella d'arrivo; vuota se già ci si è; nil se non c'è strada (o è più lunga di `limit`).
    static func route(from: GardenTile, to: GardenTile, size: Int, occupied: Set<GardenTile>, limit: Int = 16) -> [GardenTile]? {
        guard GardenLayout.isWalkable(to, size: size, occupied: occupied), GardenLayout.isWalkable(from, size: size, occupied: occupied) else { return nil }
        if from == to { return [] }
        var previous: [GardenTile: GardenTile] = [:]
        var seen: Set<GardenTile> = [from]
        var frontier: [GardenTile] = [from]
        var depth = 0
        while !frontier.isEmpty && depth < limit {
            depth += 1
            var next: [GardenTile] = []
            for tile in frontier {
                for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let step = GardenTile(col: tile.col + dc, row: tile.row + dr)
                    guard !seen.contains(step), GardenLayout.isWalkable(step, size: size, occupied: occupied) else { continue }
                    seen.insert(step)
                    previous[step] = tile
                    if step == to {
                        var path: [GardenTile] = [step]
                        while let before = previous[path[0]], before != from { path.insert(before, at: 0) }
                        return path
                    }
                    next.append(step)
                }
            }
            frontier = next
        }
        return nil
    }
}
