import AVFoundation
import Foundation

/// La musica del focus: parte con il focus e si ferma a fine focus, in ordine casuale, a volume basso.
/// Suona i brani inclusi nell'app oppure i file della cartella che hai scelto.
final class MusicPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = MusicPlayer()

    private var player: AVAudioPlayer?
    private var queue: [URL] = []
    private var lastPlayed: URL?
    private var stopTimer: Timer?
    private var previewTimer: Timer?

    private(set) var source: MusicSource
    private(set) var folder: URL?
    private(set) var volume: Double
    private(set) var focusActive = false
    private(set) var currentTitle: String?

    private static let fade: TimeInterval = 2

    override init() {
        let saved = MusicSettings.load()
        source = saved.source
        folder = saved.folder
        volume = saved.volume
        super.init()
        // Un solo sottofondo alla volta: se erano accesi entrambi (scelte di una versione precedente), vince il suono.
        if source != .off, AmbientSettings.load().sound != .none {
            source = .off
            save()
        }
        prepareFolderTracks()
    }

    // MARK: - Che cosa c'è

    /// I brani inclusi nell'app (file `music_*` nelle risorse).
    var bundledTracks: [URL] {
        guard let resources = Bundle.main.resourceURL,
              let names = try? FileManager.default.contentsOfDirectory(atPath: resources.path) else { return [] }
        return names.filter { $0.hasPrefix("music_") && MusicLibrary.isAudio(URL(fileURLWithPath: $0)) }
            .sorted().map { resources.appendingPathComponent($0) }
    }

    /// L'elenco dei brani della cartella scelta, con la data di modifica della cartella a cui si riferisce: la
    /// scansione è ricorsiva e può essere lunga (dischi grandi o di rete), quindi non si rifà a ogni focus.
    private var cachedFolderTracks: (folder: URL, modified: Date?, tracks: [URL])?

    private static func modificationDate(of folder: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: folder.path))?[.modificationDate] as? Date
    }

    var folderTracks: [URL] {
        guard let folder else { return [] }
        let modified = Self.modificationDate(of: folder)
        if let cache = cachedFolderTracks, cache.folder == folder, cache.modified == modified { return cache.tracks }
        let tracks = MusicLibrary.tracks(in: folder)
        cachedFolderTracks = (folder, modified, tracks)
        return tracks
    }

    /// Nella cartella scelta c'è almeno un brano? (Senza elencarla tutta, se l'elenco non è già pronto.)
    var folderHasTracks: Bool {
        guard let folder else { return false }
        if let cache = cachedFolderTracks, cache.folder == folder, cache.modified == Self.modificationDate(of: folder) {
            return !cache.tracks.isEmpty
        }
        return MusicLibrary.hasTracks(in: folder)
    }

    /// Prepara l'elenco in secondo piano (alla scelta della cartella e all'avvio), così il primo focus non aspetta.
    func prepareFolderTracks() {
        guard source == .folder, let folder else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let modified = Self.modificationDate(of: folder)
            let tracks = MusicLibrary.tracks(in: folder)
            DispatchQueue.main.async {
                guard let self, self.folder == folder else { return }
                self.cachedFolderTracks = (folder, modified, tracks)
            }
        }
    }

    var label: String { MusicSettings.label(source: source, folder: folder) }

    // MARK: - Comandi

    func setFocusActive(_ active: Bool) {
        focusActive = active
        apply(previewing: false)
    }

    func setSource(_ new: MusicSource, folder newFolder: URL? = nil, preview: Bool = true) {
        source = new
        if let newFolder { folder = newFolder }
        save()
        // Un solo sottofondo alla volta: se accendi la musica, il suono ambiente si spegne.
        if new != .off, AmbientPlayer.shared.sound != .none { AmbientPlayer.shared.setSound(.none, preview: false) }
        // Una nuova scelta ricomincia da un brano nuovo.
        stopNow()
        prepareFolderTracks()
        apply(previewing: preview && !focusActive)
    }

    func setVolume(_ new: Double, preview: Bool = false) {
        volume = AmbientSettings.clamp(new)
        save()
        if let player, player.isPlaying { player.setVolume(Float(volume), fadeDuration: 0.2) }
        if preview && !focusActive && source != .off { apply(previewing: true) }
    }

    private func save() {
        MusicSettings.save(MusicSettings.Saved(source: source, folder: folder, volume: volume))
    }

    // MARK: - Riproduzione

    private func apply(previewing: Bool) {
        previewTimer?.invalidate()
        previewTimer = nil
        let wanted = source != .off && (focusActive || previewing)
        if wanted {
            stopTimer?.invalidate()
            stopTimer = nil
            if let player, player.isPlaying {
                player.setVolume(Float(volume), fadeDuration: 0.3)
            } else {
                playNext(fadeIn: true)
            }
            if previewing {
                previewTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
                    self?.apply(previewing: false)
                }
            }
        } else if let player, player.isPlaying {
            // Si spegne con una dissolvenza, poi si ferma del tutto.
            player.setVolume(0, fadeDuration: Self.fade)
            stopTimer?.invalidate()
            stopTimer = Timer.scheduledTimer(withTimeInterval: Self.fade + 0.2, repeats: false) { [weak self] _ in
                self?.stopNow()
            }
        }
    }

    private func stopNow() {
        stopTimer?.invalidate()
        stopTimer = nil
        player?.stop()
        player = nil
        queue = []
        currentTitle = nil
    }

    private func currentTracks() -> [URL] {
        switch source {
        case .off: return []
        case .bundled: return bundledTracks
        case .folder: return folderTracks
        }
    }

    private func playNext(fadeIn: Bool) {
        if queue.isEmpty {
            var rng = SystemRandomNumberGenerator()
            queue = MusicLibrary.shuffled(currentTracks(), avoidingFirst: lastPlayed, using: &rng)
        }
        // Salta i file che non si riescono a leggere; se nessuno si legge, si ferma.
        while let url = queue.first {
            queue.removeFirst()
            guard let candidate = try? AVAudioPlayer(contentsOf: url) else { continue }
            candidate.delegate = self
            candidate.volume = fadeIn ? 0 : Float(volume)
            guard candidate.play() else { continue }
            if fadeIn { candidate.setVolume(Float(volume), fadeDuration: Self.fade) }
            player = candidate
            lastPlayed = url
            currentTitle = MusicLibrary.title(of: url)
            return
        }
        player = nil
        currentTitle = nil
    }

    func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        guard finished === player else { return }
        if focusActive || previewTimer != nil {
            playNext(fadeIn: false)
        } else {
            stopNow()
        }
    }
}
