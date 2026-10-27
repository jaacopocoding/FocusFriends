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
    static func canPlace(_ footprint: GardenFootprint, at origin: GardenTile, size: Int, occupied: Set<GardenTile>, island: String? = nil) -> Bool {
        let path = island.map { Set(GardenPaths.tiles(island: $0, size: size)) }
        for tile in tiles(of: footprint, at: origin) {
            if !GardenIsland.contains(tile, size: size) || (path?.contains(tile) ?? GardenIsland.isPath(tile)) || occupied.contains(tile) { return false }
            if let island, GardenLandmarks.contains(tile, island: island) { return false }
        }
        return true
    }

    /// Dove si può camminare: dentro l'isola e dove non c'è un oggetto.
    static func isWalkable(_ tile: GardenTile, size: Int, occupied: Set<GardenTile>) -> Bool {
        GardenIsland.contains(tile, size: size) && !occupied.contains(tile)
    }

    /// Tutti i posti dove si può mettere un oggetto, in ordine di tessera.
    static func freeOrigins(for footprint: GardenFootprint, size: Int, occupied: Set<GardenTile>, island: String? = nil) -> [GardenTile] {
        var result: [GardenTile] = []
        for row in 0..<size {
            for col in 0..<size {
                let origin = GardenTile(col: col, row: row)
                if canPlace(footprint, at: origin, size: size, occupied: occupied, island: island) { result.append(origin) }
            }
        }
        return result
    }

    /// Il posto libero più vicino a `desired` (a parità, il più in fondo e a sinistra), o nil se non ce n'è.
    static func nearestOrigin(to desired: GardenTile, footprint: GardenFootprint, size: Int, occupied: Set<GardenTile>, island: String? = nil) -> GardenTile? {
        for distance in 0...(2 * size) {
            var ring: [GardenTile] = []
            for dc in -distance...distance {
                let remaining = distance - abs(dc)
                ring.append(GardenTile(col: desired.col + dc, row: desired.row + remaining))
                if remaining > 0 { ring.append(GardenTile(col: desired.col + dc, row: desired.row - remaining)) }
            }
            ring.sort { ($0.row, $0.col) < ($1.row, $1.col) }
            if let found = ring.first(where: { canPlace(footprint, at: $0, size: size, occupied: occupied, island: island) }) { return found }
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
    static func defaultCompanionTile(index: Int, island: String? = nil) -> GardenTile {
        let slot = ((index % 4) + 4) % 4
        guard let island else { return GardenIsland.pathTiles(size: GardenIsland.baseSize)[[2, 4, 6, 8][slot]] }
        let path = GardenPaths.tiles(island: island, size: GardenIsland.baseSize)
        return path[min(Int(Double(path.count) * [0.2, 0.4, 0.6, 0.8][slot]), path.count - 1)]
    }

    /// Dove stanno le cose della dotazione quando si comincia (sono sempre le stesse): fuori dal sentiero e dalla casa di ogni isola, a tutte le grandezze (vedi `GardenPaths` e `GardenLandmarks`).
    static let starterOrigins: [String: GardenTile] = [
        "margherite": GardenTile(col: 7, row: 2), "trifoglio": GardenTile(col: 0, row: 7),
        "erba-alta": GardenTile(col: 7, row: 0), "mughetti": GardenTile(col: 2, row: 7),
    ]
}

/// Le cose che si uniscono a quelle uguali accanto (la staccionata): da quali lati della tessera parte un pezzo, e quindi se è dritto, un angolo, una T o una croce. Solo Foundation, con prove.
/// I lati sono quelli del rombo: una cosa dritta lungo le colonne va dal lato in alto a sinistra a quello in basso a destra, una lungo le righe da quello in alto a destra a quello in basso a sinistra.
enum GardenLinks {
    struct Arms: OptionSet, Hashable {
        let rawValue: Int
        /// Verso la tessera con una colonna in meno, una riga in meno, una riga in più, una colonna in più.
        static let upLeft = Arms(rawValue: 1), upRight = Arms(rawValue: 2), downLeft = Arms(rawValue: 4), downRight = Arms(rawValue: 8)
        var opposite: Arms {
            var result: Arms = []
            if contains(.upLeft) { result.insert(.downRight) }
            if contains(.downRight) { result.insert(.upLeft) }
            if contains(.upRight) { result.insert(.downLeft) }
            if contains(.downLeft) { result.insert(.upRight) }
            return result
        }
    }

    /// I lati da cui parte il pezzo in `tile`: verso ogni vicino uguale (`among` sono le tessere con una cosa uguale). Senza vicini va dritto, nel verso scelto girandolo; con un vicino solo
    /// prosegue dritto, nel verso del vicino (la girata non conta: il pezzo segue la fila).
    static func arms(at tile: GardenTile, among linked: Set<GardenTile>, turned: Bool) -> Arms {
        var arms: Arms = []
        if linked.contains(GardenTile(col: tile.col - 1, row: tile.row)) { arms.insert(.upLeft) }
        if linked.contains(GardenTile(col: tile.col, row: tile.row - 1)) { arms.insert(.upRight) }
        if linked.contains(GardenTile(col: tile.col, row: tile.row + 1)) { arms.insert(.downLeft) }
        if linked.contains(GardenTile(col: tile.col + 1, row: tile.row)) { arms.insert(.downRight) }
        if arms.isEmpty { return turned ? [.upRight, .downLeft] : [.upLeft, .downRight] }
        return arms.rawValue.nonzeroBitCount == 1 ? arms.union(arms.opposite) : arms
    }
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

    /// D'inverno le tessere sono quelle con la neve (assets/giardino/tessera_neve_<n>.png, dodici) e quelle del sentiero innevato
    /// (tessera_sentiero_neve_<n>.png, otto): la neve liscia, lunga a ondulazioni e a cumuli fa da sfondo; le orme, i rametti, il ghiaccio, le bacche e i
    /// sassi che spuntano sono rari. Nel sentiero le pietre contano più della neve calpestata, e le pietre scure e bagnate sono quasi un'eccezione.
    static let snowWeights: [Double] = [0.14, 0.13, 0.07, 0.07, 0.07, 0.06, 0.05, 0.04, 0.12, 0.08, 0.04, 0.13]
    static let snowPathWeights: [Double] = [0.10, 0.16, 0.16, 0.22, 0.12, 0.10, 0.10, 0.04]

    /// I pesi delle tessere (e del sentiero) per una stagione.
    static func grassWeights(season: Season) -> [Double] { season == .winter ? snowWeights : grassWeights }
    static func pathWeights(season: Season) -> [Double] { season == .winter ? snowPathWeights : pathWeights }

    /// Quante tessere di seguito (da 2 a 3) hanno la stessa immagine, per la corsa che comincia a `index` di una fila (o del sentiero).
    private static func runLength(_ index: Int, _ line: Int, _ tag: String) -> Int {
        2 + Int(GardenDrops.mixedHash("corsa-\(tag)\(line),\(index)") % 2)
    }

    /// La tessera del sentiero (da 0) per ognuna delle prime `count` tessere del sentiero (nell'ordine di `GardenIsland.pathTiles`): a gruppi di 2 o 3
    /// uguali, e un gruppo diverso dal precedente (se non dopo quattro tentativi). Quando il sentiero si allunga, quelle che c'erano non cambiano.
    static func pathVariants(count: Int, weights: [Double] = pathWeights, tag: String = "") -> [Int] {
        var result: [Int] = []
        var previous = -1
        while result.count < count {
            let start = result.count
            var choice = pick(col: start, row: -1, salt: 0, weights: weights, tag: tag)
            var salt = 1
            while choice == previous && salt <= 4 {
                choice = pick(col: start, row: -1, salt: salt, weights: weights, tag: tag)
                salt += 1
            }
            for _ in 0..<runLength(start, -1, tag) where result.count < count { result.append(choice) }
            previous = choice
        }
        return result
    }

    private static func pick(col: Int, row: Int, salt: Int, weights: [Double], tag: String) -> Int {
        let total = weights.reduce(0, +)
        let draw = Double(GardenDrops.mixedHash("terra-\(tag)\(col),\(row),\(salt)")) / 4_294_967_296 * total
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
    static func grassGrid(size: Int, weights: [Double] = grassWeights, tag: String = "") -> [Int] {
        var grid = [Int](repeating: 0, count: size * size)
        for row in 0..<size {
            var col = 0
            var previous = -1
            while col < size {
                let up = row > 0 ? grid[(row - 1) * size + col] : -1
                var choice = pick(col: col, row: row, salt: 0, weights: weights, tag: tag)
                var salt = 1
                while (choice == previous || choice == up) && salt <= 4 {
                    choice = pick(col: col, row: row, salt: salt, weights: weights, tag: tag)
                    salt += 1
                }
                for offset in 0..<runLength(col, row, tag) where col + offset < size { grid[row * size + col + offset] = choice }
                previous = choice
                col += runLength(col, row, tag)
            }
        }
        return grid
    }

    // MARK: - Il bordo di terra

    static let edgeCount = 3

    /// Quali delle tre strisce del bordo (da 0) vanno, una dopo l'altra, su un lato dell'isola (`face` 0 = sinistro, 1 = destro): mai due uguali di
    /// seguito. L'app ne mette una specchiata ogni due, così dove una finisce e l'altra comincia non si vede il taglio.
    static func edgeSequence(face: Int, count: Int) -> [Int] {
        var result: [Int] = []
        for index in 0..<count {
            func draw(_ salt: Int) -> Int {
                Int(GardenDrops.mixedHash("bordo-\(face),\(index),\(salt)") % UInt32(edgeCount))
            }
            var choice = draw(0)
            var salt = 1
            while index > 0 && choice == result[index - 1] && salt <= 4 {
                choice = draw(salt)
                salt += 1
            }
            result.append(choice)
        }
        return result
    }

    // MARK: - I dettagli sparsi sul terreno

    static let decalCount = 24

    /// Quali dei 24 dettagli (assets/giardino/dettaglio_<n>.png, da `tools/cutout_dettagli.py`) sono ciuffi, trifogli, fiori, sassi, foglie, petali e neve.
    enum DecalGroup: Int, CaseIterable {
        case tufts, clover, flowers, stones, leaves, petals, snow

        /// Gli indici (da 0) delle immagini di questo gruppo.
        var images: Range<Int> {
            switch self {
            case .tufts: return 0..<4
            case .clover: return 4..<6
            case .flowers: return 6..<10
            case .stones: return 10..<13
            case .leaves: return 13..<17
            case .petals: return 17..<20
            case .snow: return 20..<24
            }
        }

        /// Dove poggia sul terreno: 0 = il centro dell'immagine sta sul punto, 1 = il bordo in basso.
        var anchor: Double {
            switch self {
            case .tufts, .clover, .flowers: return 0.9
            case .stones: return 0.75
            case .snow: return 0.7
            case .leaves, .petals: return 0.5
            }
        }
    }

    /// Un dettaglio su una tessera: quale immagine, dove (`u` e `v` da 0 a 1 dentro la tessera, come per le colonne e le righe), quanto largo (in
    /// larghezze di tessera), e se è specchiato.
    struct Decal: Equatable {
        var image: Int
        var group: DecalGroup
        var u: Double
        var v: Double
        var size: Double
        var flipped: Bool

        var anchor: Double { group.anchor }
    }

    private struct DecalRule {
        var group: DecalGroup
        /// La probabilità di ogni dettaglio, e quanti al massimo.
        var chance: Double
        var maxCount: Int
        var size: ClosedRange<Double>
    }

    private static func decalRules(season: Season, onPath: Bool) -> [DecalRule] {
        if onPath {
            // Sul sentiero quasi niente: qualche sasso e quello che cade con la stagione.
            switch season {
            case .spring: return [DecalRule(group: .stones, chance: 0.08, maxCount: 1, size: 0.10...0.14), DecalRule(group: .petals, chance: 0.18, maxCount: 1, size: 0.14...0.18)]
            case .summer: return [DecalRule(group: .stones, chance: 0.10, maxCount: 1, size: 0.10...0.14)]
            case .autumn: return [DecalRule(group: .leaves, chance: 0.45, maxCount: 2, size: 0.13...0.17), DecalRule(group: .stones, chance: 0.06, maxCount: 1, size: 0.10...0.14)]
            case .winter: return [DecalRule(group: .snow, chance: 0.10, maxCount: 1, size: 0.26...0.36)]
            }
        }
        switch season {
        case .spring:
            return [DecalRule(group: .tufts, chance: 0.40, maxCount: 1, size: 0.28...0.40), DecalRule(group: .clover, chance: 0.10, maxCount: 1, size: 0.26...0.34),
                    DecalRule(group: .flowers, chance: 0.30, maxCount: 2, size: 0.10...0.13), DecalRule(group: .stones, chance: 0.06, maxCount: 1, size: 0.14...0.20),
                    DecalRule(group: .petals, chance: 0.12, maxCount: 1, size: 0.14...0.18)]
        case .summer:
            return [DecalRule(group: .tufts, chance: 0.40, maxCount: 1, size: 0.28...0.40), DecalRule(group: .clover, chance: 0.10, maxCount: 1, size: 0.26...0.34),
                    DecalRule(group: .flowers, chance: 0.28, maxCount: 2, size: 0.10...0.13), DecalRule(group: .stones, chance: 0.06, maxCount: 1, size: 0.14...0.20)]
        case .autumn:
            return [DecalRule(group: .tufts, chance: 0.18, maxCount: 1, size: 0.28...0.40), DecalRule(group: .stones, chance: 0.08, maxCount: 1, size: 0.14...0.20),
                    DecalRule(group: .leaves, chance: 0.60, maxCount: 2, size: 0.13...0.17), DecalRule(group: .clover, chance: 0.04, maxCount: 1, size: 0.26...0.34)]
        case .winter:
            // le tessere con la neve disegnata hanno già le loro orme, i loro rametti e i loro cumuli: i dettagli sono pochi, e niente erba verde
            return [DecalRule(group: .snow, chance: 0.22, maxCount: 1, size: 0.30...0.42), DecalRule(group: .stones, chance: 0.05, maxCount: 1, size: 0.14...0.20)]
        }
    }

    private static func decalUnit(_ col: Int, _ row: Int, _ group: DecalGroup, _ index: Int, _ salt: Int, _ tag: String) -> Double {
        Double(GardenDrops.mixedHash("dettaglio-\(tag)\(col),\(row),\(group.rawValue),\(index),\(salt)")) / 4_294_967_296
    }

    /// I dettagli sulla tessera (col, row): sempre gli stessi per la stessa tessera, stagione e tipo di tessera (sentiero o no).
    static func decals(col: Int, row: Int, season: Season, onPath: Bool, tag: String = "") -> [Decal] {
        var result: [Decal] = []
        for rule in decalRules(season: season, onPath: onPath) {
            for index in 0..<rule.maxCount where decalUnit(col, row, rule.group, index, 0, tag) < rule.chance {
                let images = rule.group.images
                let image = images.lowerBound + min(Int(decalUnit(col, row, rule.group, index, 1, tag) * Double(images.count)), images.count - 1)
                result.append(Decal(image: image, group: rule.group, u: 0.14 + decalUnit(col, row, rule.group, index, 2, tag) * 0.72,
                                    v: 0.14 + decalUnit(col, row, rule.group, index, 3, tag) * 0.72,
                                    size: rule.size.lowerBound + decalUnit(col, row, rule.group, index, 4, tag) * (rule.size.upperBound - rule.size.lowerBound),
                                    flipped: decalUnit(col, row, rule.group, index, 5, tag) < 0.5))
            }
        }
        return result
    }
}


/// La collina sotto l'isola: un'immagine d'erba (assets/giardino/collina_<stagione>.png, da `tools/prepara_collina.py`) con un buco a rombo in cima, dove sta l'isola.
/// L'isola si ingrandisce un po' perché ne copra il bordo, e la collina si ingrandisce con lei. Qui sono i numeri e il conto; il disegno sta in GardenWindow.swift.
enum GardenHill {
    /// La misura dell'immagine, in pixel, e gli angoli del buco (il rombo, largo circa il doppio dell'altezza).
    static let imageWidth = 1497.0, imageHeight = 720.0
    static let holeLeft = (x: 340.0, y: 262.0), holeRight = (x: 1158.0, y: 260.0)
    static let holeTop = (x: 752.0, y: 69.0), holeBottom = (x: 753.0, y: 466.0)
    static var holeWidth: Double { holeRight.x - holeLeft.x }
    static var holeHeight: Double { holeBottom.y - holeTop.y }
    /// Il buco è più piccolo dell'isola: l'isola ne copre il bordo e la fascia piatta d'erba che Gemini ha dipinto attorno (circa il 7 % per lato), così il pendio
    /// comincia subito dal bordo delle tessere. Per quanto: il buco è l'86 % dell'isola.
    static let fit = 0.86

    /// Dove cade la collina quando gli angoli sinistro e destro dell'isola sono in questi punti (coordinate dello schermo).
    struct Frame: Equatable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        /// Quanti punti dello schermo per ogni pixel dell'immagine.
        var scale: Double
    }

    static func frame(islandLeft: (x: Double, y: Double), islandRight: (x: Double, y: Double)) -> Frame {
        let scale = (islandRight.x - islandLeft.x) * fit / holeWidth
        let centerX = (holeLeft.x + holeRight.x) / 2, centerY = (holeLeft.y + holeRight.y) / 2
        // il centro del buco sta nel centro dell'isola (a metà fra i suoi angoli sinistro e destro, sulla loro linea)
        let islandCenterX = (islandLeft.x + islandRight.x) / 2, islandCenterY = (islandLeft.y + islandRight.y) / 2
        return Frame(x: islandCenterX - centerX * scale, y: islandCenterY - centerY * scale, width: imageWidth * scale, height: imageHeight * scale, scale: scale)
    }

    /// Quanto è larga la collina, in larghezze d'isola.
    static var widthRatio: Double { imageWidth * fit / holeWidth }
    /// Quanto scende sotto la linea degli angoli sinistro e destro dell'isola, in larghezze d'isola.
    static var belowRatio: Double { (imageHeight - (holeLeft.y + holeRight.y) / 2) * fit / holeWidth }
    /// Dall'angolo in alto dell'isola (largo `width`, alto la metà) al fondo della collina, in larghezze d'isola.
    static var heightRatio: Double { 0.25 + belowRatio }
}

/// Le isole del mondo: una per compagno, e l'id dell'isola è l'id del compagno a cui appartiene. Sono sempre quattro e sempre nelle stesse posizioni sulla mappa;
/// quelle dei compagni non ancora sbloccati sono al buio. Ognuna è un'isola a tessere come `GardenIsland` (stessa forma e stesso sentiero). Gli esemplari di un
/// animale vivono solo sulla sua isola, e gli oggetti di un animale (`GardenItem.island`) si mettono solo sulla sua.
enum GardenIslands {
    /// Nell'ordine dei compagni (`Pet.all`).
    static let all = ["pianty", "porcellino", "ciccio", "gattino"]
    /// L'isola di partenza finché non si sa chi si è scelto (e per i giardini delle versioni precedenti, finché `Garden.adoptHome` non dice quale).
    static let fallbackHome = "pianty"

    static func isKnown(_ id: String) -> Bool { all.contains(id) }

    /// Cosa si aggiunge ai sorteggi del terreno (erba, sentiero, dettagli) perché ogni isola abbia i suoi: quella di Pianty è com'è sempre stata.
    static func terrainTag(_ id: String) -> String { id == fallbackHome ? "" : id + "/" }
}

/// Il sentiero di ogni isola: unisce le due tessere dove arrivano i suoi ponti, con una curva larga (due tessere o poco meno, più stretta e più larga lungo la strada) che
/// ogni isola fa a modo suo (la forma viene dal nome dell'isola). Le tessere del sentiero non si possono occupare con gli oggetti.
/// Solo Foundation e con prove (tests/main.swift). Senza isola (`island` nil) valgono ancora il vecchio sentiero di `GardenIsland.isPath` e le sue prove.
enum GardenPaths {
    /// La fila (o colonna) di tessere dove un ponte tocca l'isola, contando da zero dal bordo vicino: è la stessa per tutte, così due isole di grandezza diversa
    /// restano in linea.
    static let landingIndex = 5

    /// Da quale lato di un'isola parte un ponte: l'inizio o la fine delle colonne, l'inizio o la fine delle righe.
    enum Face: Equatable { case colStart, colEnd, rowStart, rowEnd }

    struct Landing: Equatable {
        let face: Face
        let tile: GardenTile
    }

    /// Dove arrivano i ponti di un'isola, nell'ordine dei ponti del mondo (due, su lati vicini).
    static func landings(island: String, size: Int) -> [Landing] {
        let last = max(size - 1, 0), at = min(landingIndex, last)
        var result: [Landing] = []
        for bridge in GardenWorld.bridges {
            if bridge.first == island {
                result.append(bridge.alongColumns ? Landing(face: .colEnd, tile: GardenTile(col: last, row: at)) : Landing(face: .rowEnd, tile: GardenTile(col: at, row: last)))
            }
            if bridge.second == island {
                result.append(bridge.alongColumns ? Landing(face: .colStart, tile: GardenTile(col: 0, row: at)) : Landing(face: .rowStart, tile: GardenTile(col: at, row: 0)))
            }
        }
        return result
    }

    /// Da che parte il sentiero entra nell'isola, dal lato dell'approdo (colonna, riga).
    private static func inward(_ face: Face) -> (col: Double, row: Double) {
        switch face {
        case .colStart: return (1, 0)
        case .colEnd: return (-1, 0)
        case .rowStart: return (0, 1)
        case .rowEnd: return (0, -1)
        }
    }

    private static func unit(_ text: String) -> Double { Double(GardenDrops.mixedHash(text)) / 4_294_967_296 }

    private static var cache: [String: [GardenTile]] = [:]
    private static let lock = NSLock()

    /// Le tessere del sentiero di un'isola grande `size`, dal primo approdo al secondo. Sempre le stesse per la stessa isola e grandezza. Un'isola che non c'è: il vecchio sentiero.
    static func tiles(island: String, size: Int) -> [GardenTile] {
        let key = "\(island)|\(size)"
        lock.lock()
        if let known = cache[key] {
            lock.unlock()
            return known
        }
        lock.unlock()
        let made = generate(island: island, size: size)
        lock.lock()
        cache[key] = made
        lock.unlock()
        return made
    }

    static func contains(_ tile: GardenTile, island: String, size: Int) -> Bool {
        tiles(island: island, size: size).contains(tile)
    }

    /// Il sentiero di un'isola più piccola del massimo è quello dell'isola grande ritagliato (così, se l'isola si allarga, quello che c'era resta com'era: si aggiungono
    /// solo tessere), più un tratto dritto fino alla tessera dove arriva il ponte sul lato che si è accorciato.
    private static func generate(island: String, size: Int) -> [GardenTile] {
        let full = generateFull(island: island)
        guard size < GardenIsland.maxSize else { return full }
        var tiles = full.filter { GardenIsland.contains($0, size: size) }
        var known = Set(tiles)
        for landing in landings(island: island, size: size) where !known.contains(landing.tile) {
            guard let nearest = tiles.min(by: { abs($0.col - landing.tile.col) + abs($0.row - landing.tile.row) < abs($1.col - landing.tile.col) + abs($1.row - landing.tile.row) }) else {
                tiles.append(landing.tile)
                known.insert(landing.tile)
                continue
            }
            var current = landing.tile
            var added = [current]
            let alongColumns = inward(landing.face).col != 0
            func step(_ from: Int, toward to: Int) -> Int { from == to ? from : from + (to > from ? 1 : -1) }
            if alongColumns {
                while current.col != nearest.col { current = GardenTile(col: step(current.col, toward: nearest.col), row: current.row); added.append(current) }
                while current.row != nearest.row { current = GardenTile(col: current.col, row: step(current.row, toward: nearest.row)); added.append(current) }
            } else {
                while current.row != nearest.row { current = GardenTile(col: current.col, row: step(current.row, toward: nearest.row)); added.append(current) }
                while current.col != nearest.col { current = GardenTile(col: step(current.col, toward: nearest.col), row: current.row); added.append(current) }
            }
            for tile in added.reversed() where !known.contains(tile) {
                tiles.append(tile)
                known.insert(tile)
            }
        }
        return tiles
    }

    /// Il sentiero dell'isola grande: se passa nell'angolo della casa, si rifà con le curve che entrano di più nell'isola, finché non gira al largo.
    private static func generateFull(island: String) -> [GardenTile] {
        let lands = landings(island: island, size: GardenIsland.maxSize)
        guard lands.count == 2 else { return GardenIsland.pathTiles(size: GardenIsland.maxSize) }
        var best: [GardenTile] = []
        for attempt in 0..<9 {
            best = generateCurve(island: island, lands: lands, reach: 1 + 0.08 * Double(attempt))
            if !best.contains(where: { $0.col < GardenLandmarks.side && $0.row < GardenLandmarks.side }) { return best }
        }
        // se qualche tessera arriva ancora nell'angolo (a un capo, quando la curva si piega), si toglie
        return best.filter { !($0.col < GardenLandmarks.side && $0.row < GardenLandmarks.side) }
    }

    private static func generateCurve(island: String, lands: [Landing], reach stretch: Double) -> [GardenTile] {
        let size = GardenIsland.maxSize
        let n = Double(size)
        func center(_ tile: GardenTile) -> (col: Double, row: Double) { (Double(tile.col) + 0.5, Double(tile.row) + 0.5) }
        let p0 = center(lands[0].tile), p3 = center(lands[1].tile)
        let d0 = inward(lands[0].face), d3 = inward(lands[1].face)
        // il carattere dell'isola: quanto la curva entra, da che parte si piega ai due capi, come si stringe e si allarga
        let reach = n * (0.30 + 0.30 * unit("sentiero-entra-" + island)) * stretch
        let skew0 = n * (unit("sentiero-piega-a-" + island) - 0.5) * 0.9
        let skew3 = n * (unit("sentiero-piega-b-" + island) - 0.5) * 0.9
        let p1 = (col: p0.col + d0.col * reach - d0.row * skew0, row: p0.row + d0.row * reach + d0.col * skew0)
        let p2 = (col: p3.col + d3.col * reach - d3.row * skew3, row: p3.row + d3.row * reach + d3.col * skew3)
        let frequency = 1 + unit("sentiero-onda-" + island)
        let phase = unit("sentiero-fase-" + island)
        let steps = 80
        var samples: [(col: Double, row: Double, radius: Double)] = []
        for step in 0...steps {
            let t = Double(step) / Double(steps), u = 1 - t
            let col = u * u * u * p0.col + 3 * u * u * t * p1.col + 3 * u * t * t * p2.col + t * t * t * p3.col
            let row = u * u * u * p0.row + 3 * u * u * t * p1.row + 3 * u * t * t * p2.row + t * t * t * p3.row
            samples.append((col, row, 0.95 + 0.42 * (0.5 + 0.5 * sin(2 * Double.pi * (frequency * t + phase)))))
        }
        var found: [(tile: GardenTile, order: Int)] = []
        for row in 0..<size {
            for col in 0..<size {
                let c = (col: Double(col) + 0.5, row: Double(row) + 0.5)
                var best = Double.infinity, bestStep = 0
                for (index, sample) in samples.enumerated() {
                    let margin = ((c.col - sample.col) * (c.col - sample.col) + (c.row - sample.row) * (c.row - sample.row)).squareRoot() - sample.radius
                    if margin < best { best = margin; bestStep = index }
                }
                if best <= 0 { found.append((GardenTile(col: col, row: row), bestStep)) }
            }
        }
        var tiles = found.sorted { ($0.order, $0.tile.row, $0.tile.col) < ($1.order, $1.tile.row, $1.tile.col) }.map { $0.tile }
        for landing in lands where !tiles.contains(landing.tile) { tiles.append(landing.tile) }
        return tiles
    }
}

/// La casa di ogni isola: un punto di riferimento grande (3×3 tessere, zoccolo compreso) e fisso, nell'angolo in alto dell'isola (colonne e righe 0…2): lì il sentiero
/// non passa (`GardenPaths` gira al largo) e non copre le tessere dietro. Gli oggetti non ci vanno sopra e i compagni la aggirano. Solo Foundation e con prove (tests/main.swift).
enum GardenLandmarks {
    /// Quante tessere per lato.
    static let side = 3

    /// Le isole che hanno la casa disegnata (`assets/giardino/casa_<isola>.png`, da `tools/cutout_case.py`).
    static let shipped: Set<String> = ["pianty", "porcellino", "ciccio", "gattino"]
    /// Quelle che ci sono adesso (le prove la svuotano per provare il resto del giardino senza case).
    static var built: Set<String> = shipped

    /// Come sta il disegno rispetto alle 3×3 tessere, in pixel del disegno ritagliato (i numeri li stampa `tools/cutout_case.py`): il centro del rombo dello zoccolo, la sua
    /// mezza larghezza (dal centro agli angoli sinistro e destro) e la sua mezza altezza (dal centro all'angolo davanti); poi dove brillano le finestre di sera
    /// (`u` e `v` da 0 a 1 dall'angolo in alto a sinistra del disegno) e quanto sono grandi (in tessere).
    struct Art {
        let centerX: Double
        let centerY: Double
        let halfWidth: Double
        let halfHeight: Double
        let lights: [(u: Double, v: Double, size: Double)]
    }

    static let art: [String: Art] = [
        "pianty": Art(centerX: 465.5, centerY: 616, halfWidth: 462, halfHeight: 270,
                      lights: [(0.31, 0.64, 0.75), (0.19, 0.51, 0.55), (0.70, 0.60, 0.80), (0.80, 0.52, 0.55)]),
        "porcellino": Art(centerX: 465.5, centerY: 616, halfWidth: 462, halfHeight: 270,
                          lights: [(0.31, 0.38, 0.50)]),
        "ciccio": Art(centerX: 416.5, centerY: 638, halfWidth: 413.5, halfHeight: 251.5,
                      lights: [(0.49, 0.63, 0.90), (0.47, 0.10, 0.35)]),
        "gattino": Art(centerX: 416.5, centerY: 652.5, halfWidth: 413.5, halfHeight: 253.5,
                       lights: [(0.71, 0.57, 0.70), (0.30, 0.70, 0.35)]),
    ]

    /// Le tessere della casa di un'isola (nessuna se non ce l'ha ancora).
    static func tiles(island: String) -> [GardenTile] {
        guard built.contains(island) else { return [] }
        return (0..<side).flatMap { row in (0..<side).map { col in GardenTile(col: col, row: row) } }
    }

    static func contains(_ tile: GardenTile, island: String) -> Bool {
        built.contains(island) && tile.col >= 0 && tile.row >= 0 && tile.col < side && tile.row < side
    }
}

/// Un ponte fra due isole vicine della mappa.
struct GardenBridge: Equatable {
    /// L'isola che sta prima lungo l'asse del ponte, e quella che viene dopo.
    let first: String
    let second: String
    /// Se le due isole stanno una di seguito all'altra lungo le colonne (il ponte scende verso destra) o lungo le righe (scende verso sinistra).
    let alongColumns: Bool

    /// Come il ponte si scrive in `giardino.json` (`bridges`): le due isole, nell'ordine di `first` e `second`.
    var id: String { first + "-" + second }

    func touches(_ island: String) -> Bool { first == island || second == island }
}

/// Il mondo: le quattro isole in una griglia di 2×2 celle, sempre nelle stesse posizioni (come le tessere di un'isola: la seconda cella lungo le colonne sta a
/// destra e in basso, la seconda lungo le righe a sinistra e in basso), con quattro ponti fra le celle vicine. Ogni cella è larga quanto l'isola più grande più lo
/// spazio per il ponte; un'isola sta all'angolo in alto della sua cella e, se è più piccola, si allarga verso il davanti: i ponti toccano sempre la sesta fila (o colonna)
/// di tessere (`GardenPaths.landingIndex`), quindi un ponte è lungo di più fra isole piccole ma non si sposta. Le misure sono in tessere del mondo.
/// Solo Foundation e con prove (tests/main.swift).
enum GardenWorld {
    /// Lo spazio fra due isole grandi al massimo (in tessere): due pezzi di ponte.
    static let gap = 4
    static var cell: Int { GardenIsland.maxSize + gap }
    /// Quante tessere è largo e alto il mondo (in colonne e in righe).
    static var extent: Int { 2 * cell - gap }

    /// Dove sta ogni isola: pianty in alto, porcellino a destra, ciccio a sinistra, gattino in basso.
    private static let slots: [String: GardenTile] = [
        "pianty": GardenTile(col: 0, row: 0), "porcellino": GardenTile(col: 1, row: 0),
        "ciccio": GardenTile(col: 0, row: 1), "gattino": GardenTile(col: 1, row: 1),
    ]

    static func slot(of island: String) -> GardenTile? { slots[island] }

    /// Il vertice «in alto» di un'isola (colonna e riga del mondo): l'angolo in alto della sua cella, qualunque sia la sua grandezza.
    static func corner(of island: String, size: Int) -> (col: Double, row: Double)? {
        guard let slot = slots[island] else { return nil }
        return (Double(slot.col * cell), Double(slot.row * cell))
    }

    /// I quattro ponti, sempre nello stesso ordine (le isole come stanno in `GardenIslands.all`).
    static let bridges: [GardenBridge] = {
        var result: [GardenBridge] = []
        for first in GardenIslands.all {
            for second in GardenIslands.all {
                guard let a = slots[first], let b = slots[second] else { continue }
                if b.col == a.col + 1 && b.row == a.row {
                    result.append(GardenBridge(first: first, second: second, alongColumns: true))
                } else if b.row == a.row + 1 && b.col == a.col {
                    result.append(GardenBridge(first: first, second: second, alongColumns: false))
                }
            }
        }
        return result
    }()

    /// La striscia che un ponte deve coprire: lungo il suo asse da `from` a `to` (il bordo dell'isola prima e quello dell'isola dopo) e, sull'altro asse, `across`
    /// (il centro della tessera d'approdo, uguale per le due isole).
    static func span(of bridge: GardenBridge, firstSize: Int, secondSize: Int) -> (from: Double, to: Double, across: Double)? {
        guard let a = corner(of: bridge.first, size: firstSize), let b = corner(of: bridge.second, size: secondSize),
              let slot = slots[bridge.first] else { return nil }
        let landing = Double(GardenPaths.landingIndex) + 0.5
        if bridge.alongColumns { return (a.col + Double(firstSize), b.col, Double(slot.row * cell) + landing) }
        return (a.row + Double(firstSize), b.row, Double(slot.col * cell) + landing)
    }

    /// I ponti che si possono costruire adesso: quelli fra due isole aperte che non sono già costruiti, nell'ordine di `bridges`.
    static func pending(open: Set<String>, built: Set<String>) -> [GardenBridge] {
        bridges.filter { open.contains($0.first) && open.contains($0.second) && !built.contains($0.id) }
    }

    /// Le isole che ricevono adesso il regalo di benvenuto: quelle aperte (il compagno è sbloccato) che non l'hanno ancora ricevuto, tranne l'isola di casa. Il regalo non
    /// dipende dal ponte: arriva anche se non nasce nessun ponte (il compagno è in diagonale rispetto alle isole aperte) e una volta sola per compagno, anche se poi ne
    /// arrivano altri. Nell'ordine di `GardenIslands.all`.
    static func newcomers(open: Set<String>, welcomed: Set<String>, home: String) -> [String] {
        GardenIslands.all.filter { $0 != home && open.contains($0) && !welcomed.contains($0) }
    }

    /// Ogni pezzo di ponte copre due tessere lungo l'asse.
    static let pieceLength = 2.0

    /// Dove stanno i pezzi di un ponte lungo da `from` a `to`: i centri, lungo l'asse, in numero giusto per coprire tutto (anche un po' di più: i capi si appoggiano alle isole).
    static func pieceCenters(from: Double, to: Double) -> [Double] {
        let count = max(Int((max(to - from, 0) / pieceLength).rounded(.up)), 1)
        let middle = (from + to) / 2
        return (0..<count).map { middle + (Double($0) - Double(count - 1) / 2) * pieceLength }
    }
}
