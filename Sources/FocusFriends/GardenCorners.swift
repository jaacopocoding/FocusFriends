import Foundation

/// Un «angolo» del giardino: certe cose messe vicine fanno qualcosa insieme (il tavolino e la sdraio fanno l'angolo del tè). L'utente non sa
/// quali sono: li scopre spostando gli oggetti, e quando se ne forma uno compaiono le stelline con «Hai sbloccato…».
struct GardenCorner: Equatable {
    /// Di cosa ha bisogno: ogni voce vuole una copia diversa, e tutte devono stare vicine.
    enum Need: Equatable {
        /// Una copia di uno qualunque di questi oggetti.
        case oneOf([String])
        /// Tanti oggetti diversi di questa scheda (quattro fiori tutti diversi).
        case different(GardenCategory, Int)
    }

    let id: String
    /// Come si legge in «Hai sbloccato «…»».
    let name: String
    let needs: [Need]
}

/// Quali angoli ci sono e quando si formano. Solo Foundation e con prove (tests/main.swift); sul Mac fa tutto questo file, su Windows si ripeterà uguale.
enum GardenCorners {
    /// Quanto vicine devono stare le cose di un angolo: ognuna a non più di due tessere da quella «di mezzo» (cioè con al massimo una tessera
    /// libera in mezzo), contando i bordi dell'ingombro. Così non serve metterle proprio attaccate.
    static let reach = 2

    static let all: [GardenCorner] = [
        GardenCorner(id: "te", name: "L'angolo del tè", needs: [.oneOf(["tavolino"]), .oneOf(["sdraio"])]),
        GardenCorner(id: "lettura", name: "L'angolo di lettura", needs: [.oneOf(["panchina"]), .oneOf(["lampione"])]),
        GardenCorner(id: "orto", name: "L'orto", needs: [.oneOf(["aiuola"]), .oneOf(["erbe"]), .oneOf(["annaffiatoio"])]),
        GardenCorner(id: "gatto", name: "L'angolo del gatto", needs: [.oneOf(["casetta-gatto"]), .oneOf(["tiragraffi"]), .oneOf(["cesto-cuscino"])]),
        GardenCorner(id: "porcellino", name: "La casa del porcellino", needs: [.oneOf(["casetta-porcellino"]), .oneOf(["tunnel"]), .oneOf(["cesto-carote"])]),
        GardenCorner(id: "uccelli", name: "L'angolo degli uccelli", needs: [.oneOf(["bagnetto"]), .oneOf(["casetta-uccelli"]), .oneOf(["altalena-uccelli"])]),
        GardenCorner(id: "prato-fiorito", name: "Il prato fiorito", needs: [.different(.flowers, 4)]),
        GardenCorner(id: "bosco", name: "L'angolo del bosco", needs: [.oneOf(["funghi"]), .oneOf(["felci"]), .oneOf(["erba-alta"])]),
        GardenCorner(id: "festa", name: "La festa in giardino", needs: [.oneOf(["bandierine"]), .oneOf(["picnic"]), .oneOf(["tavolino"])]),
        GardenCorner(id: "rose", name: "L'arco delle rose", needs: [.oneOf(["arco-rose"]), .oneOf(["panchina", "ponticello"])]),
        // Due per isola, ognuno con una cosa del suo animale (e quindi solo su quell'isola): Pianty, Porcellino, Ciccio, Gattino.
        GardenCorner(id: "vivaio", name: "Il vivaio", needs: [.oneOf(["vaso-grande"]), .oneOf(["lavanda"]), .oneOf(["tulipani"])]),
        GardenCorner(id: "acqua", name: "L'angolo dell'acqua", needs: [.oneOf(["annaffiatoio"]), .oneOf(["ponticello"]), .oneOf(["felci"])]),
        GardenCorner(id: "picnic", name: "Il picnic", needs: [.oneOf(["picnic"]), .oneOf(["cesto-carote"])]),
        GardenCorner(id: "recinto", name: "Il recinto", needs: [.oneOf(["casetta-porcellino"]), .oneOf(["cancelletto"]), .oneOf(["erba-alta"])]),
        GardenCorner(id: "vento", name: "La musica del vento", needs: [.oneOf(["carillon"]), .oneOf(["altalena-uccelli"])]),
        GardenCorner(id: "bagno-sole", name: "Il bagno al sole", needs: [.oneOf(["bagnetto"]), .oneOf(["sdraio"]), .oneOf(["girasole"])]),
        GardenCorner(id: "salotto", name: "Il salotto del gatto", needs: [.oneOf(["cesto-cuscino"]), .oneOf(["tavolino"]), .oneOf(["lampione"])]),
        GardenCorner(id: "palestra", name: "La palestra del gatto", needs: [.oneOf(["tiragraffi"]), .oneOf(["amaca"])]),
    ]

    static func corner(withID id: String) -> GardenCorner? { all.first { $0.id == id } }

    /// Le tessere che occupa una copia: da quale a quale colonna e riga (compresi gli estremi).
    private static func box(of placement: GardenPlacement) -> (col0: Int, col1: Int, row0: Int, row1: Int)? {
        guard let item = GardenCatalog.item(withID: placement.item) else { return nil }
        let footprint = item.footprint.applying(turned: placement.turned)
        return (placement.col, placement.col + footprint.cols - 1, placement.row, placement.row + footprint.rows - 1)
    }

    /// La distanza fra due copie in tessere (la maggiore tra colonne e righe): 1 se si toccano, 2 se c'è una tessera libera in mezzo,
    /// 0 se sono la stessa. Conta il bordo dell'ingombro, non il centro (oggi ogni cosa sta su una tessera sola: bordo e centro coincidono).
    static func distance(_ a: GardenPlacement, _ b: GardenPlacement) -> Int {
        guard let first = box(of: a), let second = box(of: b) else { return Int.max }
        if a.id == b.id { return 0 }
        let dCol = max(0, max(first.col0 - second.col1, second.col0 - first.col1))
        let dRow = max(0, max(first.row0 - second.row1, second.row0 - first.row1))
        return max(dCol, dRow, 1)
    }

    /// Le copie di `candidates` che soddisfano `needs`, una per voce (le voci non si contendono la stessa copia), o nil se non bastano.
    private static func fulfil(_ needs: [GardenCorner.Need], from candidates: [GardenPlacement]) -> [GardenPlacement]? {
        var used = Set<UUID>()
        var members: [GardenPlacement] = []
        for need in needs {
            switch need {
            case .oneOf(let items):
                guard let found = candidates.first(where: { !used.contains($0.id) && items.contains($0.item) }) else { return nil }
                used.insert(found.id)
                members.append(found)
            case .different(let category, let count):
                var seen = Set<String>()
                var picked: [GardenPlacement] = []
                for candidate in candidates where !used.contains(candidate.id) {
                    guard let item = GardenCatalog.item(withID: candidate.item), item.category == category, !seen.contains(candidate.item) else { continue }
                    seen.insert(candidate.item)
                    picked.append(candidate)
                    if picked.count == count { break }
                }
                guard picked.count == count else { return nil }
                for placement in picked { used.insert(placement.id) }
                members += picked
            }
        }
        return members
    }

    /// Gli angoli che le copie sull'isola formano adesso: per ognuno, le copie che lo formano (nell'ordine in cui stanno nell'elenco). Si prova
    /// con ogni copia come «centro» e vale il primo centro che ci riesce, così il risultato è sempre lo stesso per le stesse copie.
    static func formed(by placements: [GardenPlacement]) -> [String: [UUID]] {
        var result: [String: [UUID]] = [:]
        for corner in all {
            for center in placements {
                let near = placements.filter { distance(center, $0) <= reach }
                guard let members = fulfil(corner.needs, from: near) else { continue }
                let ids = Set(members.map { $0.id })
                result[corner.id] = placements.filter { ids.contains($0.id) }.map { $0.id }
                break
            }
        }
        return result
    }
}
