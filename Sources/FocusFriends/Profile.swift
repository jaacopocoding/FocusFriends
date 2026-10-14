import Foundation

/// Il profilo di chi usa l'app: oggi solo il nome, per personalizzare i titoli ("Il giardino di Marco").
/// Sta in `profilo.json` accanto ai dati (e "Cancella tutto…" lo toglie con il resto). Il nome NON è scritto
/// nelle sessioni: i titoli si compongono al momento di mostrarli, quindi cambiandolo cambia ovunque.
/// Solo Foundation: si collauda da solo (tests/main.swift).
final class Profile {
    static let formatVersion = 1
    static let maxNameLength = 24

    static let shared = Profile(directory: SessionLog.defaultDirectory)

    private struct Contents: Codable {
        var version: Int
        var name: String?
        var introSeen: Bool
        /// I compagni sbloccati (nil = ancora nessuno è stato scelto: niente è bloccato).
        var unlocked: [String]?
        /// Il compagno scelto all'inizio: gli altri si sbloccano dopo di lui.
        var firstCompanion: String?
    }

    private let file: URL
    private(set) var name: String?
    /// La scheda di introduzione è già stata mostrata (e chiusa).
    private(set) var introSeen = false
    /// I compagni sbloccati; nil = niente è bloccato (chi usava già l'app, o chi non ha ancora scelto).
    private(set) var unlocked: Set<String>?
    private(set) var firstCompanion: String?
    private var observers: [() -> Void] = []
    /// Il file c'è ma non si legge (o è rovinato e non si riesce a metterlo da parte): non lo sovrascrivo.
    private var isReadOnly = false

    /// Chiamata quando qualcosa non va con il file (non si legge, è rovinato, non si scrive): il testo è per chi usa
    /// l'app. I problemi che nascono in `init` arrivano appena ci si registra.
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
        file = directory.appendingPathComponent("profilo.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        guard let data = try? Data(contentsOf: file) else {
            isReadOnly = true
            report("Il file del profilo non si legge: non lo modifico.")
            return
        }
        if let contents = try? JSONDecoder().decode(Contents.self, from: data) {
            name = Self.clean(contents.name)
            introSeen = contents.introSeen
            unlocked = contents.unlocked.map(Set.init)
            firstCompanion = contents.firstCompanion
        } else {
            // Rovinato: lo metto da parte invece di sovrascriverlo alla prossima modifica.
            let aside = directory.appendingPathComponent("profilo.corrotto-\(Int(Date().timeIntervalSince1970)).json")
            do {
                try FileManager.default.moveItem(at: file, to: aside)
                report("Il file del profilo era rovinato: l'ho messo da parte come \(aside.lastPathComponent).")
            } catch {
                isReadOnly = true
                report("Il file del profilo è rovinato e non riesco a metterlo da parte: non lo modifico.")
            }
        }
    }

    func addObserver(_ observer: @escaping () -> Void) {
        observers.append(observer)
    }

    // MARK: - Il nome

    /// Spazi in eccesso e caratteri di controllo tolti, al massimo `maxNameLength` caratteri; vuoto = nessun nome.
    /// Le maiuscole restano come le ha scritte chi l'ha scritto.
    static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let visible = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || $0 == " " }
        let words = String(String.UnicodeScalarView(visible)).split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let joined = words.joined(separator: " ")
        guard !joined.isEmpty else { return nil }
        return String(joined.prefix(maxNameLength))
    }

    func setName(_ text: String?) {
        name = Self.clean(text)
        save()
    }

    func markIntroSeen() {
        introSeen = true
        save()
    }

    // MARK: - I compagni sbloccati

    /// Modalità sviluppatore: tutti i compagni sono sempre sbloccati, senza toccare il profilo. Non c'è niente nel
    /// menu: si accende da Terminale con `defaults write com.jacopo.focusfriends developerMode -bool true`
    /// (e si spegne con `-bool false`, o con `defaults delete`).
    static let developerKey = "developerMode"
    static var isDeveloper: Bool { UserDefaults.standard.bool(forKey: developerKey) }

    /// Il compagno è usabile? Se non è mai stato deciso niente, sì (non si toglie nulla a chi usava già l'app).
    func isCompanionUnlocked(_ id: String) -> Bool {
        Self.isDeveloper || (unlocked?.contains(id) ?? true)
    }

    /// Chi usava già l'app (la presentazione è già stata vista) li tiene tutti: non gli tolgo niente.
    func keepAllCompanions(_ ids: [String]) {
        guard unlocked == nil, introSeen else { return }
        unlocked = Set(ids)
        save()
    }

    /// Il primo compagno, scelto nella presentazione: è l'unico libero, gli altri si guadagnano.
    func chooseFirstCompanion(_ id: String) {
        guard unlocked == nil else { return }
        firstCompanion = id
        unlocked = [id]
        save()
    }

    /// Segna come sbloccati questi compagni (non si richiudono più, anche se poi si cancellano sessioni).
    func unlock(_ ids: [String]) {
        guard var current = unlocked, !ids.isEmpty else { return }
        let before = current
        current.formUnion(ids)
        guard current != before else { return }
        unlocked = current
        save()
    }

    /// Dimentica nome e introduzione (per "Cancella tutto…"): alla prossima apertura si ricomincia.
    func reset() {
        name = nil
        introSeen = false
        unlocked = nil
        firstCompanion = nil
        try? FileManager.default.removeItem(at: file)
        isReadOnly = false      // "Cancella tutto" è una scelta esplicita: da qui si riparte
        observers.forEach { $0() }
    }

    private func save() {
        guard !isReadOnly else { return }
        let contents = Contents(version: Self.formatVersion, name: name, introSeen: introSeen,
                                unlocked: unlocked.map { $0.sorted() }, firstCompanion: firstCompanion)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(contents).write(to: file, options: .atomic)
            writeFailureReported = false
        } catch {
            if !writeFailureReported {
                writeFailureReported = true
                report("Non riesco a salvare il profilo (nome e compagni sbloccati): \(error.localizedDescription).")
            }
        }
        observers.forEach { $0() }
    }

    // MARK: - I titoli

    /// "Il giardino di Marco", oppure "Il mio giardino" se non c'è il nome.
    var gardenTitle: String {
        name.map { "Il giardino di \($0)" } ?? "Il mio giardino"
    }

    /// "Le statistiche di Marco", oppure "Statistiche e riepilogo".
    var statsTitle: String {
        name.map { "Le statistiche di \($0)" } ?? "Statistiche e riepilogo"
    }
}
