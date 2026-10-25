import Foundation

/// I regali di fine focus: ogni focus completato (con abbastanza studio) può far trovare una figurina per l'album del giardino.
/// Il tiro è **deterministico**: dipende solo dall'identificativo della sessione e da ciò che si è già trovato, quindi non si ritira
/// chiudendo l'app e Mac e Windows danno lo stesso risultato (si confrontano sulle stesse cartelle di esempio).
/// Solo Foundation: si collauda da solo (tests/main.swift). I numeri stanno tutti qui, in cima, per tararli.
enum GardenRarity: Int, CaseIterable, Comparable {
    case common, rare, legendary

    static func < (a: GardenRarity, b: GardenRarity) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .common: return "Comune"
        case .rare: return "Raro"
        case .legendary: return "Leggendario"
        }
    }
}

/// Quello che il giardino ricorda dei regali: quante copie di ogni cosa, e i contatori delle garanzie.
struct GardenDropState: Codable, Equatable {
    /// Quante copie di ogni oggetto si sono trovate (chi non c'è non è stato trovato).
    var found: [String: Int] = [:]
    /// Quanti focus di fila non hanno dato niente.
    var nothingInARow = 0
    /// Quanti regali dopo l'ultimo raro (o leggendario), e dopo l'ultimo leggendario.
    var sinceRare = 0
    var sinceLegendary = 0

    /// Chi comincia ha già gli oggetti che non costano niente (la «dotazione»): l'album parte da lì.
    static func starting(pool: [GardenItem] = GardenCatalog.items) -> GardenDropState {
        var state = GardenDropState()
        for item in pool where item.isStarter { state.found[item.id] = 1 }
        return state
    }
}

struct GardenDrop: Equatable {
    var item: String
    var rarity: GardenRarity
    /// Prima volta che si trova.
    var isNew: Bool
    /// Quante copie se ne hanno adesso, questa compresa.
    var copies: Int
}

/// Cosa è successo alla fine di un focus.
enum GardenGift: Equatable {
    /// Il focus non fa tirare (interrotto o troppo corto).
    case notEligible
    /// Ha fatto tirare, ma questa volta non è uscito niente.
    case nothing
    case found(GardenDrop)
}

enum GardenDrops {
    // MARK: - I numeri

    /// Quanto studio serve perché un focus faccia tirare (in secondi). Un focus interrotto non dà niente.
    static let minimumSeconds = 20 * 60
    /// Una volta su cinque non esce niente, ma mai più di due volte di fila.
    static let nothingChance = 0.20
    static let maxNothingInARow = 2
    /// Le probabilità di partenza (il resto è comune).
    static let baseRare = 0.22
    static let baseLegendary = 0.03
    /// Con la serie: da quanti giorni, quanto in più per il raro e per il leggendario.
    static let streakBonus: [(days: Int, rare: Double, legendary: Double)] = [(3, 0.04, 0), (7, 0.08, 0.005), (14, 0.12, 0.010)]
    /// Un focus lungo (da 45 minuti in su) rende un po' più probabile il raro.
    static let longFocusSeconds = 45 * 60
    static let longFocusRareBonus = 0.04
    /// Le garanzie: al massimo questi regali senza un raro (o meglio), e senza un leggendario.
    static let rarePity = 10
    static let legendaryPity = 40
    /// Dentro la rarità estratta, quanto spesso esce un oggetto che non hai ancora (se ce n'è).
    static let newItemBias = 0.80

    static func isEligible(_ session: StudySession, minimumSeconds: Int = GardenDrops.minimumSeconds) -> Bool {
        session.completed && session.seconds >= minimumSeconds
    }

    /// Le probabilità di raro e di leggendario per un focus: dipendono dai giorni di fila e da quanto è lungo.
    static func chances(streakDays: Int, seconds: Int) -> (rare: Double, legendary: Double) {
        var rare = baseRare, legendary = baseLegendary
        if let step = streakBonus.last(where: { streakDays >= $0.days }) {
            rare += step.rare
            legendary += step.legendary
        }
        if seconds >= longFocusSeconds { rare += longFocusRareBonus }
        return (min(rare, 0.5), min(legendary, 0.1))
    }

    // MARK: - Il generatore di numeri (uguale in TypeScript)

    /// FNV-1a a 32 bit sul testo (i byte UTF-8).
    static func hash(_ text: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for byte in text.utf8 {
            h ^= UInt32(byte)
            h = h &* 16_777_619
        }
        return h
    }

    /// L'hash di un testo con in più un rimescolamento (come l'ultimo passo di MurmurHash3): cambiando poco il testo (un numero in fondo) cambia
    /// tutto, anche i bit alti. Per scegliere a caso fra poche cose (le tessere, i petali…).
    static func mixedHash(_ text: String) -> UInt32 {
        var x = hash(text)
        x ^= x >> 16
        x = x &* 0x85EB_CA6B
        x ^= x >> 13
        x = x &* 0xC2B2_AE35
        x ^= x >> 16
        return x
    }

    /// Mulberry32: numeri da 0 (incluso) a 1 (escluso), sempre gli stessi per lo stesso seme.
    struct Stream {
        private var state: UInt32
        init(seed: UInt32) { state = seed }

        mutating func next() -> Double {
            state = state &+ 0x6D2B_79F5
            var t = state
            t = (t ^ (t >> 15)) &* (t | 1)
            t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
            return Double(t ^ (t >> 14)) / 4_294_967_296
        }
    }

    // MARK: - Il tiro

    /// Il regalo di un focus, o nil se questa volta non esce niente. `state` si aggiorna (copie, contatori); `pool` sono gli oggetti
    /// che possono uscire (di solito il catalogo; più avanti solo quelli dei compagni sbloccati e delle stagioni in corso).
    static func roll(sessionID: String, streakDays: Int, seconds: Int, state: inout GardenDropState,
                     pool: [GardenItem] = GardenCatalog.items, allowNothing: Bool = true) -> GardenDrop? {
        var stream = Stream(seed: hash(sessionID.uppercased()))
        let nothing = stream.next(), rarityDraw = stream.next(), newDraw = stream.next(), pickDraw = stream.next()

        if allowNothing, state.nothingInARow < maxNothingInARow, nothing < nothingChance {
            state.nothingInARow += 1
            return nil
        }
        state.nothingInARow = 0

        let (rare, legendary) = chances(streakDays: streakDays, seconds: seconds)
        var rarity: GardenRarity
        if state.sinceLegendary + 1 >= legendaryPity {
            rarity = .legendary
        } else if rarityDraw < legendary {
            rarity = .legendary
        } else if state.sinceRare + 1 >= rarePity || rarityDraw < legendary + rare {
            rarity = .rare
        } else {
            rarity = .common
        }
        // Se di quella rarità non c'è niente da far uscire, si scende (poi, in ultimo, si sale).
        var candidates = pool.filter { $0.rarity == rarity }
        if candidates.isEmpty {
            for fallback in GardenRarity.allCases.reversed() where candidates.isEmpty {
                candidates = pool.filter { $0.rarity == fallback }
                rarity = fallback
            }
        }
        guard !candidates.isEmpty else { return nil }

        // Di norma esce qualcosa che non hai (se ce n'è); ogni tanto un doppione, che va comunque nel prato.
        let fresh = candidates.filter { state.found[$0.id] == nil }
        let chosen: GardenItem
        if !fresh.isEmpty, newDraw < newItemBias || fresh.count == candidates.count {
            chosen = fresh[Int(pickDraw * Double(fresh.count))]
        } else {
            chosen = candidates[Int(pickDraw * Double(candidates.count))]
        }
        let isNew = state.found[chosen.id] == nil
        state.found[chosen.id, default: 0] += 1
        state.sinceRare = rarity >= .rare ? 0 : state.sinceRare + 1
        state.sinceLegendary = rarity == .legendary ? 0 : state.sinceLegendary + 1
        return GardenDrop(item: chosen.id, rarity: rarity, isNew: isNew, copies: state.found[chosen.id] ?? 1)
    }

    /// Tutti i regali che il registro avrebbe dato, in ordine di tempo, partendo da un album appena cominciato.
    /// Serve a provare le regole e a confrontare Mac e Windows; nell'app i tiri si fanno uno alla volta, a fine focus.
    static func simulate(sessions: [StudySession], now: Date, calendar: Calendar = StudyPeriod.calendar(),
                         pool: [GardenItem] = GardenCatalog.items) -> [(session: StudySession, drop: GardenDrop?)] {
        let streak = StudyStreak.analyze(sessions: sessions, now: now, calendar: calendar)
        var state = GardenDropState.starting(pool: pool)
        var result: [(StudySession, GardenDrop?)] = []
        let ordered = sessions.sorted {
            let a = $0.startTime(in: calendar), b = $1.startTime(in: calendar)
            return a != b ? a < b : $0.id.uuidString < $1.id.uuidString
        }
        for session in ordered where isEligible(session) {
            let day = calendar.startOfDay(for: session.startTime(in: calendar))
            let drop = roll(sessionID: session.id.uuidString, streakDays: streak.perDay[day] ?? 1, seconds: session.seconds, state: &state, pool: pool)
            result.append((session, drop))
        }
        return result
    }

    // MARK: - Le parole

    /// La frase di fine focus sul regalo (vuota se il focus non faceva tirare).
    static func line(for gift: GardenGift) -> String {
        switch gift {
        case .notEligible:
            return ""
        case .nothing:
            return "Questa volta niente figurina: la prossima non è lontana."
        case .found(let drop):
            let name = GardenCatalog.item(withID: drop.item)?.name ?? drop.item
            let number = GardenCatalog.number(of: drop.item).map { " (n. \($0))" } ?? ""
            switch (drop.rarity, drop.isNew) {
            case (.legendary, _): return "Una figurina leggendaria: \(name)\(number)!"
            case (.rare, true): return "Nuova figurina rara: \(name)\(number)!"
            case (.rare, false): return "Una figurina rara: \(name) (ne hai \(drop.copies))."
            case (.common, true): return "Nuova figurina: \(name)\(number)."
            case (.common, false): return "Hai ritrovato \(name): ne hai \(drop.copies)."
            }
        }
    }
}

extension GardenItem {
    /// Un oggetto della dotazione: c'è fin dall'inizio (non costa niente).
    var isStarter: Bool { price == 0 }

    /// La rarità, per ora ricavata dal vecchio prezzo (fino a 3 comune, da 4 a 6 raro, da 8 leggendario). Il catalogo nuovo la dirà da sé.
    var rarity: GardenRarity {
        if price <= 3 { return .common }
        if price <= 6 { return .rare }
        return .legendary
    }
}