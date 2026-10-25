import Foundation

/// Il cielo del giardino: che luce c'è a quest'ora e in questa stagione, quando si accendono i lampioni e compaiono le lucciole, e il
/// moto di quello che cade o vola (petali, foglie, neve, lucciole). Tutto sono numeri e funzioni del tempo, così si prova da soli (tests/main.swift)
/// e, quando il giardino arriverà su Windows, si ripete uguale. Il disegno sta in GardenWindow.swift. Solo Foundation.
struct GardenRGB: Equatable {
    var red: Double
    var green: Double
    var blue: Double
}

/// La luce di un momento: un colore che tinge la scena (da moltiplicare) e quanto è buio, che decide lampioni e lucciole.
struct GardenLight: Equatable {
    /// 0 = pieno giorno, fino a 0,55 = notte.
    var darkness: Double
    var tint: GardenRGB
    var tintStrength: Double

    /// Quanto brillano i lampioni (0 di giorno, 1 di notte): cominciano a farsi vedere al crepuscolo.
    var lamp: Double { GardenSky.smoothstep(darkness, from: 0.16, to: 0.40) }

    /// Il colore con cui si moltiplica la scena: bianco di giorno, azzurro scuro di notte.
    var multiplier: GardenRGB {
        GardenRGB(red: 255 + (tint.red - 255) * tintStrength, green: 255 + (tint.green - 255) * tintStrength, blue: 255 + (tint.blue - 255) * tintStrength)
    }
}

enum GardenParticleKind: Equatable {
    case petal, leaf, snow
}

/// Dov'è, e come si vede, una cosa che cade in un momento (coordinate della scena, origine in alto).
struct GardenParticle: Equatable {
    var x: Double
    var y: Double
    var size: Double
    var angle: Double
    var alpha: Double
    /// Un numero da 0 a 1 fisso per ogni particella, per scegliere il colore.
    var tone: Double
}

enum GardenSky {
    // MARK: - La stagione e la luce

    /// A che ora (in ore, con la virgola) sorge e tramonta il sole in una stagione: serve a far venire la sera prima d'inverno.
    static func sunrise(_ season: Season) -> Double {
        switch season {
        case .spring: return 6.5
        case .summer: return 5.5
        case .autumn: return 7.0
        case .winter: return 7.5
        }
    }

    static func sunset(_ season: Season) -> Double {
        switch season {
        case .spring: return 19.5
        case .summer: return 21.0
        case .autumn: return 18.0
        case .winter: return 17.0
        }
    }

    private static let night = GardenRGB(red: 62, green: 72, blue: 150)
    private static let none = GardenRGB(red: 255, green: 255, blue: 255)

    /// Le tappe della giornata (ora, buio, colore, quanto colora), da una mezzanotte all'altra.
    private static func keyframes(_ season: Season) -> [(hour: Double, darkness: Double, tint: GardenRGB, strength: Double)] {
        let rise = sunrise(season), set = sunset(season)
        return [
            (0, 0.55, night, 0.55),
            (rise - 1.5, 0.55, night, 0.55),
            (rise - 0.5, 0.30, GardenRGB(red: 150, green: 120, blue: 190), 0.40),
            (rise + 0.3, 0.12, GardenRGB(red: 255, green: 190, blue: 150), 0.28),
            (rise + 1.8, 0, none, 0),
            (set - 2, 0, none, 0),
            (set - 0.6, 0.06, GardenRGB(red: 255, green: 176, blue: 100), 0.25),
            (set + 0.2, 0.22, GardenRGB(red: 190, green: 112, blue: 150), 0.38),
            (set + 1.2, 0.45, GardenRGB(red: 92, green: 82, blue: 162), 0.50),
            (set + 2, 0.55, night, 0.55),
            (24, 0.55, night, 0.55),
        ]
    }

    /// La luce a un'ora del giorno (0…24, con la virgola) in una stagione: passa da una tappa all'altra senza salti.
    static func light(hour: Double, season: Season) -> GardenLight {
        let h = (hour.truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24)
        let frames = keyframes(season)
        for (a, b) in zip(frames, frames.dropFirst()) where h >= a.hour && h <= b.hour {
            let t = b.hour > a.hour ? (h - a.hour) / (b.hour - a.hour) : 0
            func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
            return GardenLight(darkness: mix(a.darkness, b.darkness),
                               tint: GardenRGB(red: mix(a.tint.red, b.tint.red), green: mix(a.tint.green, b.tint.green), blue: mix(a.tint.blue, b.tint.blue)),
                               tintStrength: mix(a.strength, b.strength))
        }
        return GardenLight(darkness: 0, tint: none, tintStrength: 0)
    }

    /// L'ora di un momento, con la virgola.
    static func hour(of date: Date, calendar: Calendar) -> Double {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60 + Double(parts.second ?? 0) / 3600
    }

    static func smoothstep(_ x: Double, from low: Double, to high: Double) -> Double {
        let t = min(max((x - low) / (high - low), 0), 1)
        return t * t * (3 - 2 * t)
    }

    // MARK: - Quello che cade e quello che vola

    /// Cosa cade in una stagione (d'estate niente: ci sono le lucciole la sera).
    static func particleKind(_ season: Season) -> GardenParticleKind? {
        switch season {
        case .spring: return .petal
        case .summer: return nil
        case .autumn: return .leaf
        case .winter: return .snow
        }
    }

    static func particleCount(_ kind: GardenParticleKind) -> Int {
        switch kind {
        case .petal: return 26
        case .leaf: return 22
        case .snow: return 70
        }
    }

    /// Un numero da 0 a 1, sempre lo stesso per la stessa particella e lo stesso scopo.
    private static func unit(_ index: Int, _ salt: Int) -> Double {
        Double(GardenDrops.mixedHash("cielo-\(salt)-\(index)")) / 4_294_967_296
    }

    private static func wrapped(_ value: Double, _ period: Double) -> Double {
        let r = value.truncatingRemainder(dividingBy: period)
        return r < 0 ? r + period : r
    }

    /// Una particella al tempo `time` (in secondi, da un momento qualunque): scende dall'alto ondeggiando e, uscita dal fondo, rientra dall'alto.
    static func particle(kind: GardenParticleKind, index: Int, time: Double, width: Double, height: Double) -> GardenParticle {
        let fall: Double, drift: Double, size: Double
        switch kind {
        case .petal: fall = 22 + unit(index, 1) * 18; drift = 8 + unit(index, 2) * 10; size = 3.2 + unit(index, 6) * 3
        case .leaf: fall = 30 + unit(index, 1) * 22; drift = 10 + unit(index, 2) * 12; size = 5 + unit(index, 6) * 4
        case .snow: fall = 20 + unit(index, 1) * 30; drift = (unit(index, 2) - 0.5) * 8; size = 1.4 + unit(index, 6) * 2.4
        }
        let sway = 10 + unit(index, 3) * 20, swayRate = 0.5 + unit(index, 4) * 0.9, phase = unit(index, 5) * 2 * Double.pi
        let y = wrapped(unit(index, 7) * (height + 40) + fall * time, height + 40) - 20
        let x = wrapped(unit(index, 8) * (width + 60) + drift * time + sin(time * swayRate + phase) * sway, width + 60) - 30
        return GardenParticle(x: x, y: y, size: size, angle: phase + time * (0.8 + unit(index, 9) * 1.6), alpha: 0.6 + unit(index, 10) * 0.4, tone: unit(index, 11))
    }

    // MARK: - Le lucciole

    /// Quante lucciole (da 0 a 1) a questa luce e in questa stagione: la sera, d'estate soprattutto, poche in autunno e per niente d'inverno.
    static func fireflyAmount(season: Season, light: GardenLight) -> Double {
        let factor: Double
        switch season {
        case .summer: factor = 1
        case .spring: factor = 0.7
        case .autumn: factor = 0.35
        case .winter: factor = 0
        }
        return smoothstep(light.darkness, from: 0.25, to: 0.5) * factor
    }

    static let fireflyCount = 24

    /// Una lucciola al tempo `time`: gira attorno al suo posto e si accende e si spegne piano.
    static func firefly(index: Int, time: Double, width: Double, height: Double) -> (x: Double, y: Double, glow: Double) {
        let ax = width * (0.12 + unit(index, 21) * 0.76), ay = height * (0.22 + unit(index, 22) * 0.62)
        let x = ax + sin(time * (0.25 + unit(index, 23) * 0.4) + unit(index, 24) * 6.28) * (18 + unit(index, 25) * 26)
        let y = ay + sin(time * (0.3 + unit(index, 26) * 0.4) + unit(index, 27) * 6.28) * (10 + unit(index, 28) * 16)
        let pulse = (sin(time * (0.7 + unit(index, 29) * 0.9) + unit(index, 30) * 6.28) + 1) / 2
        return (x, y, pow(pulse, 2.2))
    }

    // MARK: - Il vento, l'acqua e il fumo (la vita ferma)

    /// Quanto soffia il vento in una stagione (1 = molto, quasi fermo d'estate).
    static func wind(_ season: Season) -> Double {
        switch season {
        case .spring: return 0.8
        case .summer: return 0.45
        case .autumn: return 1.0
        case .winter: return 0.9
        }
    }

    /// Di quanto si sposta di lato la cima di una pianta (da −1 a 1, da moltiplicare per i pixel che si vogliono). `height` è dove si guarda,
    /// da 0 (la base, che sta ferma) a 1 (la cima, che oscilla di più). L'onda attraversa l'isola (dipende da `col` e `row`), `seed` (da 0 a 1)
    /// è diverso per ogni pianta, e un soffio più forte ogni tanto fa muovere tutto di più.
    static func sway(time: Double, col: Int, row: Int, seed: Double, height: Double) -> Double {
        let gust = 0.65 + 0.35 * sin(time * 0.11 + 1.3)
        let wave = sin(time * 0.95 - Double(col + row) * 0.45 + seed * 6.283) * 0.75 + sin(time * 2.1 + seed * 12.5) * 0.25
        return wave * gust * pow(min(max(height, 0), 1), 1.6)
    }

    static let sparkleCount = 3

    /// Un luccichio sull'acqua del bagnetto: dove (da −1 a 1 dentro l'ovale dell'acqua) e quanto brilla (brevi lampi a ritmi diversi).
    static func sparkle(index: Int, time: Double) -> (x: Double, y: Double, glow: Double) {
        let angle = unit(index, 41) * 2 * Double.pi, radius = sqrt(unit(index, 42)) * 0.78
        let flash = max(0, sin(time * (1.1 + unit(index, 43) * 1.3) + unit(index, 44) * 6.28))
        return (cos(angle) * radius, sin(angle) * radius, pow(flash, 6))
    }

    /// Il cerchio che si allarga sull'acqua, come per una goccia: ogni 3,4 secondi nasce in un punto (da −0,5 a 0,5 dell'ovale) e svanisce
    /// crescendo (`phase` da 0 a 1).
    static func ripple(time: Double, seed: Double) -> (x: Double, y: Double, phase: Double, alpha: Double) {
        let cycle = 3.4
        let shifted = time / cycle + seed
        let number = Int(shifted.rounded(.down))
        let phase = shifted - Double(number)
        return (unit(number, 51) - 0.5, (unit(number, 52) - 0.5) * 0.7, phase, (1 - phase) * min(phase * 8, 1) * 0.55)
    }

    /// Quanto fuma il camino: tanto d'inverno, un filo d'estate.
    static func smokeAmount(_ season: Season) -> Double {
        switch season {
        case .spring: return 0.5
        case .summer: return 0.15
        case .autumn: return 0.85
        case .winter: return 1
        }
    }

    static let smokeCount = 9

    /// Uno sbuffo di fumo (a partire dalla bocca del camino, in punti, con l'alto che è negativo): sale, si allarga, si piega col vento e svanisce.
    static func smoke(index: Int, time: Double, wind: Double) -> (dx: Double, dy: Double, radius: Double, alpha: Double) {
        let life = 7.0
        let shifted = (time + Double(index) * life / Double(smokeCount)) / life
        let t = shifted - shifted.rounded(.down)
        let dx = sin(t * 2.6 + Double(index) * 1.7) * 7 + t * t * 34 * wind
        return (dx, -t * 92, 3 + 15 * pow(t, 0.8), min(1, t * 7) * pow(1 - t, 1.3) * 0.6)
    }
}
