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
    }

    // MARK: - Che cosa c'è

    /// I brani inclusi nell'app (file `music_*` nelle risorse).
    var bundledTracks: [URL] {
        guard let resources = Bundle.main.resourceURL,
              let names = try? FileManager.default.contentsOfDirectory(atPath: resources.path) else { return [] }
        return names.filter { $0.hasPrefix("music_") && MusicLibrary.isAudio(URL(fileURLWithPath: $0)) }
            .sorted().map { resources.appendingPathComponent($0) }
    }

    var folderTracks: [URL] {
        guard let folder else { return [] }
        return MusicLibrary.tracks(in: folder)
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
        // Una nuova scelta ricomincia da un brano nuovo.
        stopNow()
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
