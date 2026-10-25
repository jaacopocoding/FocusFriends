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

/// Un tipo di oggetto del giardino. Si sblocca una volta (con i punti, o c'è fin dall'inizio) e poi se ne possono
/// mettere quanti se ne vuole.
struct GardenItem: Equatable {
    let id: String
    let name: String
    let category: GardenCategory
    /// Quanto è alto in primo piano, nelle unità del disegno del prato (`GardenScene.size`).
    let height: Double
    /// Quanti punti costa sbloccarlo; 0 = c'è fin dall'inizio. I prezzi sono provvisori: stanno tutti qui.
    let price: Int
    /// Si disegna l'ombra sul prato (no per le cose piatte, come il tappeto).
    var castsShadow = true

    /// Il nome dell'immagine nel bundle (`assets/giardino/<id>.png`, copiata da build.sh).
    var resource: String { "giardino_" + id }
}

/// Dove sta una cosa nel prato: frazioni della scena (x da sinistra, y dall'alto), con i piedi in quel punto.
struct GardenSpot: Codable, Equatable {
    var x: Double
    var y: Double
}

/// Una copia di un oggetto messa nel prato.
struct GardenPlacement: Codable, Equatable {
    var id: UUID
    var item: String
    var x: Double
    var y: Double

    var spot: GardenSpot {
        get { GardenSpot(x: x, y: y) }
        set { x = newValue.x; y = newValue.y }
    }
}

/// La scena del giardino: il disegno del prato e le regole di dove e quanto grandi stanno le cose.
enum GardenScene {
    /// Le dimensioni del disegno di riferimento: le altezze degli oggetti sono in queste unità.
    static let size = (width: 1024.0, height: 506.0)
    /// Dove comincia il prato, come frazione dell'altezza: sopra ci sono la casetta, la siepe e le colline.
    static let horizon = 265.0 / 506.0
    /// Il prato dove si possono mettere le cose (frazioni della scena).
    static let lawn = (minX: 0.03, maxX: 0.97, minY: 0.56, maxY: 0.99)
    /// Quanto sono piccole le cose in fondo al prato rispetto a quelle davanti.
    static let farScale = 0.55

    /// La scala per la profondità: `farScale` all'orizzonte, 1 in primo piano.
    static func depthScale(y: Double) -> Double {
        let t = min(max((y - horizon) / (1 - horizon), 0), 1)
        return farScale + (1 - farScale) * t
    }

    /// Riporta un punto dentro il prato.
    static func clamped(_ spot: GardenSpot) -> GardenSpot {
        GardenSpot(x: min(max(spot.x, lawn.minX), lawn.maxX), y: min(max(spot.y, lawn.minY), lawn.maxY))
    }

    /// Il punto dove sta un compagno finché non lo si sposta: in fila sul prato, davanti.
    static func defaultCompanionSpot(index: Int) -> GardenSpot {
        let row = index / 4, column = index % 4
        return GardenSpot(x: 0.34 + 0.11 * Double(column), y: min(0.82 + 0.07 * Double(row), lawn.maxY))
    }

    /// Dove cade un oggetto appena preso dal negozio senza trascinarlo: verso il centro, un po' sfalsato ogni volta
    /// (`salt` è un numero qualunque, per non mettere due copie nello stesso punto).
    static func defaultPlacementSpot(salt: Int) -> GardenSpot {
        let n = abs(salt) % 9
        return clamped(GardenSpot(x: 0.40 + 0.05 * Double(n % 5), y: 0.72 + 0.045 * Double(n / 5 + n % 3)))
    }
}

/// Gli oggetti del negozio e le dimensioni dei compagni nel giardino.
enum GardenCatalog {
    /// I compagni nel giardino: alti quanto, in primo piano (unità della scena). Quelli senza voce sono 100.
    private static let companionHeights: [String: Double] = [
        "pianty": 120, "porcellino": 60, "ciccio": 105, "gattino": 92,
    ]

    static func companionHeight(for petID: String) -> Double { companionHeights[petID] ?? 100 }

    private static func item(_ id: String, _ name: String, _ category: GardenCategory, height: Double, price: Int,
                             shadow: Bool = true) -> GardenItem {
        GardenItem(id: id, name: name, category: category, height: height, price: price, castsShadow: shadow)
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
        item("cesto-carote", "Cesto di carote", .companions, height: 55, price: 2),
        item("annaffiatoio", "Annaffiatoio", .companions, height: 50, price: 2),
        item("cesto-cuscino", "Cesto con cuscino", .companions, height: 60, price: 3),
        item("tunnel", "Tunnel con fieno", .companions, height: 55, price: 3),
        item("altalena-uccelli", "Altalena uccelli", .companions, height: 85, price: 3),
        item("vaso-grande", "Vaso grande", .companions, height: 70, price: 3),
        item("bagnetto", "Bagnetto uccelli", .companions, height: 75, price: 4),
        item("aiuola", "Aiuola rialzata", .companions, height: 75, price: 4),
        item("tiragraffi", "Tiragraffi", .companions, height: 115, price: 5),
        item("casetta-uccelli", "Casa per uccelli", .companions, height: 95, price: 5),
        item("casetta-gatto", "Casa del gatto", .companions, height: 115, price: 6),
        item("casetta-porcellino", "Casa porcellino", .companions, height: 100, price: 6),
        // Arredi
        item("picnic", "Tappeto da picnic", .furniture, height: 70, price: 4, shadow: false),
        item("bandierine", "Bandierine", .furniture, height: 110, price: 4),
        item("cancelletto", "Cancelletto", .furniture, height: 95, price: 4),
        item("tavolino", "Tavolino da tè", .furniture, height: 95, price: 5),
        item("sdraio", "Sdraio", .furniture, height: 110, price: 5),
        item("carillon", "Carillon a vento", .furniture, height: 120, price: 5),
        item("panchina", "Panchina", .furniture, height: 95, price: 6),
        item("lampione", "Lampione", .furniture, height: 170, price: 6),
        item("ponticello", "Ponticello", .furniture, height: 110, price: 8),
        item("amaca", "Amaca", .furniture, height: 150, price: 9),
        item("altalena", "Altalena", .furniture, height: 190, price: 10),
        item("arco-rose", "Arco di rose", .furniture, height: 210, price: 12),
    ]

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
