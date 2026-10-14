import Foundation

/// Da dove viene la musica del focus.
enum MusicSource: String, CaseIterable {
    /// Niente musica.
    case off
    /// I brani inclusi nell'app (assets/music, con le loro licenze nei crediti).
    case bundled
    /// I file di una cartella scelta dall'utente.
    case folder
}

/// La musica del focus: quali file ci sono e in che ordine suonano. Solo Foundation: si collauda da solo.
enum MusicLibrary {
    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "caf"]

    static func isAudio(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension.lowercased()) && !url.lastPathComponent.hasPrefix(".")
    }

    /// I file audio di una cartella (anche nelle sottocartelle), in ordine di nome. Niente file nascosti.
    static func tracks(in folder: URL, fileManager: FileManager = .default) -> [URL] {
        guard let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                      options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [URL] = []
        for case let url as URL in enumerator {
            let regular = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            if regular, isAudio(url) { found.append(url) }
        }
        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// C'è almeno un brano? Si ferma al primo trovato: per sapere solo se la cartella è vuota non serve elencarla tutta.
    static func hasTracks(in folder: URL, fileManager: FileManager = .default) -> Bool {
        guard let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                      options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return false }
        for case let url as URL in enumerator {
            let regular = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            if regular, isAudio(url) { return true }
        }
        return false
    }

    /// Un ordine casuale; il primo brano non è mai quello appena suonato (se ce n'è più di uno).
    static func shuffled<G: RandomNumberGenerator>(_ tracks: [URL], avoidingFirst last: URL?, using generator: inout G) -> [URL] {
        var result = tracks.shuffled(using: &generator)
        if result.count > 1, let last, result[0] == last {
            result.swapAt(0, 1)
        }
        return result
    }

    /// Un nome leggibile dal nome del file: «01_dreamy_night.m4a» -> «dreamy night».
    static func title(of url: URL) -> String {
        var name = url.deletingPathExtension().lastPathComponent
        if name.hasPrefix("music_") { name.removeFirst("music_".count) }
        name = name.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        // toglie un numero d'ordine iniziale ("01 ", "2. ")
        if let range = name.range(of: #"^\d+[\.\s]+"#, options: .regularExpression) { name.removeSubrange(range) }
        return name.split(whereSeparator: { $0 == " " }).joined(separator: " ")
    }
}

/// Le scelte dell'utente per la musica, ricordate tra un avvio e l'altro.
enum MusicSettings {
    /// Più basso del normale: la musica deve restare un sottofondo.
    static let defaultVolume = 0.30
    private static let sourceKey = "musicSource"
    private static let folderKey = "musicFolder"
    private static let volumeKey = "musicVolume"

    struct Saved: Equatable {
        var source: MusicSource
        var folder: URL?
        var volume: Double
    }

    static func load(_ defaults: UserDefaults = .standard) -> Saved {
        let source = defaults.string(forKey: sourceKey).flatMap(MusicSource.init(rawValue:)) ?? .off
        let folder = defaults.string(forKey: folderKey).map { URL(fileURLWithPath: $0, isDirectory: true) }
        let volume = defaults.object(forKey: volumeKey) as? Double ?? defaultVolume
        return Saved(source: source, folder: folder, volume: AmbientSettings.clamp(volume))
    }

    static func save(_ saved: Saved, _ defaults: UserDefaults = .standard) {
        defaults.set(saved.source.rawValue, forKey: sourceKey)
        defaults.set(saved.folder?.path, forKey: folderKey)
        defaults.set(AmbientSettings.clamp(saved.volume), forKey: volumeKey)
    }

    /// Cosa mostrare accanto alla riga «Musica».
    static func label(source: MusicSource, folder: URL?) -> String {
        switch source {
        case .off: return "Spenta"
        case .bundled: return "Brani inclusi"
        case .folder: return folder.map { "Cartella: \($0.lastPathComponent)" } ?? "La mia cartella"
        }
    }
}
