// Il pilota automatico della prima apertura (tools/banchi/prima-volta.sh): nell'app vera, con una cartella di dati vuota e un minuto che dura un secondo,
// fa quello che farebbe chi la apre la prima volta (il nome e il compagno, il giro guidato, un focus da 50 minuti con la materia, la fine del focus)
// e a ogni passo fotografa le finestre dell'app, nella cartella FF_FOTO. Preme i pulsanti veri (performClick): niente scorciatoie nel codice dell'app.
import AppKit

enum Autopilota {
    private static var folder: String { ProcessInfo.processInfo.environment["FF_FOTO"] ?? NSTemporaryDirectory() }
    private static var shotNumber = 0
    private static var steps: [(TimeInterval, String, () -> Void)] = []

    static func start() {
        var t: TimeInterval = 0
        func at(_ delay: TimeInterval, _ name: String, _ action: @escaping () -> Void = {}) {
            t += delay
            steps.append((t, name, action))
        }
        at(2.0, "benvenuto")
        at(0.3, "nome-e-compagno") {
            field()?.stringValue = "Giulia"
            let companions = allViews().compactMap { $0 as? CompanionButton }
            log("compagni nella scheda: \(companions.count)")
            if companions.count > 3 { companions[3].performClick(nil) }
        }
        at(0.6, "iniziamo") { press(title: "Iniziamo!") }
        at(2.5, "cliccami") {}
        at(0.5, "clic-sul-compagno") {
            let pet = NSApp.windows.compactMap { $0 as? PetWindow }.first
            log("il compagno chiama: \(pet?.onCallClick != nil)")
            pet?.onCallClick?()
        }
        for step in 1...8 {
            at(1.2, "giro-\(step)") {}
            at(0.2, "giro-\(step)-avanti") { press(title: step == 8 ? "Inizia il primo focus" : "Avanti") }
        }
        at(2.0, "dopo-il-giro") {}
        at(0.5, "cinquanta") { press(label: "Focus di 50 minuti") }
        at(1.5, "materia") { field()?.stringValue = "Anatomia" }
        at(0.5, "inizia") { press(title: "Inizia") }
        at(3.0, "focus-appena-partito") {}
        at(20.0, "focus-a-meta") {}
        for s in stride(from: 0, to: 44, by: 4) { at(s == 0 ? 28.0 : 4.0, "fine-\(s)") {} }
        at(2.0, "com-e-andata") { press(title: "Fatto") }
        at(3.0, "dopo") {}
        at(2.0, "fine") { log("fatto"); NSApp.terminate(nil) }
        let start = Date()
        for (when, name, action) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + when) {
                action()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { shot(name, since: start) }
            }
        }
    }

    // MARK: - Trovare e premere

    private static func allViews() -> [NSView] {
        var result: [NSView] = []
        func walk(_ v: NSView) { result.append(v); v.subviews.forEach(walk) }
        for w in NSApp.windows where w.isVisible { if let v = w.contentView { walk(v) } }
        return result
    }

    private static func field() -> NSTextField? {
        allViews().compactMap { $0 as? NSTextField }.first { $0.isEditable && !$0.isHidden }
    }

    private static func press(title: String) {
        let buttons = allViews().compactMap { $0 as? NSButton }.filter { $0.title == title && !$0.isHidden }
        log("premo «\(title)»: \(buttons.count) trovati")
        buttons.last?.performClick(nil)
    }

    private static func press(label: String) {
        let buttons = allViews().compactMap { $0 as? NSButton }.filter { $0.accessibilityLabel() == label }
        log("premo [\(label)]: \(buttons.count) trovati")
        buttons.first?.performClick(nil)
    }

    private static func log(_ text: String) {
        print("autopilota:", text)
        fflush(stdout)
    }

    // MARK: - Fotografare

    /// Le finestre visibili dell'app, disegnate dove stanno sullo schermo (dietro prima, davanti dopo), ritagliate attorno a quello che c'è.
    private static func shot(_ name: String, since start: Date) {
        let order = NSApp.orderedWindows
        let windows = NSApp.windows.filter { $0.isVisible && $0.alphaValue > 0.05 && $0.contentView != nil }
            .sorted { a, b in
                if a.level != b.level { return a.level.rawValue < b.level.rawValue }
                return (order.firstIndex(of: a) ?? 0) > (order.firstIndex(of: b) ?? 0)
            }
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let area = screen
        let scale: CGFloat = 1.5
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(area.width * scale), pixelsHigh: Int(area.height * scale), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = area.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(calibratedRed: 0.86, green: 0.89, blue: 0.84, alpha: 1).setFill()
        NSRect(origin: .zero, size: area.size).fill()
        for w in windows {
            guard let view = w.contentView, view.bounds.width > 0, view.bounds.height > 0,
                  let cached = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: cached)
            let content = w.contentRect(forFrameRect: w.frame)
            let rect = NSRect(x: content.minX - area.minX, y: content.minY - area.minY, width: content.width, height: content.height)
            cached.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        NSGraphicsContext.restoreGraphicsState()
        shotNumber += 1
        let file = String(format: "%@/%02d-%@.png", folder, shotNumber, name)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: file))
        let names = windows.map { String(describing: type(of: $0)) + (($0.contentView).map { ":" + String(describing: type(of: $0)) } ?? "") }
        log(String(format: "%5.1fs %@ — %@", Date().timeIntervalSince(start), name, names.joined(separator: ", ")))
    }
}
