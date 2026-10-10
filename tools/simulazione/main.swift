// Genera le tre pose di "Simulazione" come PNG trasparenti: assets/simulazione/frame1..3.png
// (1 = fermo, 2 = passo sinistro, 3 = passo destro). Si lancia con tools/make_simulazione.sh
import AppKit

let poses: [SpidyPose] = [.idle, .stepLeft, .stepRight]
let pixels = 300     // 3x rispetto alla finestra: resta nitido sugli schermi Retina

for (i, pose) in poses.enumerated() {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    SpidyArt.draw(pose, in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()

    let url = URL(fileURLWithPath: "assets/simulazione/frame\(i + 1).png")
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("Scritto \(url.path)")
}
