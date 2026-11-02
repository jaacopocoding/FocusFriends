// Disegna fuori schermo l'album vero dell'app (AlbumView): la copertina e alcune doppie pagine, da una cartella di dati (o da un giardino nuovo).
// Si lancia da tools/render-album.sh: render <cartella dei dati> <cartella dove scrivere>
import AppKit

@main
struct Render {
    static func main() {
        _ = NSApplication.shared
        let args = CommandLine.arguments
        let source = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2])
        // su una copia: il giardino e il profilo potrebbero riscriversi
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("ff-render-album-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        for name in ["giardino.json", "profilo.json"] {
            try? FileManager.default.copyItem(at: source.appendingPathComponent(name), to: work.appendingPathComponent(name))
        }
        let profile = Profile(directory: work)
        let garden = Garden(directory: work)
        let view = AlbumView(garden: garden, profile: profile)
        view.frame = NSRect(origin: .zero, size: AlbumView.size)
        func save(_ name: String) {
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: rep)
            try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(name).png"))
        }
        view.prepare()
        save("album-copertina")
        view.openImmediately()
        for index in [0, 2, 4] {
            view.spread = index
            view.needsDisplay = true
            save("album-pagine-\(index)")
        }
        print("album in", out.path)
    }
}
