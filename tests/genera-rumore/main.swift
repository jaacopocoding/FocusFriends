import Foundation

// Fa girare NoiseSynth (copiato da AmbientPlayer.swift) e scrive qualche misura del suono, per il confronto con TypeScript.

let args = CommandLine.arguments
guard args.count == 2 else { print("uso: genera-rumore <file di uscita>"); exit(2) }

let sampleRate: Float = 44100
let seconds = 10
let frames = Int(sampleRate) * seconds
func r(_ x: Double) -> Double { (x * 1_000_000).rounded() / 1_000_000 }

var result: [String: Any] = ["frequenza": Int(sampleRate), "secondi": seconds]
var kinds: [String: Any] = [:]
for (name, kind) in [("pioggia", Int32(1)), ("marrone", Int32(2)), ("vento", Int32(3)), ("nessuno", Int32(0))] {
    let synth = NoiseSynth(sampleRate: sampleRate)
    synth.kind = kind
    synth.targetGain = 1
    synth.fadeSeconds = 0.05
    var left = [Float](repeating: 0, count: frames), right = [Float](repeating: 0, count: frames)
    left.withUnsafeMutableBufferPointer { l in
        right.withUnsafeMutableBufferPointer { rr in
            // a blocchi da 128 campioni, come li chiede il motore audio
            var offset = 0
            while offset < frames {
                let n = min(128, frames - offset)
                synth.render(frames: n, left: l.baseAddress! + offset, right: rr.baseAddress! + offset)
                offset += n
            }
        }
    }
    func rms(_ a: ArraySlice<Float>) -> Double { sqrt(a.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(a.count, 1))) }
    // un secondo alla volta: il suono cambia piano nel tempo (vento, pioggia)
    var perSecond: [Double] = []
    for s in 0..<seconds {
        perSecond.append(r(rms(left[(s * Int(sampleRate))..<((s + 1) * Int(sampleRate))])))
    }
    kinds[name] = [
        "rmsSinistra": r(rms(left[...])), "rmsDestra": r(rms(right[...])),
        "picco": r(Double(left.map { abs($0) }.max() ?? 0)),
        "rmsPerSecondo": perSecond,
        "campioniSinistra": (0..<8).map { r(Double(left[44100 * 2 + $0])) },
        "campioniDestra": (0..<8).map { r(Double(right[44100 * 2 + $0])) },
        "primiCampioni": (0..<4).map { r(Double(left[$0])) },
    ]
}
result["suoni"] = kinds
let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
try (data + Data("\n".utf8)).write(to: URL(fileURLWithPath: args[1]))
print("Scritto \(args[1])")
