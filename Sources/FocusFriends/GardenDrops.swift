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

/// Quello che il giardino ricorda dei regali: cosa si è trovato, i minuti di studio messi da parte e i contatori delle garanzie.
struct GardenDropState: Codable, Equatable {
    /// Gli oggetti trovati (chi non c'è non è stato trovato). Il numero è rimasto dalle versioni in cui si contavano le copie: da quando una cosa trovata è tua e se ne mettono
    /// quante si vuole, conta solo se c'è (1 nei file nuovi, qualunque numero da 1 in su in quelli vecchi).
    var found: [String: Int] = [:]
    /// Quanti regali dopo l'ultimo raro (o leggendario), e dopo l'ultimo leggendario.
    var sinceRare = 0
    var sinceLegendary = 0
    /// I secondi di studio (dei focus completati, da 20 minuti in su) messi da parte e non ancora spesi in un regalo. Chi non c'è ancora (un file di prima) parte da zero.
    var studyBank = 0

    init() {}

    private enum CodingKeys: String, CodingKey { case found, sinceRare, sinceLegendary, studyBank }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        found = try values.decode([String: Int].self, forKey: .found)
        sinceRare = try values.decode(Int.self, forKey: .sinceRare)
        sinceLegendary = try values.decode(Int.self, forKey: .sinceLegendary)
        studyBank = max(try values.decodeIfPresent(Int.self, forKey: .studyBank) ?? 0, 0)
    }

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
}

/// Cosa è successo alla fine di un focus.
enum GardenGift: Equatable {
    /// Il focus non conta per i regali (interrotto o troppo corto).
    case notEligible
    /// Il focus conta, i suoi minuti sono messi da parte, ma non bastano ancora per la prossima figurina.
    case progress
    /// Il focus conta, ma non c'è più niente da trovare: le figurine delle isole aperte le hai tutte (arrivano altre cose con un nuovo compagno).
    case complete
    case found(GardenDrop)
}

enum GardenDrops {
    // MARK: - I numeri

    /// Quanto studio serve perché un focus conti per i regali (in secondi). Un focus interrotto non conta.
    static let minimumSeconds = 20 * 60
    /// Il primo regalo costa 50 minuti di studio (un focus pieno) (dei focus che contano), e ogni regalo costa 8 minuti in più per ogni cosa che hai già trovato oltre alla dotazione.
    static let firstGiftMinutes = 50
    static let giftMinutesStep = 8
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

    static func isEligible(_ session: StudySession, minimumSeconds: Int = GardenDrops.minimumSeconds) -> Bool {
        session.completed && session.seconds >= minimumSeconds
    }

    /// Quanti secondi di studio costa il prossimo regalo, avendo già trovato `found` cose in tutto (la dotazione non conta: `starters`).
    static func giftCostSeconds(found: Int, starters: Int = GardenCatalog.items.filter { $0.isStarter }.count) -> Int {
        (firstGiftMinutes + giftMinutesStep * max(found - starters, 0)) * 60
    }

    /// C'è ancora qualcosa da trovare fra questi oggetti?
    static func hasSomethingToFind(state: GardenDropState, pool: [GardenItem]) -> Bool {
        pool.contains { state.found[$0.id] == nil }
    }

    /// Quanti minuti di studio mancano al prossimo regalo (0 = è già maturato e arriva al prossimo focus); nil se non c'è più niente da trovare.
    static func minutesToNextGift(state: GardenDropState, pool: [GardenItem]) -> Int? {
        guard hasSomethingToFind(state: state, pool: pool) else { return nil }
        let missing = giftCostSeconds(found: state.found.count) - state.studyBank
        return missing <= 0 ? 0 : (missing + 59) / 60
    }

    /// Quanta strada si è fatta verso il prossimo regalo, da 0 a 1; nil se non c'è più niente da trovare.
    static func giftProgress(state: GardenDropState, pool: [GardenItem]) -> Double? {
        guard hasSomethingToFind(state: state, pool: pool) else { return nil }
        return min(max(Double(state.studyBank) / Double(giftCostSeconds(found: state.found.count)), 0), 1)
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

    /// Un focus che conta: i suoi secondi vanno nella riserva (`studyBank`) e, se la riserva basta per il prossimo regalo e c'è ancora qualcosa da trovare, il regalo
    /// si tira e ne costa il prezzo. Se i regali maturati sono più di uno (si aspettava un compagno nuovo) ne arriva uno per focus. `scale` moltiplica i secondi (per provare: `quickGifts`).
    static func credit(sessionID: String, streakDays: Int, seconds: Int, state: inout GardenDropState,
                       pool: [GardenItem] = GardenCatalog.items, scale: Int = 1) -> GardenDrop? {
        state.studyBank += max(seconds, 0) * max(scale, 1)
        guard hasSomethingToFind(state: state, pool: pool) else { return nil }
        let cost = giftCostSeconds(found: state.found.count)
        guard state.studyBank >= cost else { return nil }
        guard let drop = roll(sessionID: sessionID, streakDays: streakDays, seconds: seconds, state: &state, pool: pool) else { return nil }
        state.studyBank -= cost
        return drop
    }

    /// Il regalo che esce quando maturano i minuti (e per gli ospiti e i regali dei punti, che non passano dalla riserva), o nil se non c'è più niente da trovare. `state` si
    /// aggiorna (cosa si è trovato, contatori); `pool` sono gli oggetti che possono uscire (di solito il catalogo; più avanti solo quelli dei compagni sbloccati e delle stagioni in corso).
    /// Esce sempre qualcosa che non hai ancora: una cosa trovata è tua e se ne mettono quante si vuole, un doppione non servirebbe.
    static func roll(sessionID: String, streakDays: Int, seconds: Int, state: inout GardenDropState,
                     pool: [GardenItem] = GardenCatalog.items) -> GardenDrop? {
        var stream = Stream(seed: hash(sessionID.uppercased()))
        let rarityDraw = stream.next(), pickDraw = stream.next()

        let fresh = pool.filter { state.found[$0.id] == nil }
        guard !fresh.isEmpty else { return nil }

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
        // Se di quella rarità non c'è più niente da trovare, si scende (dalla più vicina) e, in ultimo, si sale.
        var candidates: [GardenItem] = []
        let order = Array(GardenRarity.allCases.filter { $0 <= rarity }.reversed()) + GardenRarity.allCases.filter { $0 > rarity }
        for next in order where candidates.isEmpty {
            candidates = fresh.filter { $0.rarity == next }
            rarity = next
        }
        let chosen = candidates[min(Int(pickDraw * Double(candidates.count)), candidates.count - 1)]
        state.found[chosen.id] = 1
        state.sinceRare = rarity >= .rare ? 0 : state.sinceRare + 1
        state.sinceLegendary = rarity == .legendary ? 0 : state.sinceLegendary + 1
        return GardenDrop(item: chosen.id, rarity: rarity)
    }

    /// Tutti i regali che il registro avrebbe dato, in ordine di tempo, partendo da un album appena cominciato (con la riserva di minuti: un focus che conta può dare niente).
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
            let drop = credit(sessionID: session.id.uuidString, streakDays: streak.perDay[day] ?? 1, seconds: session.seconds, state: &state, pool: pool)
            result.append((session, drop))
        }
        return result
    }

    // MARK: - Le parole

    /// «Ancora 35 minuti di studio»: quanto manca, a parole (un minuto solo: «Ancora 1 minuto»).
    private static func minutesWords(_ minutes: Int) -> String {
        minutes == 1 ? "1 minuto" : "\(minutes) minuti"
    }

    /// Sotto la riga «Album» del menu e nel giardino: quanto manca alla prossima figurina. Vuota se non c'è più niente da trovare.
    static func nextGiftLine(minutesLeft: Int?) -> String {
        guard let minutesLeft else { return "" }
        return minutesLeft == 0 ? "Prossima figurina: al prossimo focus" : "Prossima figurina: ancora \(minutesWords(minutesLeft)) di studio"
    }

    /// La frase di fine focus sul regalo (vuota se il focus non contava, o se c'è già tutto). `minutesLeft` sono i minuti che mancano alla figurina dopo: si dicono sempre,
    /// perché la strada fino alla prossima sia in vista.
    /// `firstFigurine`: non se n'è ancora trovata nessuna (oltre a quelle che ci sono dall'inizio): la frase parla della «prima figurina» e,
    /// quando arriva, dice dove trovarla.
    static func line(for gift: GardenGift, minutesLeft: Int? = nil, firstFigurine: Bool = false) -> String {
        let next: String
        switch minutesLeft {
        case nil: next = ""
        case 0?: next = "Ne hai già un'altra pronta: arriva al prossimo focus."
        case let minutes?: next = "La prossima tra \(minutesWords(minutes)) di studio."
        }
        switch gift {
        case .notEligible, .complete:
            return ""
        case .progress:
            guard let minutesLeft, minutesLeft > 0 else { return "" }
            if firstFigurine { return "Mancano \(minutesWords(minutesLeft)) di studio alla prima figurina." }
            return "Ancora \(minutesWords(minutesLeft)) di studio e trovi una figurina."
        case .found(let drop):
            let name = GardenCatalog.item(withID: drop.item)?.name ?? drop.item
            let number = GardenCatalog.number(of: drop.item).map { " (n. \($0))" } ?? ""
            let sentence: String
            switch drop.rarity {
            case .legendary: sentence = "Una figurina leggendaria: \(name)\(number)!"
            case .rare: sentence = "Nuova figurina rara: \(name)\(number)!"
            case .common: sentence = "Nuova figurina: \(name)\(number)."
            }
            if firstFigurine { return sentence + " La trovi nell'album e puoi metterla nel giardino." }
            return next.isEmpty ? sentence : sentence + " " + next
        }
    }

    /// Non si è ancora trovata nessuna figurina, a parte quelle che ci sono dall'inizio.
    static func noneFoundYet(_ state: GardenDropState, pool: [GardenItem] = GardenCatalog.items) -> Bool {
        let starters = Set(pool.filter(\.isStarter).map(\.id))
        return state.found.keys.allSatisfy { starters.contains($0) }
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