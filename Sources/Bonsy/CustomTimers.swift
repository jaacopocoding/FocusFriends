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
