// Disegna fuori schermo il giardino vero dell'app (GardenView) da una cartella di dati, a un'ora e in una stagione date, per confrontarlo con
// quello di Windows (windows/test/vivo/giardino.cjs). Si lancia da tools/render-giardino.sh:
//   render <cartella dei dati> <file.png> <ora> <stagione> [casa|mondo]
// L'ora e la stagione si danno con le preferenze «registrate» (non si scrivono da nessuna parte), e senza movimento (niente vento né particelle).
import AppKit

@main
struct Render {
    static func main() {
        _ = NSApplication.shared
        let args = CommandLine.arguments
        let source = URL(fileURLWithPath: args[1]), out = args[2]
        UserDefaults.standard.register(defaults: ["gardenHour": Double(args[3])!, "gardenSeason": args[4]])
        // su una copia: il giardino e il profilo potrebbero riscriversi
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("ff-render-giardino-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        for name in ["giardino.json", "profilo.json"] {
            try? FileManager.default.copyItem(at: source.appendingPathComponent(name), to: work.appendingPathComponent(name))
        }
        let profile = Profile(directory: work)
        let garden = Garden(directory: work)
        garden.isIslandOpen = { profile.isCompanionUnlocked($0) }
        let view = GardenView(log: SessionLog(directory: work), garden: garden, profile: profile)
        view.motionReduced = { true }
        view.effectsClock = { 3 }
        if args.count > 5 && args[5] == "mondo" { view.toggleWorldView() } else { view.resetCamera() }
        view.reload()
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
        print("giardino", out, rep.pixelsWide, "×", rep.pixelsHigh)
    }
}
