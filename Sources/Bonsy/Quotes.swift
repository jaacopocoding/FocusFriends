import Foundation

/// Carica le frasi di un personaggio. Cerca prima il file dell'utente, poi quello incluso nell'app.
enum Quotes {
    private static var support: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    }

    /// Dove l'utente tiene le sue frasi.
    static var userDirectory: URL { support.appendingPathComponent("Bonsy") }
    /// Cartella usata quando l'app si chiamava Spidy: ancora letta, così le frasi già scritte non si perdono.
    static var legacyDirectory: URL { support.appendingPathComponent("Spidy") }

    static func userFile(for pet: Pet) -> URL {
        userDirectory.appendingPathComponent(pet.quotesUserFile)
    }

    static func load(for pet: Pet) -> [String] {
        let candidates: [URL?] = [
            userFile(for: pet),
            legacyDirectory.appendingPathComponent(pet.quotesUserFile),
            Bundle.main.url(forResource: pet.quotesResource, withExtension: "txt"),
        ]
        for url in candidates.compactMap({ $0 }) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = text
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            if !lines.isEmpty { return lines }
        }
        return [pet.fallbackQuote]
    }
}
