import Foundation

/// Il giardino di chi usa l'app: l'album delle figurine trovate (quante copie di ogni oggetto), quante ne ha messe nel prato e dove,
/// dove stanno i compagni. Sta in `giardino.json` accanto ai dati (e "Cancella tutto…" lo toglie con il resto).
/// Le figurine arrivano a fine focus (GardenDrops): si trovano, non si comprano. Una copia si può mettere nel prato, spostare e togliere
/// (torna nell'album); il numero di copie nel prato non supera quello delle copie trovate.
/// Solo Foundation: si collauda da solo (tests/main.swift).
final class Garden {
    /// 2: l'album e i regali (la versione 1 aveva i punti spesi e gli oggetti sbloccati: si porta a 2 al primo salvataggio).
    static let formatVersion = 2
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
        var companions: [String: GardenSpot]
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
    /// Dove l'utente ha messo i compagni; chi non c'è sta dove dice `GardenScene.defaultCompanionSpot`.
    private(set) var companionSpots: [String: GardenSpot] = [:]
    private var observers: [() -> Void] = []
    /// Il file c'è ma non si legge (o è di una versione più nuova, o non si riesce a metterlo da parte): non lo
    /// sovrascrivo. Le modifiche valgono finché l'app resta aperta.
    private var isReadOnly = false
    /// Il file letto era della versione 1: prima di riscriverlo se ne tiene una copia.
    private var needsLegacyBackup = false

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
            placements = contents.placements.prefix(Self.maxPlacements).map { placement in
                var fixed = placement
                fixed.spot = GardenScene.clamped(placement.spot)
                return fixed
            }
            companionSpots = contents.companions.mapValues { GardenScene.clamped($0) }
            if contents.version >= 2, let saved = contents.drops {
                drops = saved
                // Mai meno copie trovate di quante ne stanno nel prato.
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
                needsLegacyBackup = true
            }
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

    /// Un giardino nuovo: l'album parte con gli oggetti della dotazione, già nel prato.
    private func startFresh() {
        drops = GardenDropState.starting()
        lastRolled = nil
        unseen = []
        pendingGifts = 0
        legacySpent = nil
        companionSpots = [:]
        placements = []
        for (index, item) in GardenCatalog.items.filter({ $0.isStarter }).enumerated() {
            var made = GardenPlacement(id: UUID(), item: item.id, x: 0, y: 0)
            made.spot = GardenScene.clamped(GardenScene.defaultPlacementSpot(salt: index * 4 + 1))
            placements.append(made)
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

    /// Mette una copia appena trovata in un punto del prato scelto dal numero (sempre lo stesso per lo stesso regalo).
    private func autoPlace(_ id: String, salt: String) {
        guard placements.count < Self.maxPlacements, available(id) > 0 else { return }
        var stream = GardenDrops.Stream(seed: GardenDrops.hash("posto-" + salt.uppercased()))
        let spot = GardenSpot(x: 0.10 + 0.80 * stream.next(), y: 0.60 + 0.35 * stream.next())
        var made = GardenPlacement(id: UUID(), item: id, x: 0, y: 0)
        made.spot = GardenScene.clamped(spot)
        placements.append(made)
    }

    // MARK: - Le copie nel prato

    /// Mette una copia dell'oggetto (se ce n'è una da mettere). Ritorna la copia, o nil se non si può.
    @discardableResult
    func place(_ id: String, at spot: GardenSpot) -> GardenPlacement? {
        guard isFound(id), available(id) > 0 || Profile.isDeveloper, placements.count < Self.maxPlacements else { return nil }
        var made = GardenPlacement(id: UUID(), item: id, x: 0, y: 0)
        made.spot = GardenScene.clamped(spot)
        placements.append(made)
        save()
        return made
    }

    func move(_ placementID: UUID, to spot: GardenSpot) {
        guard let index = placements.firstIndex(where: { $0.id == placementID }) else { return }
        placements[index].spot = GardenScene.clamped(spot)
        save()
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

    /// Dove sta un compagno: dove l'ha messo l'utente, o il suo posto di partenza (`index` è la sua posizione
    /// nell'elenco dei compagni).
    func companionSpot(_ petID: String, index: Int) -> GardenSpot {
        companionSpots[petID] ?? GardenScene.defaultCompanionSpot(index: index)
    }

    func setCompanionSpot(_ petID: String, to spot: GardenSpot) {
        companionSpots[petID] = GardenScene.clamped(spot)
        save()
    }

    // MARK: - Da capo

    /// Toglie tutto (per "Cancella tutto…"): le figurine trovate, le copie e le posizioni. Si riparte dalla dotazione.
    func reset() {
        startFresh()
        try? FileManager.default.removeItem(at: file)
        isReadOnly = false      // "Cancella tutto" è una scelta esplicita: da qui si riparte
        needsLegacyBackup = false
        observers.forEach { $0() }
    }

    private func save() {
        if !isReadOnly {
            if needsLegacyBackup {
                needsLegacyBackup = false
                // Il file della versione 1 si tiene com'era, prima di riscriverlo nella 2.
                let backup = directory.appendingPathComponent("giardino-formato1.json")
                if !FileManager.default.fileExists(atPath: backup.path) { try? FileManager.default.copyItem(at: file, to: backup) }
            }
            let contents = Contents(version: Self.formatVersion, unlocked: nil, spent: nil, drops: drops, lastRolled: lastRolled,
                                    unseen: unseen.sorted(), pendingGifts: pendingGifts, legacySpent: legacySpent,
                                    placements: placements, companions: companionSpots)
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
