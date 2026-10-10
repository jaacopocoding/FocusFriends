import Foundation

/// Carica le frasi di Spidy. Prima cerca il file dell'utente, poi quello incluso nell'app.
enum Quotes {
    static let fallback = "Da grandi poteri derivano grandi responsabilità."

    static func load() -> [String] {
        let userFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Spidy/frasi.txt")
        let bundled = Bundle.main.url(forResource: "frasi", withExtension: "txt")

        for url in [userFile, bundled].compactMap({ $0 }) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = text
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            if !lines.isEmpty { return lines }
        }
        return [fallback]
    }
}
