// Disegna fuori schermo i fumetti e l'orologio veri dell'app (BubbleView e TimerView) in PNG con la trasparenza, a 3×, per le immagini del README.
// Si lancia da tools/compone-readme.sh: render-fumetti <cartella> "frase 1" "frase 2" … --tempi 24:10 24:09 … → bubble1.png, bubble2.png, …, timer_2410.png, timer_2409.png, …
import AppKit

func render(_ view: NSView, scale: CGFloat, to path: String) {
    let size = view.bounds.size
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    view.displayIgnoringOpacity(view.bounds, in: context)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

@main
struct Bench {
    static func main() {
        _ = NSApplication.shared
        let out = CommandLine.arguments[1]
        let rest = Array(CommandLine.arguments.dropFirst(2))
        // le frasi, poi (dopo «--tempi») i tempi dell'orologio: timer_2410.png per «24:10»
        let split = rest.firstIndex(of: "--tempi") ?? rest.endIndex
        let phrases = Array(rest[..<split])
        let times = split < rest.endIndex ? Array(rest[(split + 1)...]) : ["24:10"]
        for (index, text) in phrases.enumerated() {
            let view = BubbleView(frame: NSRect(origin: .zero, size: BubbleView.size(for: text)))
            view.text = text
            render(view, scale: 3, to: "\(out)/bubble\(index + 1).png")
            print("bubble\(index + 1)", view.bounds.size)
        }
        for time in times {
            let timer = TimerView(frame: NSRect(origin: .zero, size: TimerWindow.size))
            timer.label = "FOCUS"
            timer.time = time
            render(timer, scale: 3, to: "\(out)/timer_\(time.replacingOccurrences(of: ":", with: "")).png")
        }
        print("orologio:", times.joined(separator: " "), TimerWindow.size)
    }
}
