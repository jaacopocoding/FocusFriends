import Foundation

/// Quanto spesso il personaggio dice una frase di sua iniziativa. Si sceglie dal menu e viene ricordato.
/// Non riguarda i messaggi del timer ("Focus finito!") né "Fai parlare": quelli ci sono sempre.
enum Chattiness: String, CaseIterable {
    case often
    case sometimes
    case rarely
    case never

    var title: String {
        switch self {
        case .often: return "Spesso"
        case .sometimes: return "Ogni tanto"
        case .rarely: return "Raramente"
        case .never: return "Mai"
        }
    }

    /// Icona di sistema (SF Symbols) mostrata accanto alla voce del menu.
    var symbolName: String {
        switch self {
        case .often: return "bubble.left.and.bubble.right"
        case .sometimes: return "bubble.left"
        case .rarely: return "ellipsis.bubble"
        case .never: return "speaker.slash"
        }
    }

    /// Pausa (in secondi) tra una frase e la successiva; nil = non parla mai di sua iniziativa.
    /// Durante un focus parla molto meno, per non distrarre.
    func interval(whileFocusing focusing: Bool) -> ClosedRange<TimeInterval>? {
        switch (self, focusing) {
        case (.never, _): return nil
        case (.often, false): return 20...55
        case (.often, true): return 120...240
        case (.sometimes, false): return 40...110       // la frequenza di sempre
        case (.sometimes, true): return 240...480
        case (.rarely, false): return 180...360
        case (.rarely, true): return 600...900
        }
    }

    private static let defaultsKey = "phraseFrequency"

    static var current: Chattiness {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(Chattiness.init(rawValue:)) ?? .sometimes }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}
