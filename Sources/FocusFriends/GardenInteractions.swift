import Foundation

/// Un compagno che usa una cosa del giardino: il gattino dorme nel cesto con cuscino, il porcellino fa capolino dal tunnel, Ciccio fa il bagno nel
/// bagnetto. Ogni interazione è un disegno solo, la cosa con il compagno dentro (`assets/interazioni/<compagno>-<cosa>.png`, ritagliati da
/// tools/cutout_interazioni.py dalle tavole fatte con Gemini): quando il compagno la usa, lui sparisce e il disegno della cosa diventa quello.
/// Solo Foundation e con prove; Windows ha la stessa tabella (`windows/src/core/gardenInteractions.ts`).
struct GardenInteraction: Equatable {
    /// Cosa si vede in più mentre la usa: niente, le «z» di chi dorme, gli schizzi d'acqua.
    enum Effect: String { case none, sleep, splash }

    let pet: String
    let item: String
    let effect: Effect
    /// Dove sta la cosa nel disegno della scena (lo trova tools/cutout_interazioni.py): quanto è più grande del suo disegno di sempre, e il suo angolo in
    /// alto a sinistra, in pixel della scena. Così la scena si mette proprio sopra la cosa (l'animale che sporge sporge attorno).
    let scale: Double
    let x: Double
    let y: Double

    /// Il nome dell'immagine della scena nell'app: `interazioni_<compagno>-<cosa>`.
    var resource: String { "interazioni_\(pet)-\(item)" }

    /// Quanti secondi ci sta: chi dorme di più.
    var duration: ClosedRange<Double> { effect == .sleep ? 20...35 : 12...20 }
}

enum GardenInteractions {
    private static func scene(_ pet: String, _ item: String, _ effect: GardenInteraction.Effect = .none, scale: Double, x: Double, y: Double) -> GardenInteraction {
        GardenInteraction(pet: pet, item: item, effect: effect, scale: scale, x: x, y: y)
    }

    /// Le interazioni, per compagno (le misure da tools/cutout_interazioni.py; l'amaca e l'altalena sono ritagliate sul loro riquadro).
    static let all: [GardenInteraction] = [
        scene("gattino", "cesto-cuscino", .sleep, scale: 1.687, x: 0, y: 0),
        scene("gattino", "tiragraffi", scale: 1.489, x: 0, y: 0),
        scene("gattino", "panchina", .sleep, scale: 1.658, x: 0, y: 0),
        scene("gattino", "amaca", .sleep, scale: 1.609, x: 0, y: 0),
        scene("porcellino", "cesto-carote", scale: 1.560, x: 142, y: 0),
        scene("porcellino", "tunnel", scale: 1.660, x: 5, y: 0),
        scene("porcellino", "picnic", scale: 1.930, x: 11, y: 0),
        scene("porcellino", "altalena", scale: 1.306, x: 0, y: 0),
        scene("ciccio", "bagnetto", .splash, scale: 1.215, x: 18, y: 79),
        scene("ciccio", "altalena-uccelli", scale: 1.291, x: 13, y: 0),
        scene("ciccio", "casetta-uccelli", scale: 1.093, x: 4, y: 58),
        scene("ciccio", "girasole", scale: 1.083, x: 28, y: 29),
        scene("riccio", "mucchio-foglie", scale: 1.229, x: 69, y: 0),
        scene("riccio", "cassetta-mele", scale: 1.200, x: 0, y: 0),
        scene("riccio", "tronco-cavo", .sleep, scale: 1.512, x: 0, y: 3),
        scene("riccio", "carriola-ghiande", scale: 1.347, x: 1, y: 5),
        scene("tartaruga", "sasso-sole", .sleep, scale: 1.598, x: 0, y: 32),
        scene("tartaruga", "lattuga", scale: 0.901, x: 0, y: 82),
        scene("tartaruga", "laghetto", scale: 1.518, x: 1, y: 20),
        scene("tartaruga", "rifugio-paglia", .sleep, scale: 1.293, x: 0, y: 0),
        // la scena dell'annaffiatoio è specchiata (Gemini l'aveva girato dall'altra parte): Pianty sta a sinistra
        scene("pianty", "annaffiatoio", .splash, scale: 1.242, x: 171, y: 36),
        scene("pianty", "aiuola", scale: 1.461, x: 0, y: 43),
        scene("pianty", "sdraio", .sleep, scale: 1.499, x: 1, y: 0),
        scene("pianty", "barattolo-lucciole", scale: 0.658, x: 43, y: 71),
    ]

    static func interaction(pet: String, item: String) -> GardenInteraction? { all.first { $0.pet == pet && $0.item == item } }

    /// Una cosa che il compagno potrebbe usare adesso: quale copia, quale scena e la strada fino alla tessera accanto dove si ferma.
    struct Candidate: Equatable {
        let placement: GardenPlacement
        let interaction: GardenInteraction
        let route: [GardenTile]
    }

    /// Le cose dell'isola che questo compagno sa usare, raggiungibili (fino a `limit` passi, fino a una tessera accanto), nell'ordine delle copie; non
    /// quella dell'ultima volta.
    static func candidates(pet: String, placements: [GardenPlacement], from: GardenTile, size: Int, occupied: Set<GardenTile>, last: UUID?,
                           taken: Set<GardenTile> = [], limit: Int = 12) -> [Candidate] {
        var result: [Candidate] = []
        for placement in placements where placement.id != last {
            guard let interaction = interaction(pet: pet, item: placement.item), let item = GardenCatalog.item(withID: placement.item) else { continue }
            let footprint = GardenLayout.tiles(of: item.footprint.applying(turned: placement.turned), at: placement.tile)
            var best: [GardenTile]?
            for tile in GardenCompanions.standingTiles(around: footprint, size: size)
            where GardenLayout.isWalkable(tile, size: size, occupied: occupied) && !taken.contains(tile) {
                guard let way = GardenCompanions.route(from: from, to: tile, size: size, occupied: occupied, limit: limit) else { continue }
                if best == nil || way.count < best!.count { best = way }
            }
            if let way = best { result.append(Candidate(placement: placement, interaction: interaction, route: way)) }
        }
        return result
    }

    /// Sceglie fra le candidate, tutte uguali: `value` da 0 a 1 (il caso lo dà chi chiama, così la scelta si prova uguale su Mac e Windows).
    static func pick(_ candidates: [Candidate], value: Double) -> Candidate? {
        guard !candidates.isEmpty else { return nil }
        return candidates[min(Int(min(max(value, 0), 0.999_999) * Double(candidates.count)), candidates.count - 1)]
    }
}
