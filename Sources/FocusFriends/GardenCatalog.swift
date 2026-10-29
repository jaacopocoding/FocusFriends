import Foundation

/// Le schede del negozio del giardino.
enum GardenCategory: String, CaseIterable {
    case flowers, companions, furniture

    var title: String {
        switch self {
        case .flowers: return "Fiori"
        case .companions: return "Per i compagni"
        case .furniture: return "Arredi"
        }
    }
}

/// La luce che fa un oggetto la sera (quando brillano i lampioni, vedi `GardenSky`): un alone caldo attorno a un punto del disegno e una pozza di luce sul prato.
struct GardenGlow: Equatable {
    var red: Int
    var green: Int
    var blue: Int
    /// Quanto è larga l'alone, in larghezze di tessera (la pozza sul prato è un quinto più larga).
    var radius: Double
    /// Dove sta la luce nel disegno: da 0 in cima a 1 ai piedi.
    var top: Double
    /// Quanto è forte (1 = come il lampione).
    var strength: Double
    /// Vibra piano come una fiamma (non con «Riduci movimento»).
    var flickers = false

    static let lamp = GardenGlow(red: 255, green: 196, blue: 104, radius: 1.25, top: 0.10, strength: 1)
}

/// Un tipo di oggetto del giardino. Si trova una volta (a fine focus, o c'è fin dall'inizio) e poi se ne possono mettere quante sono le copie trovate.
struct GardenItem: Equatable {
    let id: String
    let name: String
    let category: GardenCategory
    /// Quanto è alto, nelle unità del disegno: sull'isola si disegna alto `height × larghezza di una tessera ÷ 115`. (0 per quelli che stanno sul lato: la lunghezza è un lato
    /// della tessera, e l'altezza ne viene.)
    let height: Double
    /// Quanti punti costa sbloccarlo; 0 = c'è fin dall'inizio. I prezzi sono provvisori: stanno tutti qui.
    let price: Int
    /// Si disegna l'ombra sul prato (no per le cose piatte, come il tappeto).
    var castsShadow = true
    /// Quante tessere occupa (da girato, larghezza e profondità si scambiano). Nel catalogo sono tutti una tessera, tranne l'amaca e l'arco di rose (2×1, in fila lungo un asse): un oggetto
    /// sta sulla sua casella, e il disegno non è più largo di una tessera e poco più (per questo `height` dei più larghi è ridotta); la regola è nelle prove.
    var footprint = GardenFootprint(cols: 1, rows: 1)
    /// Una cosa piatta che sta sul lato della tessera, da un lato all'altro (la staccionata, le bandierine; l'amaca e l'arco di rose su due tessere in fila), mai da un angolo all'altro: si disegna adagiata sull'asse
    /// (`GardenSprites.axial`), e girata va sull'altro asse. Non fa ombra, e ha la base che passa per il centro della tessera.
    var axial = false
    /// Quanto si inclina il disegno adagiato sul lato: 0,5 è la pendenza dei lati dei rombi (giusta per le cose piatte, come la staccionata); le cose il cui disegno ha già una sua
    /// prospettiva (l'amaca, l'arco di rose) si storcono, e ne vogliono meno.
    var slope = 0.5
    /// Una volta trovata, se ne mettono quante si vuole (una staccionata sola non serve a niente): niente copie da contare, e i regali non la danno più.
    var repeatable = false
    /// Si unisce alle uguali che ha accanto (la staccionata): un pezzo ha un braccio verso ogni vicino, e così fa gli angoli, le T e le croci da solo (`GardenLinks`). Con un vicino
    /// solo prosegue dritto; senza vicini va nel verso scelto girandolo.
    var joins = false
    /// Fa luce la sera (il lampione, l'alberello di lucine, la lanterna, il braciere, e le quattro luci degli animali).
    var glow: GardenGlow?
    /// Ha un secondo disegno, «acceso» (`giardino_<id>-acceso`), che si vede quando fa buio: il braciere con la fiamma. Fa luce solo da acceso.
    var litDrawing = false
    /// L'isola dell'animale a cui appartiene (l'id del compagno): quell'oggetto si mette solo sulla sua isola. `nil` = universale, va su qualunque isola.
    var island: String?

    /// Può stare su questa isola? Gli universali sì, ovunque; quelli di un animale solo sulla sua.
    func fits(island other: String) -> Bool { island == nil || island == other }

    /// Il nome con l'articolo, per le frasi: «il cesto di carote», «la casa del gatto», «l'annaffiatoio». (Le cose degli animali sono sedici: la regola
    /// basta, e le prove le controllano tutte.)
    var nameWithArticle: String {
        let lower = name.prefix(1).lowercased() + name.dropFirst()
        if let first = lower.first, "aeiou".contains(first) { return "l'" + lower }
        let feminine = ["casa", "lanterna", "lampada", "candela"].contains { lower.hasPrefix($0 + " ") }
        return (feminine ? "la " : "il ") + lower
    }

    /// Dove si può mettere, a parole (per l'album): «universale», o «solo sull'isola di Gattino». `ownerName` è il nome dell'animale a cui appartiene.
    func islandRule(ownerName: String) -> String {
        island == nil ? "universale" : "solo sull'isola di \(ownerName)"
    }

    /// La riga quando si prova a mettere una cosa di un animale su un'altra isola: «La casa del gatto sta solo sull'isola di Gattino.»
    func wrongIslandLine(ownerName: String) -> String {
        let phrase = nameWithArticle
        return phrase.prefix(1).uppercased() + phrase.dropFirst() + " sta solo sull'isola di \(ownerName)."
    }

    /// Il nome dell'immagine nel bundle (`assets/giardino/<id>.png`, copiata da build.sh): quella di fronte, che sta nell'album e nella cassetta.
    var resource: String { "giardino_" + id }

    /// Quanti lati di tessera è lunga una cosa sul lato (una, o due per l'amaca e l'arco di rose).
    var sides: Int { max(footprint.cols, footprint.rows) }

    /// Il disegno da acceso (stessa larghezza e stessi piedi di quello spento, ma più alto: c'è la fiamma).
    var litResource: String? { litDrawing ? resource + "-acceso" : nil }

    /// Il disegno con cui sta sull'isola: per le cose sul lato quello adagiato sull'asse (con la sua lunghezza in lati, se più di uno: `giardino_amaca@asse2`).
    var gardenResource: String { axial ? resource + Self.axialSuffix + (sides > 1 ? "\(sides)" : "") : resource }
    static let axialSuffix = "@asse"

    /// Il disegno di un pezzo che si unisce ai vicini, con i bracci che ha (vedi `GardenLinks`): `giardino_cancelletto@asse#10`.
    func gardenResource(arms: GardenLinks.Arms) -> String { gardenResource + "#\(arms.rawValue)" }
}

/// Una copia di un oggetto messa sull'isola: la tessera dove sta il suo angolo in fondo, e se è girata.
struct GardenPlacement: Codable, Equatable {
    var id: UUID
    var item: String
    /// L'isola dove sta (l'id del compagno a cui appartiene). Vuoto = quella di casa, quando non è ancora decisa (`Garden.adoptHome`): chi apre un giardino
    /// delle versioni precedenti, o chi non ha ancora scelto il suo compagno.
    var island: String
    var col: Int
    var row: Int
    var turned: Bool
    /// Solo leggendo un file delle versioni 1 e 2: dov'era nel prato libero. `Garden` lo trasforma in una tessera e lo toglie.
    var legacy: GardenSpot?

    var tile: GardenTile {
        get { GardenTile(col: col, row: row) }
        set { col = newValue.col; row = newValue.row }
    }

    init(id: UUID = UUID(), item: String, tile: GardenTile, turned: Bool = false, island: String = "") {
        self.id = id
        self.item = item
        self.island = island
        col = tile.col
        row = tile.row
        self.turned = turned
        legacy = nil
    }

    private enum CodingKeys: String, CodingKey { case id, item, island, col, row, turned, x, y }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        item = try values.decode(String.self, forKey: .item)
        island = try values.decodeIfPresent(String.self, forKey: .island) ?? ""
        turned = try values.decodeIfPresent(Bool.self, forKey: .turned) ?? false
        if let col = try values.decodeIfPresent(Int.self, forKey: .col), let row = try values.decodeIfPresent(Int.self, forKey: .row) {
            self.col = col
            self.row = row
            legacy = nil
        } else {
            // Un file delle versioni 1 e 2: la posizione nel prato libero.
            col = 0
            row = 0
            legacy = GardenSpot(x: try values.decode(Double.self, forKey: .x), y: try values.decode(Double.self, forKey: .y))
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(item, forKey: .item)
        if !island.isEmpty { try values.encode(island, forKey: .island) }
        try values.encode(col, forKey: .col)
        try values.encode(row, forKey: .row)
        try values.encode(turned, forKey: .turned)
    }
}

/// Dove sta un compagno nel file: una tessera (versione 3) o un punto del prato libero (versioni 1 e 2).
struct GardenCompanionPlace: Codable, Equatable {
    var col: Int?
    var row: Int?
    var x: Double?
    var y: Double?
}

/// Gli oggetti del negozio e le dimensioni dei compagni nel giardino.
enum GardenCatalog {
    /// I compagni nel giardino: alti quanto, in primo piano (unità della scena). Quelli senza voce sono 100.
    private static let companionHeights: [String: Double] = [
        "pianty": 120, "porcellino": 60, "ciccio": 105, "gattino": 92,
    ]

    static func companionHeight(for petID: String) -> Double { companionHeights[petID] ?? 100 }

    private static func item(_ id: String, _ name: String, _ category: GardenCategory, height: Double, price: Int,
                             shadow: Bool = true, cols: Int = 1, rows: Int = 1, axial: Bool = false, slope: Double = 0.5, repeatable: Bool = false, joins: Bool = false,
                             glow: GardenGlow? = nil, litDrawing: Bool = false, island: String? = nil) -> GardenItem {
        GardenItem(id: id, name: name, category: category, height: height, price: price, castsShadow: shadow,
                   footprint: GardenFootprint(cols: cols, rows: rows), axial: axial, slope: slope, repeatable: repeatable, joins: joins, glow: glow, litDrawing: litDrawing, island: island)
    }

    /// Tutti gli oggetti, nell'ordine in cui compaiono nel negozio. I prezzi sono provvisori.
    static let items: [GardenItem] = [
        // Fiori
        item("margherite", "Margherite", .flowers, height: 90, price: 0),
        item("trifoglio", "Trifoglio", .flowers, height: 45, price: 0),
        item("erba-alta", "Erba alta", .flowers, height: 90, price: 0),
        item("mughetti", "Mughetti", .flowers, height: 110, price: 0),
        item("tulipani", "Tulipani", .flowers, height: 100, price: 2),
        item("funghi", "Funghi", .flowers, height: 70, price: 2),
        item("lavanda", "Lavanda", .flowers, height: 105, price: 3),
        item("papaveri", "Papaveri", .flowers, height: 120, price: 3),
        item("erbe", "Vaso di erbe", .flowers, height: 85, price: 3),
        item("felci", "Felci", .flowers, height: 110, price: 3),
        item("girasole", "Girasole", .flowers, height: 170, price: 4),
        item("rosaio", "Rosaio", .flowers, height: 130, price: 8),
        // Case e cose per i compagni
        item("cesto-carote", "Cesto di carote", .companions, height: 55, price: 2, island: "porcellino"),
        item("annaffiatoio", "Annaffiatoio", .companions, height: 50, price: 2, island: "pianty"),
        item("cesto-cuscino", "Cesto con cuscino", .companions, height: 60, price: 3, island: "gattino"),
        item("tunnel", "Tunnel con fieno", .companions, height: 55, price: 3, island: "porcellino"),
        item("altalena-uccelli", "Altalena uccelli", .companions, height: 85, price: 3, island: "ciccio"),
        item("vaso-grande", "Vaso grande", .companions, height: 70, price: 3, island: "pianty"),
        item("bagnetto", "Bagnetto uccelli", .companions, height: 75, price: 4, island: "ciccio"),
        item("aiuola", "Aiuola rialzata", .companions, height: 75, price: 4, island: "pianty"),
        item("tiragraffi", "Tiragraffi", .companions, height: 115, price: 5, island: "gattino"),
        item("casetta-uccelli", "Casa per uccelli", .companions, height: 95, price: 5, island: "ciccio"),
        item("casetta-gatto", "Casa del gatto", .companions, height: 115, price: 6, island: "gattino"),
        item("casetta-porcellino", "Casa porcellino", .companions, height: 88, price: 6, island: "porcellino"),
        // Arredi
        item("picnic", "Tappeto da picnic", .furniture, height: 70, price: 4, shadow: false),
        item("bandierine", "Bandierine", .furniture, height: 0, price: 4, shadow: false, axial: true),
        item("cancelletto", "Cancelletto", .furniture, height: 0, price: 4, shadow: false, axial: true, repeatable: true, joins: true),
        item("tavolino", "Tavolino da tè", .furniture, height: 95, price: 5),
        item("sdraio", "Sdraio", .furniture, height: 110, price: 5),
        item("carillon", "Carillon a vento", .furniture, height: 120, price: 5),
        item("panchina", "Panchina", .furniture, height: 95, price: 6),
        item("lampione", "Lampione", .furniture, height: 170, price: 6, glow: .lamp),
        item("ponticello", "Ponticello", .furniture, height: 82, price: 8),
        item("amaca", "Amaca", .furniture, height: 0, price: 9, shadow: false, cols: 2, axial: true, slope: 0.3),
        item("altalena", "Altalena", .furniture, height: 0, price: 10, shadow: false, axial: true),
        item("arco-rose", "Arco di rose", .furniture, height: 0, price: 12, shadow: false, cols: 2, axial: true, slope: 0.3),
        // Le luci (il lampione è fra gli arredi, più su): si aggiungono in fondo, perché il numero di una figurina non cambia mai.
        item("alberello-lucine", "Alberello di lucine", .furniture, height: 135, price: 5,
             glow: GardenGlow(red: 255, green: 230, blue: 160, radius: 0.85, top: 0.40, strength: 0.8)),
        item("lanterna-ceppo", "Lanterna sul ceppo", .furniture, height: 105, price: 4,
             glow: GardenGlow(red: 255, green: 190, blue: 100, radius: 0.8, top: 0.32, strength: 0.85)),
        item("braciere", "Braciere", .furniture, height: 80, price: 7, shadow: false,
             glow: GardenGlow(red: 255, green: 150, blue: 70, radius: 1.15, top: 0.35, strength: 1, flickers: true), litDrawing: true),
        // Una luce per ogni animale, sulla sua isola (sono le ultime quattro figurine, ma nell'album stanno con le cose dei compagni).
        item("barattolo-lucciole", "Barattolo di lucciole", .companions, height: 78, price: 4,
             glow: GardenGlow(red: 232, green: 244, blue: 150, radius: 0.7, top: 0.45, strength: 0.7), island: "pianty"),
        item("lanterna-voliera", "Lanterna per la voliera", .companions, height: 105, price: 5,
             glow: GardenGlow(red: 255, green: 200, blue: 110, radius: 0.8, top: 0.45, strength: 0.85), island: "ciccio"),
        item("lampada-fienile", "Lampada da fienile", .companions, height: 96, price: 4,
             glow: GardenGlow(red: 255, green: 175, blue: 85, radius: 0.85, top: 0.36, strength: 0.85), island: "porcellino"),
        item("candela-cesto", "Candela nel cesto", .companions, height: 62, price: 3,
             glow: GardenGlow(red: 255, green: 205, blue: 130, radius: 0.65, top: 0.22, strength: 0.8), island: "gattino"),
    ]

    /// Gli oggetti universali (su qualunque isola) e quelli di un animale (solo sulla sua isola).
    static var universalItems: [GardenItem] { items.filter { $0.island == nil } }
    static func items(forIsland island: String) -> [GardenItem] { items.filter { $0.island == island } }

    /// Il regalo di benvenuto di un'isola quando si costruisce il suo ponte: il primo oggetto dell'animale (nell'ordine del catalogo) che non si ha ancora;
    /// se si hanno già tutti, una copia in più del primo. `copies` dice quante copie di un oggetto si hanno.
    static func welcomeGift(forIsland island: String, copies: (String) -> Int) -> String? {
        let own = items(forIsland: island)
        return (own.first { copies($0.id) == 0 } ?? own.first)?.id
    }

    static func item(withID id: String) -> GardenItem? {
        items.first { $0.id == id }
    }

    /// Il numero della figurina nell'album (da 1, nell'ordine del catalogo: non cambia mai, i nuovi oggetti si aggiungono in fondo).
    static func number(of id: String) -> Int? {
        items.firstIndex { $0.id == id }.map { $0 + 1 }
    }

    static func items(in category: GardenCategory) -> [GardenItem] {
        items.filter { $0.category == category }
    }
}

/// Come l'album mette le figurine sulle pagine: sei per pagina (tre colonne per due righe), una sezione del catalogo dopo l'altra,
/// ogni sezione comincia su una pagina di sinistra. Il numero di una figurina non cambia mai (è la posizione nel catalogo).
enum GardenAlbum {
    struct Page: Equatable {
        var category: GardenCategory
        var items: [GardenItem]
        /// Quale pagina della sezione (da 1) e quante sono.
        var index: Int
        var count: Int
    }

    static let perPage = 6

    /// Quante doppie pagine sono complete (tutte le figurine trovate): ognuna allarga l'isola del giardino.
    static func completedSpreads(isFound: (String) -> Bool, catalog: [GardenItem] = GardenCatalog.items) -> Int {
        spreads(catalog: catalog).filter { spread in
            let items = spread.left.items + (spread.right?.items ?? [])
            return !items.isEmpty && items.allSatisfy { isFound($0.id) }
        }.count
    }

    /// Le doppie pagine (se una sezione ha un numero dispari di pagine, l'ultima pagina di destra manca).
    static func spreads(catalog: [GardenItem] = GardenCatalog.items) -> [(left: Page, right: Page?)] {
        var result: [(left: Page, right: Page?)] = []
        for category in GardenCategory.allCases {
            let items = catalog.filter { $0.category == category }
            guard !items.isEmpty else { continue }
            let chunks = stride(from: 0, to: items.count, by: perPage).map { Array(items[$0..<min($0 + perPage, items.count)]) }
            let pages = chunks.enumerated().map { Page(category: category, items: $1, index: $0 + 1, count: chunks.count) }
            for start in stride(from: 0, to: pages.count, by: 2) {
                result.append((pages[start], start + 1 < pages.count ? pages[start + 1] : nil))
            }
        }
        return result
    }
}

extension GardenItem {
    /// Quanto ondeggia col vento (0 = sta fermo): i fiori e l'erba un poco, le bandierine e il carillon di più. Funghi e vasi no.
    var swayStrength: Double {
        switch id {
        case "funghi", "erbe": return 0
        case "bandierine", "carillon": return 1.8
        default: return category == .flowers ? 1 : 0
        }
    }

    /// Dove sta l'acqua nel disegno (centro e mezze misure, in frazioni del disegno): ci si mettono i luccichii.
    var waterSpot: (u: Double, v: Double, halfWidth: Double, halfHeight: Double)? {
        id == "bagnetto" ? (0.50, 0.255, 0.30, 0.07) : nil
    }
}

