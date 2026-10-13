import Foundation

/// Il ciclo del Pomodoro: dopo quattro focus completati di fila la pausa è lunga.
/// Solo Foundation (con prove): non sa niente di timer o finestre, conta e basta.
struct BreakCycle {
    /// Quanti focus completati portano a una pausa lunga.
    static let focusesPerCycle = 4
    /// La durata della pausa lunga, in minuti.
    static let longBreakMinutes = 15
    /// Se tra un focus completato e il successivo passa più di così, il ciclo ricomincia da capo.
    static let resetAfter: TimeInterval = 2 * 3600

    private static let enabledKey = "longBreakEnabled"

    /// Spenta dal menu, la pausa è sempre quella scelta.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Quanti focus del ciclo in corso sono già stati completati (0...3).
    private(set) var completed = 0
    private var lastCompletion: Date?

    /// Un focus è stato completato: conta, e dice se la pausa che segue è quella lunga.
    /// Dopo la pausa lunga il conteggio riparte da zero.
    mutating func focusCompleted(at moment: Date) -> Bool {
        if let last = lastCompletion, moment.timeIntervalSince(last) > Self.resetAfter {
            completed = 0
        }
        lastCompletion = moment
        completed += 1
        if completed >= Self.focusesPerCycle {
            completed = 0
            return true
        }
        return false
    }

    /// Il ciclo ricomincia (per esempio quando si spegne la pausa lunga).
    mutating func reset() {
        completed = 0
        lastCompletion = nil
    }
}
