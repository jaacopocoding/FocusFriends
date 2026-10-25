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
        Double(GardenDrops.hash("cielo-\(salt)-\(index)")) / 4_294_967_296
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
}
