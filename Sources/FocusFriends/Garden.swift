import Foundation

/// Il giardino di chi usa l'app: quali oggetti ha sbloccato, quante copie ne ha messe e dove, dove stanno i
/// compagni. Sta in `giardino.json` accanto ai dati (e "Cancella tutto…" lo toglie con il resto).
/// I punti non stanno qui: si ricavano dal registro (GardenPoints); qui c'è solo quanto se n'è speso.
/// Solo Foundation: si collauda da solo (tests/main.swift).
final class Garden {
    static let formatVersion = 1
    /// Un tetto di sicurezza alle copie nel prato (un file a mano non deve poter riempire la memoria).
    static let maxPlacements = 150

    static let shared = Garden(directory: SessionLog.defaultDirectory)

    private struct Contents: Codable {
        var version: Int
        var unlocked: [String]
        var spent: Int
        var placements: [GardenPlacement]
        var companions: [String: GardenSpot]
    }

    private let file: URL
    /// Gli oggetti sbloccati con i punti (quelli che costano 0 ci sono sempre e non stanno qui).
    private(set) var unlocked: Set<String> = []
    /// I punti spesi in tutto.
    private(set) var spent = 0
    /// Le copie messe nel prato, dalla prima all'ultima.
    private(set) var placements: [GardenPlacement] = []
    /// Dove l'utente ha messo i compagni; chi non c'è sta dove dice `GardenScene.defaultCompanionSpot`.
    private(set) var companionSpots: [String: GardenSpot] = [:]
    private var observers: [() -> Void] = []
    /// Il file c'è ma non si legge (o è di una versione più nuova, o non si riesce a metterlo da parte): non lo
    /// sovrascrivo. Le modifiche valgono finché l'app resta aperta.
    private var isReadOnly = false

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
        file = directory.appendingPathComponent("giardino.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
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
            unlocked = Set(contents.unlocked)
            spent = max(contents.spent, 0)
            placements = contents.placements.prefix(Self.maxPlacements).map { placement in
                var fixed = placement
                fixed.spot = GardenScene.clamped(placement.spot)
                return fixed
            }
            companionSpots = contents.companions.mapValues { GardenScene.clamped($0) }
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
        }
    }

    func addObserver(_ observer: @escaping () -> Void) {
        observers.append(observer)
    }

    // MARK: - Gli oggetti sbloccati

    /// L'oggetto si può mettere nel prato? È gratuito, oppure sbloccato, oppure siamo in modalità sviluppatore.
    func isUnlocked(_ id: String) -> Bool {
        guard let item = GardenCatalog.item(withID: id) else { return false }
        return item.price == 0 || unlocked.contains(id) || Profile.isDeveloper
    }

    /// Sblocca un oggetto spendendo i suoi punti. `balance` sono i punti che ci sono: se non bastano non succede
    /// niente. Una volta sbloccato resta tuo, anche se poi si cancellano delle sessioni.
    @discardableResult
    func unlock(_ id: String, balance: Int) -> Bool {
        guard let item = GardenCatalog.item(withID: id), !isUnlocked(id), balance >= item.price else { return false }
        unlocked.insert(id)
        spent += item.price
        save()
        return true
    }

    // MARK: - Le copie nel prato

    /// Mette una copia dell'oggetto (se è sbloccato). Ritorna la copia, o nil se non si può.
    @discardableResult
    func place(_ id: String, at spot: GardenSpot) -> GardenPlacement? {
        guard isUnlocked(id), placements.count < Self.maxPlacements else { return nil }
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

    /// Toglie tutto (per "Cancella tutto…"): oggetti sbloccati, copie e posizioni.
    func reset() {
        unlocked = []
        spent = 0
        placements = []
        companionSpots = [:]
        try? FileManager.default.removeItem(at: file)
        isReadOnly = false      // "Cancella tutto" è una scelta esplicita: da qui si riparte
        observers.forEach { $0() }
    }

    private func save() {
        if !isReadOnly {
            let contents = Contents(version: Self.formatVersion, unlocked: unlocked.sorted(), spent: spent,
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
