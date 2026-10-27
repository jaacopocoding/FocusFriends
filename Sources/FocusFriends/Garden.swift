import Foundation

/// Il giardino di chi usa l'app: l'album delle figurine trovate (quante copie di ogni oggetto), quante ne ha messe sull'isola e su quale
/// tessera, dove stanno i compagni. Sta in `giardino.json` accanto ai dati (e "Cancella tutto…" lo toglie con il resto).
/// Le figurine arrivano a fine focus (GardenDrops): si trovano, non si comprano. Una copia si può mettere sull'isola, spostare, girare e
/// togliere (torna tra quelle da mettere); il numero di copie sull'isola non supera quello delle copie trovate. Le regole di dove ci
/// stanno le cose sono in GardenGrid.swift.
/// Solo Foundation: si collauda da solo (tests/main.swift).
/// Un ospite che ha già fatto visita (`GardenVisitors`): il diario ricorda quando, quante volte e cosa l'aveva attirato.
struct GardenGuest: Codable, Equatable {
    /// Il giorno della prima visita, come «2026-10-26».
    var first: String
    /// Quante volte l'hai salutato.
    var visits: Int
    /// Cosa l'aveva attirato la prima volta: il nome di una cosa o di un angolo.
    var reason: String
}

/// Cosa succede quando si saluta un ospite: la prima volta lascia un regalo.
struct GardenGuestWelcome: Equatable {
    var isFirst: Bool
    var gift: GardenDrop?
}

/// Il regalo di benvenuto che arriva con il ponte di un'isola.
struct GardenBridgeWelcome: Equatable {
    var island: String
    var item: String
    /// La copia messa sull'isola; nil se non c'era posto (resta tra quelle da mettere).
    var placement: UUID?
}

final class Garden {
    /// 4: più isole, una per compagno (ogni copia ricorda la sua, e c'è l'isola di casa). La 3 aveva un'isola sola, la 2 l'album e il prato libero, la 1 i punti
    /// spesi e gli oggetti sbloccati: si portano a 4 al primo salvataggio.
    static let formatVersion = 4
    /// Un tetto di sicurezza alle copie su ogni isola (un file a mano non deve poter riempire la memoria).
    static let maxPlacements = 150

    static let shared = Garden(directory: SessionLog.defaultDirectory)
    /// Una chiave nascosta delle preferenze, per provare i regali con focus da un minuto.
    static let quickGiftsKey = "quickGifts"
    /// Due chiavi nascoste, per rivedere la cerimonia d'arrivo (con la modalità sviluppatore è sempre tutto aperto, i ponti sono già costruiti e tutti già accolti). Il valore è
    /// l'isola, `defaults write com.jacopo.focusfriends replayBridges -string gattino`, e vale per il prossimo ingresso nel giardino, una volta sola.
    /// `replayBridges` rifà la costruzione dei ponti di quell'isola **senza toccare niente** (nessun regalo, nessun salvataggio); `replayWelcome` rifà l'arrivo intero, e il regalo
    /// è vero: una copia in più nell'album.
    static let replayBridgesKey = "replayBridges"
    static let replayWelcomeKey = "replayWelcome"

    private struct Contents: Codable {
        var version: Int
        // versione 1
        var unlocked: [String]?
        var spent: Int?
        // versione 2
        var drops: GardenDropState?
        var lastRolled: String?
        var unseen: [String]?
        var pendingGifts: Int?
        var legacySpent: Int?
        var placements: [GardenPlacement]
        var companions: [String: GardenCompanionPlace]
        /// L'isola di casa (l'id del compagno scelto all'inizio); manca nei file delle versioni precedenti, finché non si decide.
        var home: String?
        /// Gli angoli già sbloccati (si aggiunge senza cambiare la versione: chi non lo conosce lo ignora).
        var corners: [String]?
        /// Gli ospiti che hanno fatto visita (anche questo: facoltativo).
        var guests: [String: GardenGuest]?
        /// I ponti già costruiti (`GardenBridge.id`). Si scrive sempre, anche vuoto; manca solo nei file di prima (vedi `settleBridges`).
        var bridges: [String]?
        /// Le isole che hanno già ricevuto il regalo di benvenuto (la casa e quelle già aperte quando si è calcolato l'elenco, poi una per ogni compagno sbloccato). Come `bridges`.
        var welcomed: [String]?
    }

    private let file: URL
    private let directory: URL
    /// Quello che si è trovato (copie di ogni oggetto) e i contatori delle garanzie.
    private(set) var drops = GardenDropState.starting()
    /// L'ultimo focus che ha tirato: lo stesso focus non tira due volte.
    private(set) var lastRolled: String?
    /// Gli oggetti trovati e non ancora visti nell'album (portano il nastrino «NUOVA»).
    private(set) var unseen: Set<String> = []
    /// Chi aveva il giardino della versione 1: i punti non spesi diventano regali da aprire.
    private(set) var pendingGifts = 0
    /// I punti spesi nella versione 1, finché non si sono trasformati in regali (`convertLegacyPoints`).
    private var legacySpent: Int?
    /// Le copie messe su tutte le isole, dalla prima all'ultima.
    private(set) var allPlacements: [GardenPlacement] = []
    /// L'isola di casa (quella del compagno scelto all'inizio); nil finché non si sa (`adoptHome`).
    private(set) var home: String?
    /// L'isola che il giardino mostra adesso: le chiamate senza un'isola (`placements`, `islandSize`, `place`…) parlano di questa.
    private var shown: String?
    /// Dove l'utente ha messo i compagni; chi non c'è sta dove dice `GardenLayout.defaultCompanionTile`.
    private(set) var companionTiles: [String: GardenTile] = [:]
    /// Gli angoli sbloccati (`GardenCorners`), nell'ordine in cui si sono trovati.
    private(set) var corners: [String] = []
    /// Gli ospiti salutati, per specie (`GardenVisitor.id`).
    private(set) var guests: [String: GardenGuest] = [:]
    /// I ponti già costruiti (`GardenBridge.id`), nell'ordine in cui si sono costruiti. Un ponte compare solo se è qui; finché non si è calcolato (`bridgesUnsettled`) è vuoto.
    private(set) var bridges: [String] = []
    /// Le isole che hanno già ricevuto il regalo di benvenuto (`GardenBridge` non c'entra: il regalo arriva anche se non nasce nessun ponte). L'isola di casa non lo riceve, ma c'è.
    private(set) var welcomed: [String] = []
    /// Gli elenchi dei ponti e dei benvenuti non ci sono ancora: il file è di prima, o il giardino è nuovo o appena cancellato. `settleBridges` li calcola (chi ha già
    /// più compagni sbloccati ha i ponti già costruiti e i compagni già accolti, senza cerimonia) e li salva subito; finché non ci sono, non si scrivono nel file e non c'è niente da fare.
    private var bridgesUnsettled = false
    private var welcomedUnsettled = false
    /// Gli angoli che le copie sull'isola mostrata formano adesso, con le copie che li formano (si ricalcola a ogni modifica).
    private(set) var formedCorners: [String: [UUID]] = [:]
    /// Gli angoli appena sbloccati e non ancora annunciati dalla finestra del giardino (le stelline).
    private var newCorners: [String] = []
    private var observers: [() -> Void] = []
    /// Il file c'è ma non si legge (o è di una versione più nuova, o non si riesce a metterlo da parte): non lo
    /// sovrascrivo. Le modifiche valgono finché l'app resta aperta.
    private var isReadOnly = false
    /// Il file letto era di una versione vecchia: prima di riscriverlo se ne tiene una copia con questo nome.
    private var legacyBackupName: String?

    /// Chiamata quando qualcosa non va con il file: il testo è per chi usa l'app. I problemi che nascono in `init`
    /// arrivano appena ci si registra.
    var onProblem: ((String) -> Void)? {
        didSet {
            guard let handler = onProblem, !pendingProblems.isEmpty else { return }
            let pending = pendingProblems
            pendingProblems = []
            pending.forEach(handler)
        }
    }
    private var pendingProblems: [String] = []
    private var writeFailureReported = false

    private func report(_ message: String) {
        if let handler = onProblem { handler(message) } else { pendingProblems.append(message) }
    }

    init(directory: URL) {
        self.directory = directory
        file = directory.appendingPathComponent("giardino.json")
        guard FileManager.default.fileExists(atPath: file.path) else {
            startFresh()
            return
        }
        guard let data = try? Data(contentsOf: file) else {
            isReadOnly = true
            report("Il file del giardino non si legge: non lo modifico.")
            return
        }
        if let contents = try? JSONDecoder().decode(Contents.self, from: data) {
            if contents.version > Self.formatVersion {
                isReadOnly = true
                report("Il giardino è di una versione più nuova di questa app: lo leggo ma non lo modifico.")
            }
            allPlacements = Array(contents.placements.prefix(Self.maxPlacements * GardenIslands.all.count))
            home = contents.home.flatMap { GardenIslands.isKnown($0) ? $0 : nil }
            var legacyCompanions: [String: GardenSpot] = [:]
            for (petID, place) in contents.companions {
                if let col = place.col, let row = place.row {
                    companionTiles[petID] = GardenTile(col: col, row: row)
                } else if let x = place.x, let y = place.y {
                    legacyCompanions[petID] = GardenSpot(x: x, y: y)
                }
            }
            if contents.version >= 2, let saved = contents.drops {
                drops = saved
                // Mai meno copie trovate di quante ne stanno sull'isola.
                for (item, count) in Dictionary(grouping: allPlacements, by: { $0.item }).mapValues({ $0.count }) where (drops.found[item] ?? 0) < count {
                    drops.found[item] = count
                }
                lastRolled = contents.lastRolled
                unseen = Set(contents.unseen ?? [])
                pendingGifts = max(contents.pendingGifts ?? 0, 0)
                legacySpent = contents.legacySpent
            } else {
                // Versione 1: gli oggetti sbloccati restano nell'album (con tante copie quante ne aveva messe nel prato, almeno una).
                drops = GardenDropState.starting()
                for id in contents.unlocked ?? [] where GardenCatalog.item(withID: id) != nil { drops.found[id] = max(drops.found[id] ?? 0, 1) }
                for (item, count) in Dictionary(grouping: allPlacements, by: { $0.item }).mapValues({ $0.count }) {
                    drops.found[item] = max(drops.found[item] ?? 0, count)
                }
                legacySpent = max(contents.spent ?? 0, 0)
            }
            if contents.version < Self.formatVersion { legacyBackupName = "giardino-formato\(max(contents.version, 1)).json" }
            if let saved = contents.bridges {
                let known = Set(GardenWorld.bridges.map(\.id))
                bridges = saved.filter { known.contains($0) }
            } else {
                bridgesUnsettled = true
            }
            if let saved = contents.welcomed {
                welcomed = saved.filter { GardenIslands.isKnown($0) }
            } else {
                welcomedUnsettled = true
            }
            // un file della 4 di prima dei ponti si tiene com'era (uno delle versioni vecchie ha già la sua copia)
            if (bridgesUnsettled || welcomedUnsettled) && legacyBackupName == nil { legacyBackupName = "giardino-prima-dei-ponti.json" }
            corners = contents.corners ?? []
            guests = contents.guests ?? [:]
            settle(legacyCompanions: legacyCompanions)
            formedCorners = GardenCorners.formed(by: placements)
        } else {
            // Rovinato: lo metto da parte invece di sovrascriverlo alla prossima modifica.
            let aside = directory.appendingPathComponent("giardino.corrotto-\(Int(Date().timeIntervalSince1970)).json")
            do {
                try FileManager.default.moveItem(at: file, to: aside)
                report("Il file del giardino era rovinato: l'ho messo da parte come \(aside.lastPathComponent).")
            } catch {
                isReadOnly = true
                report("Il file del giardino è rovinato e non riesco a metterlo da parte: non lo modifico.")
            }
            startFresh()
        }
    }

    /// Un giardino nuovo: l'album parte con gli oggetti della dotazione, già sull'isola.
    private func startFresh() {
        drops = GardenDropState.starting()
        lastRolled = nil
        unseen = []
        pendingGifts = 0
        legacySpent = nil
        companionTiles = [:]
        allPlacements = []
        home = nil
        shown = nil
        corners = []
        newCorners = []
        guests = [:]
        bridges = []
        welcomed = []
        bridgesUnsettled = true
        welcomedUnsettled = true
        for item in GardenCatalog.items.filter({ $0.isStarter }) {
            guard let origin = GardenLayout.starterOrigins[item.id] else { continue }
            allPlacements.append(GardenPlacement(item: item.id, tile: origin))
        }
        formedCorners = GardenCorners.formed(by: placements)
    }

    /// Dopo aver letto un file: le posizioni del prato libero (versioni 1 e 2) diventano tessere, e quello che non ci sta (fuori
    /// dall'isola, sul sentiero, sopra un'altra cosa) torna tra le copie da mettere. Isola per isola.
    private func settle(legacyCompanions: [String: GardenSpot]) {
        var occupied: [String: Set<GardenTile>] = [:]
        var sizes: [String: Int] = [:]
        func size(of island: String) -> Int {
            if let known = sizes[island] { return known }
            let made = islandSize(of: island)
            sizes[island] = made
            return made
        }
        var settled: [GardenPlacement] = []
        var onPath: [GardenPlacement] = []
        for var placement in allPlacements {
            guard let item = GardenCatalog.item(withID: placement.item) else {
                settled.append(placement)
                continue
            }
            let island = resolved(placement.island)
            let footprint = item.footprint.applying(turned: placement.turned)
            if let spot = placement.legacy {
                placement.legacy = nil
                let desired = GardenLayout.tile(fromLegacy: spot, size: size(of: island))
                guard let origin = GardenLayout.nearestOrigin(to: desired, footprint: footprint, size: size(of: island), occupied: occupied[island] ?? [], island: island) else { continue }
                placement.tile = origin
            } else if !GardenLayout.canPlace(footprint, at: placement.tile, size: size(of: island), occupied: occupied[island] ?? [], island: island) {
                // se è sul sentiero dell'isola (che può essere cambiato) si sposta dopo, quando tutte le altre hanno il loro posto; fuori dall'isola o sopra
                // un'altra cosa no: torna tra quelle da mettere
                let path = Set(GardenPaths.tiles(island: island, size: size(of: island))).union(GardenLandmarks.tiles(island: island))
                let covered = GardenLayout.tiles(of: footprint, at: placement.tile)
                if covered.allSatisfy({ GardenIsland.contains($0, size: size(of: island)) }) && covered.contains(where: { path.contains($0) }) { onPath.append(placement) }
                continue
            }
            occupied[island, default: []].formUnion(GardenLayout.tiles(of: footprint, at: placement.tile))
            settled.append(placement)
        }
        for var placement in onPath {
            guard let item = GardenCatalog.item(withID: placement.item) else { continue }
            let island = resolved(placement.island)
            let footprint = item.footprint.applying(turned: placement.turned)
            guard let origin = GardenLayout.nearestOrigin(to: placement.tile, footprint: footprint, size: size(of: island), occupied: occupied[island] ?? [], island: island) else { continue }
            placement.tile = origin
            occupied[island, default: []].formUnion(GardenLayout.tiles(of: footprint, at: origin))
            settled.append(placement)
        }
        allPlacements = settled
        // i compagni del prato libero: sull'isola di casa
        for (petID, spot) in legacyCompanions {
            let desired = GardenLayout.tile(fromLegacy: spot, size: size(of: homeIsland))
            companionTiles[petID] = GardenLayout.nearestWalkable(to: desired, size: size(of: homeIsland), occupied: occupied[homeIsland] ?? []) ?? desired
        }
    }

    // MARK: - Le isole

    /// L'isola di casa: quella del compagno scelto all'inizio.
    var homeIsland: String { home ?? GardenIslands.fallbackHome }
    /// L'isola che il giardino sta mostrando (di norma quella di casa).
    var shownIsland: String { shown ?? homeIsland }

    /// Sceglie quale isola mostrare (un id che non è di un'isola non conta). Le chiamate senza un'isola (`placements`, `islandSize`, `place`…) parlano di questa.
    func showIsland(_ id: String) {
        guard GardenIslands.isKnown(id), id != shownIsland else { return }
        shown = id
        updateCorners()
        observers.forEach { $0() }
    }

    /// Decide l'isola di casa, una volta sola: quella del compagno scelto all'inizio (per chi aveva già il giardino, il compagno che usa). Le copie che
    /// non avevano ancora un'isola (un giardino delle versioni precedenti, o appena cominciato) stanno lì.
    func adoptHome(_ id: String) {
        guard home == nil, GardenIslands.isKnown(id) else { return }
        home = id
        for index in allPlacements.indices where allPlacements[index].island.isEmpty { allPlacements[index].island = id }
        relocateOffPath(on: id)
        save()
    }

    /// Le copie di un'isola che stanno sul suo sentiero (ogni isola ha il suo) vanno sulla tessera libera più vicina.
    private func relocateOffPath(on island: String) {
        let size = islandSize(of: island)
        for index in allPlacements.indices where resolved(allPlacements[index].island) == island {
            guard let item = GardenCatalog.item(withID: allPlacements[index].item) else { continue }
            let footprint = item.footprint.applying(turned: allPlacements[index].turned)
            let others = occupiedTiles(on: island, ignoring: allPlacements[index].id)
            if !GardenLayout.canPlace(footprint, at: allPlacements[index].tile, size: size, occupied: others, island: island),
               let origin = GardenLayout.nearestOrigin(to: allPlacements[index].tile, footprint: footprint, size: size, occupied: others, island: island) {
                allPlacements[index].tile = origin
            }
        }
    }

    /// L'isola vera di un id che può essere vuoto (= casa).
    private func resolved(_ island: String) -> String { island.isEmpty ? homeIsland : island }

    /// Quello che si scrive nella copia: finché non si sa qual è la casa, quella di casa resta «vuota» e segue la casa quando si decide.
    private func stored(_ island: String) -> String { home == nil && island == GardenIslands.fallbackHome ? "" : island }

    /// Le copie su un'isola, dalla prima all'ultima.
    func placements(on island: String) -> [GardenPlacement] {
        let target = resolved(island)
        return allPlacements.filter { resolved($0.island) == target }
    }

    /// Le copie sull'isola mostrata.
    var placements: [GardenPlacement] { placements(on: shownIsland) }

    func addObserver(_ observer: @escaping () -> Void) {
        observers.append(observer)
    }

    // MARK: - L'album

    /// Quante copie di un oggetto si sono trovate.
    func copies(of id: String) -> Int {
        drops.found[id] ?? 0
    }

    /// Quante sono ancora da mettere nel prato.
    func available(_ id: String) -> Int {
        max(copies(of: id) - count(of: id), 0)
    }

    /// L'oggetto è nell'album? (In modalità sviluppatore sono tutti.)
    func isFound(_ id: String) -> Bool {
        guard GardenCatalog.item(withID: id) != nil else { return false }
        return copies(of: id) > 0 || Profile.isDeveloper
    }

    /// Quanti oggetti diversi si sono trovati.
    var foundCount: Int {
        GardenCatalog.items.filter { copies(of: $0.id) > 0 }.count
    }

    /// L'album è stato aperto: le figurine nuove non sono più «NUOVE».
    func markSeen() {
        guard !unseen.isEmpty else { return }
        unseen = []
        save()
    }

    // MARK: - I regali

    /// Il regalo di un focus appena finito: tira (una volta sola per focus), e se esce qualcosa lo mette subito nel prato.
    @discardableResult
    func rollGift(for session: StudySession, streakDays: Int) -> GardenGift {
        // Per provarlo senza aspettare 20 minuti: `defaults write com.jacopo.focusfriends quickGifts -bool true` (da un minuto in su).
        let minimum = UserDefaults.standard.bool(forKey: Self.quickGiftsKey) ? SessionLog.minimumSeconds : GardenDrops.minimumSeconds
        guard GardenDrops.isEligible(session, minimumSeconds: minimum), lastRolled != session.id.uuidString else { return .notEligible }
        var state = drops
        let drop = GardenDrops.roll(sessionID: session.id.uuidString, streakDays: streakDays, seconds: session.seconds, state: &state)
        drops = state
        lastRolled = session.id.uuidString
        guard let drop else {
            save()
            return .nothing
        }
        unseen.insert(drop.item)
        autoPlace(drop.item, salt: session.id.uuidString)
        save()
        return .found(drop)
    }

    /// Chi aveva il giardino della versione 1: i punti guadagnati e non spesi diventano regali da aprire (una volta sola).
    func convertLegacyPoints(earned: Int) {
        guard let spent = legacySpent else { return }
        pendingGifts = max(earned - spent, 0)
        legacySpent = nil
        save()
    }

    /// Apre i regali in attesa: uno per punto, tutti con qualcosa dentro. Sono sempre gli stessi (dipendono solo dal numero d'ordine).
    @discardableResult
    func openPendingGifts() -> [GardenDrop] {
        guard pendingGifts > 0 else { return [] }
        var opened: [GardenDrop] = []
        var state = drops
        for number in 1...pendingGifts {
            let id = "REGALO-\(number)"
            if let drop = GardenDrops.roll(sessionID: id, streakDays: 1, seconds: GardenDrops.minimumSeconds, state: &state, allowNothing: false) {
                opened.append(drop)
                unseen.insert(drop.item)
                drops = state
                autoPlace(drop.item, salt: id)
            }
        }
        drops = state
        pendingGifts = 0
        save()
        return opened
    }

    /// Mette una copia appena trovata su una tessera libera dell'isola `island` (di casa se non si dice) scelta dal numero (sempre la stessa per lo stesso regalo).
    /// Se non c'è posto resta tra le copie da mettere. Dice quale copia ha messo.
    @discardableResult
    private func autoPlace(_ id: String, on island: String? = nil, salt: String) -> UUID? {
        let island = island ?? homeIsland
        guard placements(on: island).count < Self.maxPlacements, available(id) > 0, let item = GardenCatalog.item(withID: id) else { return nil }
        let origins = GardenLayout.freeOrigins(for: item.footprint, size: islandSize(of: island), occupied: occupiedTiles(on: island), island: island)
        guard !origins.isEmpty else { return nil }
        var stream = GardenDrops.Stream(seed: GardenDrops.hash("posto-" + salt.uppercased()))
        let placement = GardenPlacement(item: id, tile: origins[min(Int(stream.next() * Double(origins.count)), origins.count - 1)], island: stored(island))
        allPlacements.append(placement)
        return placement.id
    }

    // MARK: - I ponti e i benvenuti

    func isBuilt(_ bridge: GardenBridge) -> Bool { bridges.contains(bridge.id) }

    /// Se gli elenchi dei ponti e dei benvenuti mancano (un file di prima, un giardino nuovo o cancellato) li calcola e li salva subito: i ponti fra le isole già aperte sono già
    /// costruiti e i loro compagni già accolti, senza cerimonia e senza regali. Si chiama all'avvio, quando si sa chi è sbloccato, e di nuovo quando si apre il giardino (dopo
    /// «Cancella tutto»); se non mancano non fa niente. Va fatto subito e non al primo cambiamento: chi ha un compagno solo e chiude l'app non deve trovare, il giorno che ne
    /// sblocca un altro, il ponte già costruito e il regalo già dato.
    func settleBridges(open: Set<String>) {
        guard bridgesUnsettled || welcomedUnsettled else { return }
        if bridgesUnsettled {
            bridges = GardenWorld.pending(open: open, built: []).map(\.id)
            bridgesUnsettled = false
        }
        if welcomedUnsettled {
            // chi è aperto, chi ha già un ponte (un file della prova con i ponti ma senza benvenuti) e la casa
            let linked = Set(GardenWorld.bridges.filter { bridges.contains($0.id) }.flatMap { [$0.first, $0.second] })
            welcomed = GardenIslands.all.filter { open.contains($0) || linked.contains($0) || $0 == homeIsland }
            welcomedUnsettled = false
        }
        save()
    }

    /// I ponti da costruire adesso: fra due isole aperte e non ancora costruiti. Niente finché l'elenco non è calcolato.
    func pendingBridges(open: Set<String>) -> [GardenBridge] {
        bridgesUnsettled ? [] : GardenWorld.pending(open: open, built: Set(bridges))
    }

    /// Le isole da accogliere adesso, ognuna con il suo regalo: i compagni sbloccati dall'ultima volta, anche se non nasce nessun ponte. Niente finché l'elenco non è calcolato.
    func pendingWelcomes(open: Set<String>) -> [String] {
        welcomedUnsettled ? [] : GardenWorld.newcomers(open: open, welcomed: Set(welcomed), home: homeIsland)
    }

    /// Segna costruiti questi ponti e accolte queste isole, e dà il regalo di benvenuto a ciascuna: il primo oggetto del loro animale che non si ha ancora, o una copia in più
    /// del primo. Il regalo va sull'isola (se c'è posto). Un salvataggio solo. Ponti e isole sono due cose separate: `built` può essere vuoto (un compagno in diagonale non ha ponte)
    /// e `islands` può essere vuoto (un ponte fra due isole già accolte).
    @discardableResult
    func buildBridges(_ built: [GardenBridge], welcoming islands: [String]) -> [GardenBridgeWelcome] {
        guard !bridgesUnsettled, !welcomedUnsettled else { return [] }
        for bridge in built where !bridges.contains(bridge.id) { bridges.append(bridge.id) }
        var welcomes: [GardenBridgeWelcome] = []
        for island in islands {
            if !welcomed.contains(island) { welcomed.append(island) }
            guard let item = GardenCatalog.welcomeGift(forIsland: island, copies: { copies(of: $0) }) else { continue }
            drops.found[item, default: 0] += 1
            unseen.insert(item)
            welcomes.append(GardenBridgeWelcome(island: island, item: item, placement: autoPlace(item, on: island, salt: "BENVENUTO-" + island)))
        }
        save()
        return welcomes
    }

    // MARK: - L'isola e le copie

    /// Quante tessere per lato: 8, e una in più per ogni doppia pagina dell'album completata, fino a 10 (e mai meno di quanto serve
    /// a quello che c'è già sopra). Vale per ogni isola, per ora.
    func islandSize(of island: String) -> Int {
        let completed = GardenAlbum.completedSpreads(isFound: { isFound($0) })
        var size = GardenIsland.size(completedSpreads: completed)
        for placement in placements(on: island) {
            guard let item = GardenCatalog.item(withID: placement.item) else { continue }
            let footprint = item.footprint.applying(turned: placement.turned)
            size = max(size, placement.col + footprint.cols, placement.row + footprint.rows)
        }
        return min(size, GardenIsland.maxSize)
    }

    /// La grandezza dell'isola mostrata.
    var islandSize: Int { islandSize(of: shownIsland) }

    /// Le tessere coperte dalle copie di un'isola (senza contare `ignoring`, quella che si sta spostando).
    func occupiedTiles(on island: String, ignoring: UUID? = nil) -> Set<GardenTile> {
        GardenLayout.occupiedTiles(placements(on: island), skipping: ignoring).union(GardenLandmarks.tiles(island: island))
    }

    /// Le tessere coperte sull'isola mostrata.
    func occupiedTiles(ignoring: UUID? = nil) -> Set<GardenTile> { occupiedTiles(on: shownIsland, ignoring: ignoring) }

    /// Ci sta una copia di `id` con l'angolo in fondo su `tile`, su quell'isola (se non si dice, la mostrata)?
    func canPlace(_ id: String, at tile: GardenTile, turned: Bool = false, on island: String? = nil, ignoring: UUID? = nil) -> Bool {
        guard let item = GardenCatalog.item(withID: id) else { return false }
        let target = island.map(resolved) ?? shownIsland
        return GardenLayout.canPlace(item.footprint.applying(turned: turned), at: tile, size: islandSize(of: target), occupied: occupiedTiles(on: target, ignoring: ignoring), island: target)
    }

    /// Mette una copia dell'oggetto (se ce n'è una da mettere e ci sta). Ritorna la copia, o nil se non si può.
    @discardableResult
    func place(_ id: String, at tile: GardenTile, turned: Bool = false, on island: String? = nil) -> GardenPlacement? {
        let target = island.map(resolved) ?? shownIsland
        guard isFound(id), available(id) > 0 || Profile.isDeveloper, placements(on: target).count < Self.maxPlacements,
              canPlace(id, at: tile, turned: turned, on: target) else { return nil }
        let made = GardenPlacement(item: id, tile: tile, turned: turned, island: stored(target))
        allPlacements.append(made)
        save()
        return made
    }

    /// Mette una copia su una tessera libera qualunque (un tocco sulla cassetta): sempre la stessa per lo stesso numero di copie.
    @discardableResult
    func placeSomewhere(_ id: String, on island: String? = nil) -> GardenPlacement? {
        guard let item = GardenCatalog.item(withID: id) else { return nil }
        let target = island.map(resolved) ?? shownIsland
        let origins = GardenLayout.freeOrigins(for: item.footprint, size: islandSize(of: target), occupied: occupiedTiles(on: target), island: target)
        guard !origins.isEmpty else { return nil }
        var stream = GardenDrops.Stream(seed: GardenDrops.hash("tocco-\(placements(on: target).count)-" + id))
        return place(id, at: origins[min(Int(stream.next() * Double(origins.count)), origins.count - 1)], on: target)
    }

    /// Sposta una copia (e la gira, se `turned` c'è), sulla sua isola. Ritorna false se lì non ci sta: resta dov'era.
    /// Sposta una copia su una tessera libera, della sua isola o (se si dice `island`) di un'altra: allora cambia isola.
    @discardableResult
    func move(_ placementID: UUID, to tile: GardenTile, turned: Bool? = nil, on island: String? = nil) -> Bool {
        guard let index = allPlacements.firstIndex(where: { $0.id == placementID }) else { return false }
        let newTurned = turned ?? allPlacements[index].turned
        let target = island.map(resolved) ?? resolved(allPlacements[index].island)
        guard GardenIslands.isKnown(target),
              canPlace(allPlacements[index].item, at: tile, turned: newTurned, on: target, ignoring: placementID) else { return false }
        allPlacements[index].tile = tile
        allPlacements[index].turned = newTurned
        if island != nil && target != resolved(allPlacements[index].island) { allPlacements[index].island = stored(target) }
        updateCorners()
        save()
        return true
    }

    /// Una copia, su qualunque isola.
    func placement(withID id: UUID) -> GardenPlacement? { allPlacements.first { $0.id == id } }

    /// Gira una copia di un quarto, se così ci sta ancora.
    @discardableResult
    func rotate(_ placementID: UUID) -> Bool {
        guard let placement = allPlacements.first(where: { $0.id == placementID }) else { return false }
        return move(placementID, to: placement.tile, turned: !placement.turned)
    }

    func remove(_ placementID: UUID) {
        guard let index = allPlacements.firstIndex(where: { $0.id == placementID }) else { return }
        allPlacements.remove(at: index)
        save()
    }

    /// Quante copie di un oggetto sono sulle isole (su tutte: una copia sta in un posto solo).
    func count(of id: String) -> Int {
        allPlacements.filter { $0.item == id }.count
    }

    // MARK: - I compagni

    /// Dove sta un compagno: dove l'ha messo l'utente, o il suo posto di partenza sul sentiero (`index` è la sua posizione
    /// nell'elenco dei compagni).
    func companionTile(_ petID: String, index: Int) -> GardenTile {
        companionTiles[petID] ?? GardenLayout.defaultCompanionTile(index: index, island: GardenIslands.isKnown(petID) ? petID : nil)
    }

    func setCompanionTile(_ petID: String, to tile: GardenTile) {
        guard GardenIsland.contains(tile, size: islandSize) else { return }
        companionTiles[petID] = tile
        save()
    }

    // MARK: - Gli angoli

    /// Ricalcola gli angoli formati e sblocca quelli nuovi. Ritorna se ce n'è qualcuno di nuovo.
    @discardableResult
    private func updateCorners() -> Bool {
        var found = false
        for island in GardenIslands.all {
            // le cose fanno un angolo solo se stanno sulla stessa isola; si sblocca da qualunque isola, ma si mostrano quelli dell'isola mostrata
            let formed = GardenCorners.formed(by: placements(on: island))
            if island == shownIsland { formedCorners = formed }
            for corner in GardenCorners.all where formed[corner.id] != nil && !corners.contains(corner.id) {
                corners.append(corner.id)
                newCorners.append(corner.id)
                found = true
            }
        }
        return found
    }

    /// Gli angoli che le copie di un'isola formano adesso.
    func formedCorners(on island: String) -> [String: [UUID]] {
        GardenCorners.formed(by: placements(on: island))
    }

    /// Guarda se le copie sull'isola formano un angolo non ancora sbloccato (per quello che c'era già prima di aprire la finestra) e,
    /// se sì, lo sblocca e salva.
    func discoverCorners() {
        if updateCorners() { save() }
    }

    /// Gli angoli sbloccati da quando si è chiesto l'ultima volta: la finestra del giardino li annuncia con le stelline.
    func takeNewCorners() -> [String] {
        defer { newCorners = [] }
        return newCorners
    }

    // MARK: - Gli ospiti

    /// Saluti un ospite (`id` è la specie): la prima volta entra nel diario, con la data e il motivo, e ti lascia un regalo (qualcosa che si
    /// aggiunge all'album, sempre lo stesso per la stessa specie); le volte dopo si conta solo la visita.
    @discardableResult
    func welcomeGuest(_ id: String, day: String, reason: String) -> GardenGuestWelcome {
        if var known = guests[id] {
            known.visits += 1
            guests[id] = known
            save()
            return GardenGuestWelcome(isFirst: false, gift: nil)
        }
        guests[id] = GardenGuest(first: day, visits: 1, reason: reason)
        var state = drops
        let salt = "OSPITE-\(id)"
        let gift = GardenDrops.roll(sessionID: salt, streakDays: 1, seconds: GardenDrops.minimumSeconds, state: &state, allowNothing: false)
        if let gift {
            drops = state
            unseen.insert(gift.item)
            autoPlace(gift.item, salt: salt)
        }
        save()
        return GardenGuestWelcome(isFirst: true, gift: gift)
    }

    // MARK: - Da capo

    /// Toglie tutto (per "Cancella tutto…"): le figurine trovate, le copie e le posizioni. Si riparte dalla dotazione.
    func reset() {
        startFresh()
        try? FileManager.default.removeItem(at: file)
        isReadOnly = false      // "Cancella tutto" è una scelta esplicita: da qui si riparte
        legacyBackupName = nil
        observers.forEach { $0() }
    }

    private func save() {
        updateCorners()
        if !isReadOnly {
            if let name = legacyBackupName {
                legacyBackupName = nil
                // Il file di una versione vecchia si tiene com'era, prima di riscriverlo nella 3.
                let backup = directory.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: backup.path) { try? FileManager.default.copyItem(at: file, to: backup) }
            }
            let contents = Contents(version: Self.formatVersion, unlocked: nil, spent: nil, drops: drops, lastRolled: lastRolled,
                                    unseen: unseen.sorted(), pendingGifts: pendingGifts, legacySpent: legacySpent,
                                    placements: allPlacements,
                                    companions: companionTiles.mapValues { GardenCompanionPlace(col: $0.col, row: $0.row, x: nil, y: nil) }, home: home,
                                    corners: corners.isEmpty ? nil : corners, guests: guests.isEmpty ? nil : guests,
                                    bridges: bridgesUnsettled ? nil : bridges, welcomed: welcomedUnsettled ? nil : welcomed)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try encoder.encode(contents).write(to: file, options: .atomic)
                writeFailureReported = false
            } catch {
                if !writeFailureReported {
                    writeFailureReported = true
                    report("Non riesco a salvare il giardino: \(error.localizedDescription).")
                }
            }
        }
        observers.forEach { $0() }
    }
}
