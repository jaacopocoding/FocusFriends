import Foundation

/// I timer che l'utente aggiunge dal menu "Personalizza…", in aggiunta a quelli di serie (focus 30 e 50,
/// pausa 5 e 10). Si ricordano alla riapertura.
struct CustomTimers {
    enum Kind: String {
        case focus
        case rest

        var title: String { self == .focus ? "Focus" : "Pausa" }
    }

    enum AddResult: Equatable {
        case added
        case outOfRange(ClosedRange<Int>)
        case alreadyExists
        case tooMany(Int)
    }

    static let builtIn: [Kind: [Int]] = [.focus: [30, 50], .rest: [5, 10]]
    /// Durate ammesse, in minuti.
    static let allowed: [Kind: ClosedRange<Int>] = [.focus: 1...180, .rest: 1...60]
    /// Quanti timer personalizzati per tipo: più di così il menu diventa una lista infinita.
    static let maxCustomPerKind = 6

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ kind: Kind) -> String { "customTimers.\(kind.rawValue)" }

    /// Solo quelli aggiunti dall'utente, in ordine crescente. Valori fuori misura o ripetuti vengono ignorati.
    func custom(_ kind: Kind) -> [Int] {
        let stored = (defaults.array(forKey: key(kind)) as? [Int]) ?? []
        let range = Self.allowed[kind]!
        let builtIn = Set(Self.builtIn[kind] ?? [])
        return Array(Set(stored.filter { range.contains($0) && !builtIn.contains($0) })).sorted()
    }

    /// Quelli di serie e quelli personalizzati, in ordine crescente.
    func all(_ kind: Kind) -> [Int] {
        Array(Set((Self.builtIn[kind] ?? []) + custom(kind))).sorted()
    }

    func isCustom(_ minutes: Int, kind: Kind) -> Bool {
        custom(kind).contains(minutes)
    }

    @discardableResult
    func add(_ minutes: Int, kind: Kind) -> AddResult {
        let range = Self.allowed[kind]!
        guard range.contains(minutes) else { return .outOfRange(range) }
        guard !all(kind).contains(minutes) else { return .alreadyExists }
        let current = custom(kind)
        guard current.count < Self.maxCustomPerKind else { return .tooMany(Self.maxCustomPerKind) }
        defaults.set((current + [minutes]).sorted(), forKey: key(kind))
        return .added
    }

    func remove(_ minutes: Int, kind: Kind) {
        defaults.set(custom(kind).filter { $0 != minutes }, forKey: key(kind))
    }
}

/// Il quadrante dei timer: dal punto in cui si trascina ai minuti.
enum TimerDialMath {
    /// `fraction` è 0..<1 del giro, da mezzogiorno in senso orario. I minuti sono multipli di `step`, tra `step`
    /// e `maxMinutes`; passando per mezzogiorno non si salta da un estremo all'altro (resta al massimo o al minimo).
    static func minutes(fraction: Double, previous: Int, maxMinutes: Int, step: Int) -> Int {
        let maxM = max(maxMinutes, step)
        let before = Double(previous) / Double(maxM)
        if before > 0.75 && fraction < 0.25 { return maxM }
        if before < 0.25 && fraction > 0.75 { return step }
        let snapped = Int((fraction * Double(maxM) / Double(step)).rounded()) * step
        return min(max(snapped, step), maxM)
    }

    /// La parte di giro da colorare per `minutes` (al massimo un giro intero).
    static func filledFraction(minutes: Int, maxMinutes: Int) -> Double {
        min(max(Double(minutes) / Double(max(maxMinutes, 1)), 0), 1)
    }
}
