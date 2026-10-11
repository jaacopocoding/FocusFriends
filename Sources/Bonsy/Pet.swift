import AppKit

/// Un personaggio che può stare sul desktop: immagini (una per stadio di crescita), frasi e misure.
struct Pet: Equatable {
    let id: String
    let name: String
    /// Una risorsa per stadio, dal più giovane al più cresciuto. Un solo elemento = personaggio fisso.
    let imageResources: [String]
    /// Dimensione della finestra, in punti.
    let size: NSSize
    let quotesResource: String
    /// Nome del file con cui l'utente può sostituire le frasi (in Application Support/Bonsy).
    let quotesUserFile: String
    let fallbackQuote: String
    let greeting: String
    /// Ombra a terra: larghezza come frazione di quella della finestra.
    let shadowWidthFraction: CGFloat
    /// Altezza della linea di terra nell'immagine, come frazione dell'altezza (0 = bordo inferiore).
    let groundFraction: CGFloat
    /// Porzione dell'ultima immagine da usare come icona nella barra dei menu (coordinate 0...1, origine in basso).
    let iconCrop: NSRect?
    /// Dove sta il "volto" nell'immagine usata per l'avatar del menu, come frazione della larghezza.
    var iconFocus: CGFloat = 0.5
    /// Se cammina per lo schermo. In quel caso le immagini non sono stadi di crescita ma pose:
    /// 0 = fermo, 1 e 2 = i due passi.
    var walks: Bool = false
    /// Per chi cammina: la sequenza di immagini (indici) da ripetere mentre cammina.
    var walkFrames: [Int] = [1, 2]
    /// Per chi cammina: secondi tra un fotogramma del passo e il successivo.
    var stepInterval: TimeInterval = 0.2
    /// Per chi cammina: la posa mentre parla (nil = resta ferma nella posa a riposo).
    var talkFrame: Int? = nil
    /// Le immagini guardano a destra: quando va a sinistra vengono specchiate.
    var facesRight: Bool = false
    /// Fotogrammi di quando mangia: lo fa ogni tanto, in momenti casuali, mentre gira per lo schermo.
    var eatFrames: [Int] = []
    /// Dorme ogni tanto, in momenti casuali: prima la posa "assopito", poi il respiro in ciclo.
    var sleepIntroFrame: Int? = nil
    var sleepFrames: [Int] = []
    /// Ogni tanto, in momenti casuali, fa il "popcorning": saltelli di gioia, uno dopo l'altro.
    var popcornFrames: [Int] = []

    /// Disegno mostrato mentre l'utente lo solleva col mouse (nil = si trascina in modo normale).
    var pickedResource: String? = nil
    /// Dimensione della finestra mentre è sollevato, in punti.
    var pickedSize: NSSize = .zero
    /// Dove tiene il cursore sul disegno sollevato (frazioni di larghezza e altezza, origine in basso a sinistra).
    var pickedGrab: CGPoint = CGPoint(x: 0.5, y: 0.5)

    /// Per chi cammina e cresce insieme (Pianty): quanti fotogrammi ha ogni stadio di crescita.
    /// Le immagini sono in ordine: tutti i fotogrammi del primo stadio, poi quelli del secondo, e così via;
    /// dentro lo stadio vale `walkFrames` (0 = fermo).
    var framesPerStage: Int? = nil

    var stageCount: Int { framesPerStage.map { imageResources.count / $0 } ?? (walks ? 1 : imageResources.count) }
    var finalStage: Int { stageCount - 1 }
    /// Lo stadio con cui sta fermo: l'ultimo per chi cresce, la posa "fermo" per chi cammina.
    var restStage: Int { walks ? 0 : finalStage }
    /// L'immagine con cui sta fermo, contando anche chi cresce e cammina (ultimo stadio, fotogramma fermo).
    var restImageIndex: Int { framesPerStage.map { finalStage * $0 } ?? restStage }
    var growsWithTimer: Bool { stageCount > 1 }
    /// L'immagine da cui si ricava l'icona nella barra dei menu.
    var iconResource: String {
        if framesPerStage != nil { return imageResources[restImageIndex] }
        return walks ? imageResources[0] : imageResources[finalStage]
    }

    static let spidy = Pet(
        id: "spidy",
        name: "Spidy",
        imageResources: ["spidy"],
        size: NSSize(width: 80, height: 100),
        quotesResource: "frasi",
        quotesUserFile: "frasi.txt",
        fallbackQuote: "Da grandi poteri derivano grandi responsabilità.",
        greeting: "Ciao! Il tuo amichevole Spidy di quartiere è qui.",
        shadowWidthFraction: 0.65,
        groundFraction: 0.015,
        iconCrop: NSRect(x: 0.218, y: 0.353, width: 0.67, height: 0.635)   // la testa
    )

    static let bonsy = Pet(
        id: "bonsy",
        name: "Bonsy",
        imageResources: (1...5).map { "bonsy_stage\($0)" },
        size: NSSize(width: 92, height: 114),
        quotesResource: "frasi_bonsy",
        quotesUserFile: "frasi_bonsy.txt",
        fallbackQuote: "Un passo alla volta: anch'io sono partito da un seme.",
        greeting: "Ciao! Sono Bonsy. Cresciamo insieme, con calma.",
        shadowWidthFraction: 0.72,
        groundFraction: 0.061,
        iconCrop: nil
    )

    /// Una succulenta che cresce come Bonsy e ne condivide le frasi, ma ha due piedini e cammina.
    /// Per ognuno dei 5 stadi ci sono 7 immagini: la prima è "fermo", le altre 6 sono il ciclo dei passi
    /// (generato da tools/cutout_pianty.py muovendo solo le gambe, così la pianta resta identica).
    static let pianty = Pet(
        id: "pianty",
        name: "Pianty",
        imageResources: (1...5).flatMap { stage in (1...7).map { "pianty_stage\(stage)_\($0)" } },
        size: NSSize(width: 84, height: 141),
        quotesResource: "frasi_bonsy",
        quotesUserFile: "frasi_bonsy.txt",
        fallbackQuote: "Un passo alla volta: anch'io sono partito da un seme.",
        greeting: "Ciao! Sono Pianty. Cresciamo insieme, con calma.",
        shadowWidthFraction: 0.6,
        groundFraction: 0.0176,
        iconCrop: nil,
        walks: true,
        walkFrames: [1, 2, 3, 4, 5, 6],
        stepInterval: 1.0 / 15,     // 6 fotogrammi in 0,4 s: il piede appoggiato non scivola a 42 pt/s
        facesRight: true,           // i passi sono disegnati verso destra: a sinistra si specchia
        framesPerStage: 7
    )

    /// Prova: stesse cose di Spidy (stesse frasi), ma cammina per lo schermo.
    static let simulazione = Pet(
        id: "simulazione",
        name: "Simulazione",
        imageResources: (1...3).map { "simulazione_frame\($0)" },
        size: NSSize(width: 84, height: 84),
        quotesResource: "frasi",
        quotesUserFile: "frasi.txt",
        fallbackQuote: "Da grandi poteri derivano grandi responsabilità.",
        greeting: "Ciao! Faccio due passi per lo schermo, ci vediamo in giro.",
        shadowWidthFraction: 0,           // l'ombra è già nel disegno
        groundFraction: 0,
        iconCrop: NSRect(x: 0.2, y: 0.42, width: 0.6, height: 0.56),   // la testa
        walks: true
    )

    /// Un porcellino d'India: cammina per lo schermo, mangia, dorme, saltella e incoraggia.
    static let porcellino = Pet(
        id: "porcellino",
        name: "Porcellino",
        imageResources: (1...19).map { "porcellino_frame\($0)" },   // 1-5 cammino, 6-10 mangia, 11-14 dorme, 15-19 popcorning
        size: NSSize(width: 118, height: 121),
        quotesResource: "frasi_porcellino",
        quotesUserFile: "frasi_porcellino.txt",
        fallbackQuote: "Un passo alla volta: io arrivo ovunque trotterellando.",
        greeting: "Ciao! Sono il porcellino. Facciamo due passi?",
        shadowWidthFraction: 0.7,
        groundFraction: 0.129,
        iconCrop: NSRect(x: 0.38, y: 0.28, width: 0.52, height: 0.42),   // la testa (con le orecchie)
        iconFocus: 0.60,
        walks: true,
        walkFrames: [1, 2, 3, 2],   // passo, passaggio, passo, passaggio
        talkFrame: 4,               // orecchie che saltellano
        facesRight: true,
        eatFrames: [5, 6, 7, 8, 9, 8, 7, 6],   // tiene la carota, morde, mastica, e torna indietro
        sleepIntroFrame: 10,                    // assopito
        sleepFrames: [11, 12, 11, 12, 11, 12, 13, 12],   // respiro lento, ogni tanto l'orecchio si muove
        popcornFrames: [14, 15, 16, 17, 18],     // pronto, slancio, in aria, atterraggio, pronto
        pickedResource: "porcellino_picked",   // le mani che lo sollevano, spaventato
        pickedSize: NSSize(width: 130, height: 120),
        pickedGrab: CGPoint(x: 0.30, y: 0.60)   // il cursore sta sulle mani
    )

    /// Bonsy è il personaggio principale: viene per primo ed è quello di partenza.
    static let all = [bonsy, pianty, porcellino, spidy, simulazione]

    // MARK: - Scelta ricordata

    private static let defaultsKey = "pet"

    static var saved: Pet {
        let id = UserDefaults.standard.string(forKey: defaultsKey)
        return all.first { $0.id == id } ?? bonsy
    }

    func remember() {
        UserDefaults.standard.set(id, forKey: Self.defaultsKey)
    }

    /// Stadio da mostrare durante un focus, dato quanta parte del tempo è trascorsa (0...1).
    /// Gli stadi sono quote uguali del focus: l'ultimo arriva a 4/5 del tempo.
    func stage(forProgress progress: Double) -> Int {
        guard growsWithTimer else { return 0 }
        let p = min(max(progress, 0), 0.999_999)
        return min(Int(p * Double(stageCount)), finalStage)
    }
}
