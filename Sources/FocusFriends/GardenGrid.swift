import Foundation

/// Una tessera dell'isola del giardino. `col` va verso destra e in basso, `row` verso sinistra e in basso: (0, 0) è l'angolo in fondo.
struct GardenTile: Codable, Hashable {
    var col: Int
    var row: Int
}

/// Quante tessere occupa un oggetto (larghezza lungo `col`, profondità lungo `row`).
struct GardenFootprint: Equatable {
    var cols: Int
    var rows: Int

    /// Girato di un quarto: larghezza e profondità si scambiano.
    var turned: GardenFootprint { GardenFootprint(cols: rows, rows: cols) }

    func applying(turned isTurned: Bool) -> GardenFootprint { isTurned ? turned : self }
}

/// Dove sta una cosa nel prato libero della versione 1 e 2 del giardino: frazioni della scena (x da sinistra, y dall'alto), con i piedi in
/// quel punto. Serve solo per leggere i file vecchi (`GardenLayout.tile(fromLegacy:size:)`).
struct GardenSpot: Codable, Equatable {
    var x: Double
    var y: Double
}

/// Il prato libero di prima: la sua forma serve a trasformare le vecchie posizioni in tessere.
enum GardenScene {
    /// Il prato dove stavano le cose (frazioni della scena).
    static let lawn = (minX: 0.03, maxX: 0.97, minY: 0.56, maxY: 0.99)

    static func clamped(_ spot: GardenSpot) -> GardenSpot {
        GardenSpot(x: min(max(spot.x, lawn.minX), lawn.maxX), y: min(max(spot.y, lawn.minY), lawn.maxY))
    }
}

/// L'isola: un quadrato di tessere visto di sbieco. Parte da 8×8 e si allarga di una fila per ogni doppia pagina dell'album completata,
/// fino a 10×10. Un sentiero la attraversa: ci camminano i compagni, ma non ci si costruisce sopra.
enum GardenIsland {
    static let baseSize = 8
    static let maxSize = 10

    /// Quanto è grande con tante doppie pagine dell'album completate.
    static func size(completedSpreads: Int) -> Int {
        min(baseSize + max(completedSpreads, 0), maxSize)
    }

    /// Il sentiero entra dal fondo, gira e arriva al bordo davanti. Le tessere non cambiano quando l'isola si allarga: si allunga solo
    /// l'ultimo pezzo (così niente di quello che c'è già finisce sul sentiero).
    static func isPath(_ tile: GardenTile) -> Bool {
        (tile.row == 3 && (0...3).contains(tile.col))
            || (tile.col == 3 && (3...5).contains(tile.row))
            || (tile.row == 5 && tile.col >= 3)
    }

    /// Le tessere del sentiero di un'isola, dall'ingresso all'uscita.
    static func pathTiles(size: Int) -> [GardenTile] {
        var result = (0...3).map { GardenTile(col: $0, row: 3) }
        result += [GardenTile(col: 3, row: 4), GardenTile(col: 3, row: 5)]
        if size > 4 { result += (4..<size).map { GardenTile(col: $0, row: 5) } }
        return result
    }

    static func contains(_ tile: GardenTile, size: Int) -> Bool {
        tile.col >= 0 && tile.row >= 0 && tile.col < size && tile.row < size
    }
}

/// Le regole di dove stanno le cose sull'isola (solo Foundation, con prove).
enum GardenLayout {
    /// Le tessere che un oggetto occupa con l'angolo in fondo in `origin`.
    static func tiles(of footprint: GardenFootprint, at origin: GardenTile) -> [GardenTile] {
        var result: [GardenTile] = []
        for dc in 0..<footprint.cols {
            for dr in 0..<footprint.rows { result.append(GardenTile(col: origin.col + dc, row: origin.row + dr)) }
        }
        return result
    }

    /// Le tessere occupate dalle copie nel prato. `skipping`: una copia da non contare (quella che si sta spostando).
    static func occupiedTiles(_ placements: [GardenPlacement], skipping: UUID? = nil) -> Set<GardenTile> {
        var result: Set<GardenTile> = []
        for placement in placements where placement.id != skipping {
            guard let item = GardenCatalog.item(withID: placement.item) else { continue }
            result.formUnion(tiles(of: item.footprint.applying(turned: placement.turned), at: placement.tile))
        }
        return result
    }

    /// Ci sta? Dentro l'isola, fuori dal sentiero e senza coprire altro.
    static func canPlace(_ footprint: GardenFootprint, at origin: GardenTile, size: Int, occupied: Set<GardenTile>) -> Bool {
        for tile in tiles(of: footprint, at: origin) {
            if !GardenIsland.contains(tile, size: size) || GardenIsland.isPath(tile) || occupied.contains(tile) { return false }
        }
        return true
    }

    /// Dove si può camminare: dentro l'isola e dove non c'è un oggetto.
    static func isWalkable(_ tile: GardenTile, size: Int, occupied: Set<GardenTile>) -> Bool {
        GardenIsland.contains(tile, size: size) && !occupied.contains(tile)
    }

    /// Tutti i posti dove si può mettere un oggetto, in ordine di tessera.
    static func freeOrigins(for footprint: GardenFootprint, size: Int, occupied: Set<GardenTile>) -> [GardenTile] {
        var result: [GardenTile] = []
        for row in 0..<size {
            for col in 0..<size {
                let origin = GardenTile(col: col, row: row)
                if canPlace(footprint, at: origin, size: size, occupied: occupied) { result.append(origin) }
            }
        }
        return result
    }

    /// Il posto libero più vicino a `desired` (a parità, il più in fondo e a sinistra), o nil se non ce n'è.
    static func nearestOrigin(to desired: GardenTile, footprint: GardenFootprint, size: Int, occupied: Set<GardenTile>) -> GardenTile? {
        for distance in 0...(2 * size) {
            var ring: [GardenTile] = []
            for dc in -distance...distance {
                let remaining = distance - abs(dc)
                ring.append(GardenTile(col: desired.col + dc, row: desired.row + remaining))
                if remaining > 0 { ring.append(GardenTile(col: desired.col + dc, row: desired.row - remaining)) }
            }
            ring.sort { ($0.row, $0.col) < ($1.row, $1.col) }
            if let found = ring.first(where: { canPlace(footprint, at: $0, size: size, occupied: occupied) }) { return found }
        }
        return nil
    }

    /// La tessera dove si può camminare più vicina a `desired` (a parità, la più in fondo e a sinistra).
    static func nearestWalkable(to desired: GardenTile, size: Int, occupied: Set<GardenTile>) -> GardenTile? {
        for distance in 0...(2 * size) {
            var ring: [GardenTile] = []
            for dc in -distance...distance {
                let remaining = distance - abs(dc)
                ring.append(GardenTile(col: desired.col + dc, row: desired.row + remaining))
                if remaining > 0 { ring.append(GardenTile(col: desired.col + dc, row: desired.row - remaining)) }
            }
            ring.sort { ($0.row, $0.col) < ($1.row, $1.col) }
            if let found = ring.first(where: { isWalkable($0, size: size, occupied: occupied) }) { return found }
        }
        return nil
    }

    /// Dove cade, sull'isola, un punto del vecchio prato libero. A sinistra e a destra dello schermo corrispondono `col - row`, in fondo e
    /// davanti `col + row`.
    static func tile(fromLegacy spot: GardenSpot, size: Int) -> GardenTile {
        let clamped = GardenScene.clamped(spot)
        let u = (clamped.x - GardenScene.lawn.minX) / (GardenScene.lawn.maxX - GardenScene.lawn.minX)
        let v = (clamped.y - GardenScene.lawn.minY) / (GardenScene.lawn.maxY - GardenScene.lawn.minY)
        let n = Double(size)
        let col = Int((n * (v + u - 0.5)).rounded(.down)), row = Int((n * (v - u + 0.5)).rounded(.down))
        return GardenTile(col: min(max(col, 0), size - 1), row: min(max(row, 0), size - 1))
    }

    /// Dove sta un compagno finché non lo si sposta: sul sentiero, a distanza uno dall'altro.
    static func defaultCompanionTile(index: Int) -> GardenTile {
        let path = GardenIsland.pathTiles(size: GardenIsland.baseSize)
        return path[[2, 4, 6, 8][((index % 4) + 4) % 4]]
    }

    /// Dove stanno le cose della dotazione quando si comincia (sono sempre le stesse).
    static let starterOrigins: [String: GardenTile] = [
        "margherite": GardenTile(col: 5, row: 3), "trifoglio": GardenTile(col: 2, row: 5),
        "erba-alta": GardenTile(col: 1, row: 1), "mughetti": GardenTile(col: 6, row: 6),
    ]
}

/// Il terreno dell'isola: quale delle tessere d'erba disegnate (assets/giardino/tessera_erba_<n>.png, dodici) va su ogni tessera. Sempre la
/// stessa per la stessa tessera (non cambia da un'apertura all'altra) e non due uguali una accanto all'altra, quasi mai.
enum GardenTerrain {
    static let grassCount = 12
    /// Quanto spesso esce ognuna (le prime due, lisce, fanno da sfondo; quelle con sassi, muschio o foglie sono rare perché hanno tinte diverse).
    static let grassWeights: [Double] = [0.15, 0.09, 0.12, 0.09, 0.06, 0.06, 0.05, 0.05, 0.04, 0.06, 0.02, 0.07]

    static let pathCount = 8
    /// Le tessere del sentiero: le lastre e i ciottoli fanno la parte principale; il masso solo, il muschio e la terra liscia sono rari.
    static let pathWeights: [Double] = [0.04, 0.14, 0.16, 0.20, 0.14, 0.08, 0.12, 0.12]

    /// Quante tessere di seguito (da 2 a 3) hanno la stessa immagine, per la corsa che comincia a `index` di una fila (o del sentiero).
    private static func runLength(_ index: Int, _ line: Int) -> Int {
        2 + Int(GardenDrops.mixedHash("corsa-\(line),\(index)") % 2)
    }

    /// La tessera del sentiero (da 0) per ognuna delle prime `count` tessere del sentiero (nell'ordine di `GardenIsland.pathTiles`): a gruppi di 2 o 3
    /// uguali, e un gruppo diverso dal precedente (se non dopo quattro tentativi). Quando il sentiero si allunga, quelle che c'erano non cambiano.
    static func pathVariants(count: Int, weights: [Double] = pathWeights) -> [Int] {
        var result: [Int] = []
        var previous = -1
        while result.count < count {
            let start = result.count
            var choice = pick(col: start, row: -1, salt: 0, weights: weights)
            var salt = 1
            while choice == previous && salt <= 4 {
                choice = pick(col: start, row: -1, salt: salt, weights: weights)
                salt += 1
            }
            for _ in 0..<runLength(start, -1) where result.count < count { result.append(choice) }
            previous = choice
        }
        return result
    }

    private static func pick(col: Int, row: Int, salt: Int, weights: [Double]) -> Int {
        let total = weights.reduce(0, +)
        let draw = Double(GardenDrops.mixedHash("terra-\(col),\(row),\(salt)")) / 4_294_967_296 * total
        var sum = 0.0
        for (index, weight) in weights.enumerated() {
            sum += weight
            if draw < sum { return index }
        }
        return weights.count - 1
    }

    /// La tessera d'erba (da 0) di ogni tessera di un'isola `size × size`, per righe (`row * size + col`). In ogni fila (verso `col`) vanno a gruppi di
    /// 2 o 3 uguali, come chiazze di prato; un gruppo è diverso da quello prima e dalla tessera che gli sta sopra all'inizio (se non dopo quattro
    /// tentativi). Non dipende da quanto è grande l'isola: se si allarga, quello che c'era resta com'era.
    static func grassGrid(size: Int, weights: [Double] = grassWeights) -> [Int] {
        var grid = [Int](repeating: 0, count: size * size)
        for row in 0..<size {
            var col = 0
            var previous = -1
            while col < size {
                let up = row > 0 ? grid[(row - 1) * size + col] : -1
                var choice = pick(col: col, row: row, salt: 0, weights: weights)
                var salt = 1
                while (choice == previous || choice == up) && salt <= 4 {
                    choice = pick(col: col, row: row, salt: salt, weights: weights)
                    salt += 1
                }
                for offset in 0..<runLength(col, row) where col + offset < size { grid[row * size + col + offset] = choice }
                previous = choice
                col += runLength(col, row)
            }
        }
        return grid
    }
}

