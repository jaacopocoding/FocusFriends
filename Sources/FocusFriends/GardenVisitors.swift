import Foundation

/// La fascia della giornata (sull'orologio): decide quali ospiti possono venire.
enum GardenDaySlot: String, CaseIterable {
    case morning, day, evening, night

    /// 6–10 mattina, 10–17 giorno, 17–21 sera, il resto notte.
    static func of(hour: Double) -> GardenDaySlot {
        switch hour {
        case 6..<10: return .morning
        case 10..<17: return .day
        case 17..<21: return .evening
        default: return .night
        }
    }
}

/// Un angolo che attira un ospite raro, e la cosa dell'angolo vicino a cui si ferma.
struct GardenVisitorHaunt: Equatable {
    let corner: String
    let item: String
}

/// Un animaletto che passa a trovarti sull'isola. L'immagine è `assets/giardino/visitatore_<id>.png`.
struct GardenVisitor: Equatable {
    let id: String
    /// Col suo articolo: «Il riccio», «L'anatroccolo».
    let name: String
    let feminine: Bool
    /// I comuni vengono se c'è una di queste cose sull'isola…
    let items: [String]
    /// …i rari se si è formato uno di questi angoli.
    let haunts: [GardenVisitorHaunt]
    let seasons: Set<Season>
    let slots: Set<GardenDaySlot>
    /// Quanto è alto nel giardino (unità della scena, come gli oggetti), e quanto è probabile fra quelli che possono venire.
    let height: Double
    let weight: Double

    var isRare: Bool { items.isEmpty }
    var resource: String { "giardino_visitatore_" + id }
    /// «venuto» o «venuta».
    var came: String { feminine ? "venuta" : "venuto" }
}

/// Chi viene a trovarti e perché. Solo Foundation e con prove (tests/main.swift).
enum GardenVisitors {
    private static let allSeasons = Set(Season.allCases)
    private static let notWinter: Set<Season> = [.spring, .summer, .autumn]

    /// Le cose degli animali che attirano qualcuno stanno ognuna sulla sua isola (`GardenItem.island`): le ultime voci di alcuni ospiti sono per Pianty (l'aiuola e
    /// l'annaffiatoio) e per Gattino (il cesto con cuscino e il tiragraffi), che altrimenti avrebbero una specie sola in tutto l'anno. Si aggiungono in coda: chi aveva
    /// già un motivo per venire lo ha ancora, e il primo motivo che si trova resta quello di prima.
    static let all: [GardenVisitor] = [
        GardenVisitor(id: "pettirosso", name: "Il pettirosso", feminine: false, items: ["bagnetto", "casetta-uccelli"], haunts: [],
                      seasons: allSeasons, slots: [.morning, .day, .evening], height: 50, weight: 1),
        GardenVisitor(id: "cinciallegra", name: "La cinciallegra", feminine: true, items: ["casetta-uccelli", "girasole"], haunts: [],
                      seasons: allSeasons, slots: [.morning, .day], height: 46, weight: 1),
        GardenVisitor(id: "coniglio", name: "Il coniglio", feminine: false, items: ["erba-alta", "trifoglio", "aiuola"], haunts: [],
                      seasons: notWinter, slots: [.morning, .evening], height: 62, weight: 1),
        GardenVisitor(id: "riccio", name: "Il riccio", feminine: false, items: ["funghi", "felci", "cesto-cuscino"], haunts: [],
                      seasons: notWinter, slots: [.evening, .night], height: 52, weight: 1),
        GardenVisitor(id: "rana", name: "La rana", feminine: true, items: ["bagnetto", "ponticello", "annaffiatoio"], haunts: [],
                      seasons: [.spring, .summer], slots: [.evening], height: 36, weight: 1),
        GardenVisitor(id: "anatroccolo", name: "L'anatroccolo", feminine: false, items: ["ponticello", "bagnetto"], haunts: [],
                      seasons: [.spring], slots: [.morning, .day], height: 42, weight: 1),
        GardenVisitor(id: "lucertola", name: "La lucertola", feminine: true, items: ["panchina", "tunnel"], haunts: [],
                      seasons: [.summer], slots: [.day], height: 30, weight: 1),
        GardenVisitor(id: "tartaruga", name: "La tartaruga", feminine: true, items: ["sdraio", "picnic"], haunts: [],
                      seasons: [.spring, .summer], slots: [.day], height: 40, weight: 1),
        GardenVisitor(id: "topolino", name: "Il topolino", feminine: false, items: ["cesto-carote", "picnic"], haunts: [],
                      seasons: [.autumn, .winter], slots: [.evening], height: 30, weight: 1),
        GardenVisitor(id: "scoiattolo", name: "Lo scoiattolo", feminine: false, items: ["altalena", "amaca", "tiragraffi"], haunts: [],
                      seasons: [.spring, .autumn], slots: [.morning, .day], height: 66, weight: 1),
        GardenVisitor(id: "civetta", name: "La civetta", feminine: true, items: [], haunts: [GardenVisitorHaunt(corner: "lettura", item: "panchina")],
                      seasons: allSeasons, slots: [.night], height: 60, weight: 0.4),
        GardenVisitor(id: "volpe", name: "La volpe", feminine: true, items: [],
                      haunts: [GardenVisitorHaunt(corner: "te", item: "tavolino"), GardenVisitorHaunt(corner: "festa", item: "picnic")],
                      seasons: allSeasons, slots: [.evening, .night], height: 86, weight: 0.4),
    ]

    static func visitor(withID id: String) -> GardenVisitor? { all.first { $0.id == id } }

    /// Chi potrebbe venire adesso e vicino a quale copia si fermerebbe, con il motivo: una cosa (`item`) o un angolo (`corner`).
    struct Attraction: Equatable {
        let visitor: GardenVisitor
        let placement: GardenPlacement
        /// La cosa che l'ha attirato (per i comuni), o l'angolo (per i rari).
        let item: String
        let corner: String?
    }

    /// Fra tutti gli ospiti, quelli che questa stagione e a quest'ora possono venire e hanno qualcosa che li attira sull'isola. Un comune guarda le
    /// sue cose nell'ordine in cui le elenca, e fra le copie prende la prima; un raro guarda i suoi angoli.
    static func attractions(placements: [GardenPlacement], formedCorners: [String: [UUID]], season: Season, slot: GardenDaySlot) -> [Attraction] {
        var result: [Attraction] = []
        for visitor in all where visitor.seasons.contains(season) && visitor.slots.contains(slot) {
            if visitor.isRare {
                for haunt in visitor.haunts {
                    guard let members = formedCorners[haunt.corner],
                          let placement = placements.first(where: { members.contains($0.id) && $0.item == haunt.item }) else { continue }
                    result.append(Attraction(visitor: visitor, placement: placement, item: haunt.item, corner: haunt.corner))
                    break
                }
            } else {
                for item in visitor.items {
                    guard let placement = placements.first(where: { $0.item == item }) else { continue }
                    result.append(Attraction(visitor: visitor, placement: placement, item: item, corner: nil))
                    break
                }
            }
        }
        return result
    }

    /// Quanto spesso, nelle fasce in cui qualcuno potrebbe venire, viene davvero (le altre volte è una giornata tranquilla).
    static let presenceChance = 0.8

    private static func unit(_ text: String) -> Double {
        Double(GardenDrops.mixedHash(text)) / 4_294_967_296
    }

    /// Chi viene in questa fascia di questo giorno (`day` come «2026-10-26»), o nessuno. Dipende solo dal giorno, dalla fascia e da cosa c'è sull'isola:
    /// aprendo il giardino due volte nella stessa fascia si trova lo stesso ospite.
    static func arrival(day: String, slot: GardenDaySlot, placements: [GardenPlacement], formedCorners: [String: [UUID]], season: Season) -> Attraction? {
        let candidates = attractions(placements: placements, formedCorners: formedCorners, season: season, slot: slot)
        guard !candidates.isEmpty, unit("ospite-presenza-\(day)-\(slot.rawValue)") < presenceChance else { return nil }
        let total = candidates.reduce(0) { $0 + $1.visitor.weight }
        let draw = unit("ospite-scelta-\(day)-\(slot.rawValue)") * total
        var sum = 0.0
        for candidate in candidates {
            sum += candidate.visitor.weight
            if draw < sum { return candidate }
        }
        return candidates.last
    }

    /// Dove entra: la tessera libera sul bordo dell'isola da cui la strada fino a `goal` è più vicina a `ideal` passi (né troppo corta né troppo lunga), e
    /// la strada (la prima tessera è quella d'ingresso). Nil se non c'è modo di arrivare.
    static func entryRoute(to goal: GardenTile, size: Int, occupied: Set<GardenTile>, ideal: Int = 7, limit: Int = 24) -> [GardenTile]? {
        var best: [GardenTile]?
        for row in 0..<size {
            for col in 0..<size where col == 0 || row == 0 || col == size - 1 || row == size - 1 {
                let entry = GardenTile(col: col, row: row)
                guard GardenLayout.isWalkable(entry, size: size, occupied: occupied),
                      let steps = GardenCompanions.route(from: entry, to: goal, size: size, occupied: occupied, limit: limit) else { continue }
                let path = [entry] + steps
                if best == nil || abs(path.count - ideal) < abs((best?.count ?? 0) - ideal) { best = path }
            }
        }
        return best
    }

    /// La riga del diario per una specie: cosa l'ha portata qui (il nome della cosa, o dell'angolo).
    static func reasonText(item: String, corner: String?) -> String {
        if let corner, let found = GardenCorners.corner(withID: corner) { return found.name }
        return GardenCatalog.item(withID: item)?.name ?? item
    }
}
