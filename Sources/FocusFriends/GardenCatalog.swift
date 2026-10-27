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

/// Un tipo di oggetto del giardino. Si trova una volta (a fine focus, o c'è fin dall'inizio) e poi se ne possono mettere quante sono le copie trovate.
struct GardenItem: Equatable {
    let id: String
    let name: String
    let category: GardenCategory
    /// Quanto è alto, nelle unità del disegno: sull'isola si disegna alto `height × larghezza di una tessera ÷ 115`.
    let height: Double
    /// Quanti punti costa sbloccarlo; 0 = c'è fin dall'inizio. I prezzi sono provvisori: stanno tutti qui.
    let price: Int
    /// Si disegna l'ombra sul prato (no per le cose piatte, come il tappeto).
    var castsShadow = true
    /// Quante tessere occupa (da girato, larghezza e profondità si scambiano).
    var footprint = GardenFootprint(cols: 1, rows: 1)
    /// L'isola dell'animale a cui appartiene (l'id del compagno): quell'oggetto si mette solo sulla sua isola. `nil` = universale, va su qualunque isola.
    var island: String?

    /// Può stare su questa isola? Gli universali sì, ovunque; quelli di un animale solo sulla sua.
    func fits(island other: String) -> Bool { island == nil || island == other }

    /// Il nome con l'articolo, per le frasi: «il cesto di carote», «la casa del gatto», «l'annaffiatoio». (Le cose degli animali sono dodici: la regola
    /// basta, e le prove le controllano tutte.)
    var nameWithArticle: String {
        let lower = name.prefix(1).lowercased() + name.dropFirst()
        if let first = lower.first, "aeiou".contains(first) { return "l'" + lower }
        return (lower.hasPrefix("casa ") ? "la " : "il ") + lower
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

    /// Il nome dell'immagine nel bundle (`assets/giardino/<id>.png`, copiata da build.sh).
    var resource: String { "giardino_" + id }
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
                             shadow: Bool = true, cols: Int = 1, rows: Int = 1, island: String? = nil) -> GardenItem {
        GardenItem(id: id, name: name, category: category, height: height, price: price, castsShadow: shadow,
                   footprint: GardenFootprint(cols: cols, rows: rows), island: island)
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
        item("aiuola", "Aiuola rialzata", .companions, height: 75, price: 4, cols: 2, island: "pianty"),
        item("tiragraffi", "Tiragraffi", .companions, height: 115, price: 5, island: "gattino"),
        item("casetta-uccelli", "Casa per uccelli", .companions, height: 95, price: 5, island: "ciccio"),
        item("casetta-gatto", "Casa del gatto", .companions, height: 115, price: 6, cols: 2, rows: 2, island: "gattino"),
        item("casetta-porcellino", "Casa porcellino", .companions, height: 100, price: 6, cols: 2, rows: 2, island: "porcellino"),
        // Arredi
        item("picnic", "Tappeto da picnic", .furniture, height: 70, price: 4, shadow: false, cols: 2, rows: 2),
        item("bandierine", "Bandierine", .furniture, height: 110, price: 4, cols: 2),
        item("cancelletto", "Cancelletto", .furniture, height: 95, price: 4, cols: 2),
        item("tavolino", "Tavolino da tè", .furniture, height: 95, price: 5),
        item("sdraio", "Sdraio", .furniture, height: 110, price: 5),
        item("carillon", "Carillon a vento", .furniture, height: 120, price: 5),
        item("panchina", "Panchina", .furniture, height: 95, price: 6, cols: 2),
        item("lampione", "Lampione", .furniture, height: 170, price: 6),
        item("ponticello", "Ponticello", .furniture, height: 110, price: 8, cols: 2),
        item("amaca", "Amaca", .furniture, height: 150, price: 9, cols: 2, rows: 2),
        item("altalena", "Altalena", .furniture, height: 190, price: 10, cols: 2, rows: 2),
        item("arco-rose", "Arco di rose", .furniture, height: 210, price: 12, cols: 2),
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

