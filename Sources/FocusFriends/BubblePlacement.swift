import CoreGraphics
import Foundation

/// Dove mettere il fumetto attorno al compagno. Tiene conto dello schermo e di quello che c'è già attorno (la scheda «Com'è andata?»):
/// - di norma sta sopra la testa, con la punta della codina che la tocca;
/// - se la punta non riuscirebbe ad arrivare alla testa (il compagno è vicino a un bordo dello schermo) il fumetto si **specchia**: la codina passa
///   dall'altra parte e il fumetto si apre verso il centro;
/// - se sopra non c'è posto (il compagno è in alto) sta di fianco, all'altezza più bassa che lo schermo permette;
/// - non sta mai sopra un ingombro: sceglie la disposizione che lo lascia libero.
/// Solo Foundation: si collauda da solo (tests/main.swift) e la versione per Windows (`core/bubblePlacement.ts`) deve dare gli stessi risultati.
enum BubblePlacement {
    /// Dove sta la punta della codina nel disegno del fumetto, come frazione della larghezza (a destra); specchiato è 1 − questo.
    static let tipFraction: CGFloat = 0.825
    /// Quanto la punta entra nel disegno (tra la cima e il fumetto non resta aria).
    static let overlap: CGFloat = 6
    static let screenMargin: CGFloat = 6
    static let topMargin: CGFloat = 4
    /// Quanta aria lasciare attorno a un ingombro.
    static let obstacleMargin: CGFloat = 6
    /// Quanto la punta può stare lontana dal centro del compagno senza che si cerchi un'altra disposizione.
    static let tolerance: CGFloat = 8

    enum Layout: Equatable {
        case above
        case besideLeft
        case besideRight
    }

    struct Result: Equatable {
        /// L'angolo in basso a sinistra del fumetto (coordinate dello schermo, con l'origine in basso).
        var origin: CGPoint
        /// La codina sta a destra (come nel disegno) o, specchiato, a sinistra.
        var tailOnRight: Bool
        var layout: Layout
        /// Dove cade la punta della codina.
        var tipX: CGFloat
    }

    private struct Candidate {
        var result: Result
        var rect: CGRect
        var penalty: CGFloat
    }

    /// - Parameters:
    ///   - bubble: la misura del fumetto.
    ///   - anchorX: il centro del compagno, dove deve puntare la codina.
    ///   - topY: la cima di ciò che si vede del compagno.
    ///   - pet: la finestra del compagno (per mettere il fumetto di fianco).
    ///   - screen: la parte di schermo utilizzabile.
    ///   - obstacles: quello che il fumetto non deve coprire.
    ///   - previousTailOnRight: da che parte stava la codina un momento fa: si resta lì finché va bene (niente scatti mentre il compagno cammina).
    static func place(bubble: CGSize, anchorX: CGFloat, topY: CGFloat, pet: CGRect, screen: CGRect, obstacles: [CGRect] = [],
                      previousTailOnRight: Bool? = nil) -> Result {
        let w = bubble.width, h = bubble.height
        let blocked = obstacles.map { $0.insetBy(dx: -obstacleMargin, dy: -obstacleMargin) }

        func overlapArea(_ rect: CGRect) -> CGFloat {
            blocked.reduce(0) { total, obstacle in
                let common = rect.intersection(obstacle)
                return total + (common.isNull ? 0 : common.width * common.height)
            }
        }

        func above(tailOnRight: Bool) -> Candidate {
            let wanted = anchorX - w * (tailOnRight ? tipFraction : 1 - tipFraction)
            let x = min(max(wanted, screen.minX + screenMargin), screen.maxX - w - screenMargin)
            let y = topY - overlap
            let rect = CGRect(x: x, y: y, width: w, height: h)
            let deviation = abs(x - wanted)
            let fits = y + h <= screen.maxY - topMargin
            let penalty = (fits ? 0 : 100_000) + max(deviation - tolerance, 0) * 100 + overlapArea(rect)
            return Candidate(result: Result(origin: rect.origin, tailOnRight: tailOnRight, layout: .above,
                                            tipX: x + w * (tailOnRight ? tipFraction : 1 - tipFraction)), rect: rect, penalty: penalty)
        }

        func beside(onLeft: Bool) -> Candidate {
            let wanted = onLeft ? pet.minX - w - 2 : pet.maxX + 2
            let x = min(max(wanted, screen.minX + screenMargin), screen.maxX - w - screenMargin)
            let y = max(min(topY - overlap, screen.maxY - h - topMargin), screen.minY)
            let rect = CGRect(x: x, y: y, width: w, height: h)
            // Di fianco la codina guarda il compagno: a destra se il fumetto sta alla sua sinistra.
            let tailOnRight = onLeft
            let squeezed = abs(x - wanted)                     // spinto dentro lo schermo: potrebbe finire sul compagno
            let touchesPet = rect.intersects(pet.insetBy(dx: 1, dy: 1))
            let penalty = (touchesPet ? 50_000 : 0) + squeezed * 10 + overlapArea(rect)
            return Candidate(result: Result(origin: rect.origin, tailOnRight: tailOnRight, layout: onLeft ? .besideLeft : .besideRight,
                                            tipX: x + w * (tailOnRight ? tipFraction : 1 - tipFraction)), rect: rect, penalty: penalty)
        }

        let firstTail = previousTailOnRight ?? true
        let prefersLeft = anchorX > screen.midX
        let order = [above(tailOnRight: firstTail), above(tailOnRight: !firstTail), beside(onLeft: prefersLeft), beside(onLeft: !prefersLeft)]
        // La prima disposizione senza difetti; se non ce n'è, quella con meno difetti (a parità, la prima).
        if let good = order.first(where: { $0.penalty == 0 }) { return good.result }
        return order.min(by: { $0.penalty < $1.penalty })!.result
    }
}
