// Genera un'anteprima PNG delle pose di Spidy: ./tools/preview.sh
import AppKit

let poses: [SpidyPose] = [.idle, .stepLeft, .stepRight]
let big: CGFloat = 300
let width = Int(big) * poses.count
let height = Int(big) + 130

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

NSColor(calibratedWhite: 0.93, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

for (i, pose) in poses.enumerated() {
    SpidyArt.draw(pose, in: NSRect(x: CGFloat(i) * big, y: 130, width: big, height: big))
}
// Dimensione reale sullo schermo (96 pt, a 2x per i Retina).
for (i, pose) in poses.enumerated() {
    SpidyArt.draw(pose, in: NSRect(x: 40 + CGFloat(i) * 120, y: 16, width: 96, height: 96))
}

NSGraphicsContext.restoreGraphicsState()
let out = CommandLine.arguments.dropFirst().first ?? "preview.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Scritto \(out)")
