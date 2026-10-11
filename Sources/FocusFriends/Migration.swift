import Foundation

/// Con il nome nuovo (Bonsy → FocusFriends) cambia anche l'identificativo dell'app, e con esso lo spazio
/// delle preferenze: al primo avvio copio quelle della vecchia app (personaggio scelto, frequenza delle frasi,
/// timer personalizzati...), senza sovrascrivere nulla di già presente. Una volta sola.
enum Migration {
    private static let oldDomain = "com.jacopo.bonsy"
    private static let doneKey = "migratedFromBonsy"

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }
        guard let old = defaults.persistentDomain(forName: oldDomain) else { return }
        for (key, value) in old where defaults.object(forKey: key) == nil {
            if key.hasPrefix("NS") || key.hasPrefix("Apple") || key.hasPrefix("com.apple") { continue }
            defaults.set(value, forKey: key)
        }
    }
}
