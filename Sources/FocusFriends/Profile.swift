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
    }

    private let file: URL
    private(set) var name: String?
    /// La scheda di introduzione è già stata mostrata (e chiusa).
    private(set) var introSeen = false
    private var observers: [() -> Void] = []

    init(directory: URL) {
        file = directory.appendingPathComponent("profilo.json")
        if let data = try? Data(contentsOf: file), let contents = try? JSONDecoder().decode(Contents.self, from: data) {
            name = Self.clean(contents.name)
            introSeen = contents.introSeen
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

    /// Dimentica nome e introduzione (per "Cancella tutto…"): alla prossima apertura si ricomincia.
    func reset() {
        name = nil
        introSeen = false
        try? FileManager.default.removeItem(at: file)
        observers.forEach { $0() }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let contents = Contents(version: Self.formatVersion, name: name, introSeen: introSeen)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(contents) {
            try? data.write(to: file, options: .atomic)
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
