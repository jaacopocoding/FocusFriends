import Foundation

/// I suoni ambiente che accompagnano il focus. Sono generati dall'app (niente file, niente licenze): rumore filtrato.
/// Solo Foundation: si collauda da solo (tests/main.swift). Il motore audio è in AmbientPlayer.swift.
enum AmbientSound: String, CaseIterable {
    case none, rain, brown, wind

    var title: String {
        switch self {
        case .none: return "Nessuno"
        case .rain: return "Pioggia"
        case .brown: return "Rumore marrone"
        case .wind: return "Vento"
        }
    }

    /// Il suono dopo questo, in giro: Nessuno → Pioggia → Rumore marrone → Vento → Nessuno.
    var next: AmbientSound {
        let all = AmbientSound.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }

    var symbolName: String {
        switch self {
        case .none: return "speaker.slash"
        case .rain: return "cloud.rain"
        case .brown: return "waveform"
        case .wind: return "wind"
        }
    }
}

/// Le scelte dell'utente (suono e volume), ricordate tra un avvio e l'altro.
enum AmbientSettings {
    /// Basso di proposito: deve restare sotto la voce e la musica.
    static let defaultVolume = 0.25
    /// I livelli del menu classico.
    static let volumeSteps: [Double] = [0.10, 0.25, 0.40, 0.60]

    private static let soundKey = "ambientSound"
    private static let volumeKey = "ambientVolume"

    static func clamp(_ volume: Double) -> Double {
        guard volume.isFinite else { return defaultVolume }
        return min(max(volume, 0), 1)
    }

    static func load(_ defaults: UserDefaults = .standard) -> (sound: AmbientSound, volume: Double) {
        let sound = defaults.string(forKey: soundKey).flatMap(AmbientSound.init(rawValue:)) ?? .none
        let volume = defaults.object(forKey: volumeKey) as? Double
        return (sound, clamp(volume ?? defaultVolume))
    }

    static func save(sound: AmbientSound, volume: Double, _ defaults: UserDefaults = .standard) {
        defaults.set(sound.rawValue, forKey: soundKey)
        defaults.set(clamp(volume), forKey: volumeKey)
    }

    /// Il volume del livello più vicino (per il segno di spunta nel menu).
    static func nearestStep(to volume: Double) -> Double {
        volumeSteps.min(by: { abs($0 - volume) < abs($1 - volume) }) ?? defaultVolume
    }
}

/// La scelta del sottofondo come la vede chi studia: una sola alla volta (un suono, la musica o niente).
enum BackgroundChoice: String, CaseIterable {
    case none, rain, wind, brown, music

    var title: String {
        switch self {
        case .none: return "Nessuno"
        case .rain: return "Pioggia"
        case .wind: return "Vento"
        case .brown: return "Marrone"
        case .music: return "Musica"
        }
    }

    /// Quale scelta corrisponde a quello che è acceso adesso (il suono vince, ma i due non sono mai accesi insieme).
    static func current(ambient: AmbientSound, music: MusicSource) -> BackgroundChoice {
        switch ambient {
        case .rain: return .rain
        case .wind: return .wind
        case .brown: return .brown
        case .none: return music == .off ? .none : .music
        }
    }

    /// Il suono ambiente di questa scelta (nil se è la musica).
    var ambientSound: AmbientSound? {
        switch self {
        case .none: return AmbientSound.none
        case .rain: return .rain
        case .wind: return .wind
        case .brown: return .brown
        case .music: return nil
        }
    }
}
