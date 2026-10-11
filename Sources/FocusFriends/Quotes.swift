import Foundation

/// Carica le frasi di un personaggio. Cerca prima il file dell'utente, poi quello incluso nell'app.
enum Quotes {
    private static var support: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    }

    /// Dove l'utente tiene le sue frasi.
    static var userDirectory: URL { support.appendingPathComponent("FocusFriends") }
    /// Cartelle usate quando l'app si chiamava Bonsy e, prima ancora, Spidy: ancora lette (in questo ordine),
    /// così le frasi già scritte non si perdono.
    static var legacyDirectories: [URL] {
        ["Bonsy", "Spidy"].map { support.appendingPathComponent($0) }
    }

    static func userFile(for pet: Pet) -> URL {
        userDirectory.appendingPathComponent(pet.quotesUserFile)
    }

    static func load(for pet: Pet) -> [String] {
        var candidates: [URL] = [userFile(for: pet)]
        candidates += legacyDirectories.map { $0.appendingPathComponent(pet.quotesUserFile) }
        if let bundled = Bundle.main.url(forResource: pet.quotesResource, withExtension: "txt") {
            candidates.append(bundled)
        }
        for url in candidates {
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
