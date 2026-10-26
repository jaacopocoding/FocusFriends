import Foundation

/// Il giardino di chi usa l'app: l'album delle figurine trovate (quante copie di ogni oggetto), quante ne ha messe sull'isola e su quale
/// tessera, dove stanno i compagni. Sta in `giardino.json` accanto ai dati (e "Cancella tutto…" lo toglie con il resto).
/// Le figurine arrivano a fine focus (GardenDrops): si trovano, non si comprano. Una copia si può mettere sull'isola, spostare, girare e
/// togliere (torna tra quelle da mettere); il numero di copie sull'isola non supera quello delle copie trovate. Le regole di dove ci
/// stanno le cose sono in GardenGrid.swift.
/// Solo Foundation: si collauda da solo (tests/main.swift).
final class Garden {
    /// 3: l'isola a tessere (la 2 aveva l'album e il prato libero, la 1 i punti spesi e gli oggetti sbloccati: si portano a 3 al primo salvataggio).
    static let formatVersion = 3
    /// Un tetto di sicurezza alle copie nel prato (un file a mano non deve poter riempire la memoria).
    static let maxPlacements = 150

    static let shared = Garden(directory: SessionLog.defaultDirectory)
    /// Una chiave nascosta delle preferenze, per provare i regali con focus da un minuto.
    static let quickGiftsKey = "quickGifts"

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
        /// Gli angoli già sbloccati (si aggiunge senza cambiare la versione: chi non lo conosce lo ignora).
        var corners: [String]?
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
    /// Le copie messe nel prato, dalla prima all'ultima.
    private(set) var placements: [GardenPlacement] = []
    /// Dove l'utente ha messo i compagni; chi non c'è sta dove dice `GardenLayout.defaultCompanionTile`.
    private(set) var companionTiles: [String: GardenTile] = [:]
    /// Gli angoli sbloccati (`GardenCorners`), nell'ordine in cui si sono trovati.
    private(set) var corners: [String] = []
    /// Gli angoli che le copie sull'isola formano adesso, con le copie che li formano (si ricalcola a ogni modifica).
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
            placements = Array(contents.placements.prefix(Self.maxPlacements))
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
                for (item, count) in Dictionary(grouping: placements, by: { $0.item }).mapValues({ $0.count }) where (drops.found[item] ?? 0) < count {
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
                for (item, count) in Dictionary(grouping: placements, by: { $0.item }).mapValues({ $0.count }) {
                    drops.found[item] = max(drops.found[item] ?? 0, count)
                }
                legacySpent = max(contents.spent ?? 0, 0)
            }
            if contents.version < Self.formatVersion { legacyBackupName = "giardino-formato\(max(contents.version, 1)).json" }
            corners = contents.corners ?? []
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
        placements = []
        corners = []
        newCorners = []
        for item in GardenCatalog.items.filter({ $0.isStarter }) {
            guard let origin = GardenLayout.starterOrigins[item.id] else { continue }
            placements.append(GardenPlacement(item: item.id, tile: origin))
        }
        formedCorners = GardenCorners.formed(by: placements)
    }

    /// Dopo aver letto un file: le posizioni del prato libero (versioni 1 e 2) diventano tessere, e quello che non ci sta (fuori
    /// dall'isola, sul sentiero, sopra un'altra cosa) torna tra le copie da mettere.
    private func settle(legacyCompanions: [String: GardenSpot]) {
        let size = islandSize
        var occupied: Set<GardenTile> = []
        var settled: [GardenPlacement] = []
        for var placement in placements {
            guard let item = GardenCatalog.item(withID: placement.item) else {
                settled.append(placement)
                continue
            }
            let footprint = item.footprint.applying(turned: placement.turned)
            if let spot = placement.legacy {
                placement.legacy = nil
                let desired = GardenLayout.tile(fromLegacy: spot, size: size)
                guard let origin = GardenLayout.nearestOrigin(to: desired, footprint: footprint, size: size, occupied: occupied) else { continue }
                placement.tile = origin
            } else if !GardenLayout.canPlace(footprint, at: placement.tile, size: GardenIsland.maxSize, occupied: occupied) {
                continue
            }
            occupied.formUnion(GardenLayout.tiles(of: footprint, at: placement.tile))
            settled.append(placement)
        }
        placements = settled
        for (petID, spot) in legacyCompanions {
            let desired = GardenLayout.tile(fromLegacy: spot, size: size)
            companionTiles[petID] = GardenLayout.nearestWalkable(to: desired, size: size, occupied: occupied) ?? desired
        }
    }

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

    /// Mette una copia appena trovata su una tessera libera scelta dal numero (sempre la stessa per lo stesso regalo). Se non c'è posto
    /// resta tra le copie da mettere.
    private func autoPlace(_ id: String, salt: String) {
        guard placements.count < Self.maxPlacements, available(id) > 0, let item = GardenCatalog.item(withID: id) else { return }
        let origins = GardenLayout.freeOrigins(for: item.footprint, size: islandSize, occupied: GardenLayout.occupiedTiles(placements))
        guard !origins.isEmpty else { return }
        var stream = GardenDrops.Stream(seed: GardenDrops.hash("posto-" + salt.uppercased()))
        placements.append(GardenPlacement(item: id, tile: origins[min(Int(stream.next() * Double(origins.count)), origins.count - 1)]))
    }

    // MARK: - L'isola e le copie

    /// Quante tessere per lato: 8, e una in più per ogni doppia pagina dell'album completata, fino a 10 (e mai meno di quanto serve
    /// a quello che c'è già sopra).
    var islandSize: Int {
        let completed = GardenAlbum.completedSpreads(isFound: { isFound($0) })
        var size = GardenIsland.size(completedSpreads: completed)
        for placement in placements {
            guard let item = GardenCatalog.item(withID: placement.item) else { continue }
            let footprint = item.footprint.applying(turned: placement.turned)
            size = max(size, placement.col + footprint.cols, placement.row + footprint.rows)
        }
        return min(size, GardenIsland.maxSize)
    }

    /// Le tessere coperte dalle copie (senza contare `ignoring`, quella che si sta spostando).
    func occupiedTiles(ignoring: UUID? = nil) -> Set<GardenTile> {
        GardenLayout.occupiedTiles(placements, skipping: ignoring)
    }

    /// Ci sta una copia di `id` con l'angolo in fondo su `tile`?
    func canPlace(_ id: String, at tile: GardenTile, turned: Bool = false, ignoring: UUID? = nil) -> Bool {
        guard let item = GardenCatalog.item(withID: id) else { return false }
        return GardenLayout.canPlace(item.footprint.applying(turned: turned), at: tile, size: islandSize, occupied: occupiedTiles(ignoring: ignoring))
    }

    /// Mette una copia dell'oggetto (se ce n'è una da mettere e ci sta). Ritorna la copia, o nil se non si può.
    @discardableResult
    func place(_ id: String, at tile: GardenTile, turned: Bool = false) -> GardenPlacement? {
        guard isFound(id), available(id) > 0 || Profile.isDeveloper, placements.count < Self.maxPlacements,
              canPlace(id, at: tile, turned: turned) else { return nil }
        let made = GardenPlacement(item: id, tile: tile, turned: turned)
        placements.append(made)
        save()
        return made
    }

    /// Mette una copia su una tessera libera qualunque (un tocco sulla cassetta): sempre la stessa per lo stesso numero di copie.
    @discardableResult
    func placeSomewhere(_ id: String) -> GardenPlacement? {
        guard let item = GardenCatalog.item(withID: id) else { return nil }
        let origins = GardenLayout.freeOrigins(for: item.footprint, size: islandSize, occupied: occupiedTiles())
        guard !origins.isEmpty else { return nil }
        var stream = GardenDrops.Stream(seed: GardenDrops.hash("tocco-\(placements.count)-" + id))
        return place(id, at: origins[min(Int(stream.next() * Double(origins.count)), origins.count - 1)])
    }

    /// Sposta una copia (e la gira, se `turned` c'è). Ritorna false se lì non ci sta: resta dov'era.
    @discardableResult
    func move(_ placementID: UUID, to tile: GardenTile, turned: Bool? = nil) -> Bool {
        guard let index = placements.firstIndex(where: { $0.id == placementID }) else { return false }
        let newTurned = turned ?? placements[index].turned
        guard canPlace(placements[index].item, at: tile, turned: newTurned, ignoring: placementID) else { return false }
        placements[index].tile = tile
        placements[index].turned = newTurned
        save()
        return true
    }

    /// Gira una copia di un quarto, se così ci sta ancora.
    @discardableResult
    func rotate(_ placementID: UUID) -> Bool {
        guard let placement = placements.first(where: { $0.id == placementID }) else { return false }
        return move(placementID, to: placement.tile, turned: !placement.turned)
    }

    func remove(_ placementID: UUID) {
        guard let index = placements.firstIndex(where: { $0.id == placementID }) else { return }
        placements.remove(at: index)
        save()
    }

    func count(of id: String) -> Int {
        placements.filter { $0.item == id }.count
    }

    // MARK: - I compagni

    /// Dove sta un compagno: dove l'ha messo l'utente, o il suo posto di partenza sul sentiero (`index` è la sua posizione
    /// nell'elenco dei compagni).
    func companionTile(_ petID: String, index: Int) -> GardenTile {
        companionTiles[petID] ?? GardenLayout.defaultCompanionTile(index: index)
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
        formedCorners = GardenCorners.formed(by: placements)
        var found = false
        for corner in GardenCorners.all where formedCorners[corner.id] != nil && !corners.contains(corner.id) {
            corners.append(corner.id)
            newCorners.append(corner.id)
            found = true
        }
        return found
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
                                    placements: placements,
                                    companions: companionTiles.mapValues { GardenCompanionPlace(col: $0.col, row: $0.row, x: nil, y: nil) },
                                    corners: corners.isEmpty ? nil : corners)
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
