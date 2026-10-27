import AppKit

/// L'album delle figurine: un libro antico, in una finestra a parte. Si vede prima la copertina in pelle; un clic lo apre su due pagine con
/// sei figurine ciascuna (le trovate incollate, un po' storte; le altre caselle tratteggiate con il numero e la sagoma). Si sfoglia con le
/// frecce, i pulsanti o la tastiera. Una sezione del catalogo (12 oggetti) occupa una doppia pagina.
/// Il libro è disegnato (assets/album/copertina.png e doppia_pagina.png); sopra ci vanno i titoli, le figurine e i numeri. Se le immagini
/// non ci sono, copertina e pagine si disegnano a mano.
/// Il libro serve solo a collezionare e a guardare: gli oggetti si mettono nel prato dal giardino (la cassetta in basso).
final class AlbumView: NSView {
    static let size = NSSize(width: 980, height: 730)

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private let garden: Garden
    private let profile: Profile

    private let spreadList = GardenAlbum.spreads()
    fileprivate enum Mode { case cover, opening, open }
    private var mode: Mode = .cover
    private var spread = 0
    /// Le figurine nuove, finché il libro resta aperto.
    private var newOnes: Set<String> = []
    private var message: String?
    private var messageTimer: Timer?
    private var backButton: NSView?

    /// Le animazioni (copertina che si apre, pagina che gira) girano su uno strato a parte, che c'è solo mentre durano.
    private var stage: BookStage?
    private var isAnimating: Bool { stage != nil }
    /// Mentre si fotografa il libro per le animazioni: solo il libro, senza tavolo, ombra, comandi e messaggi.
    private var capturing = false
    private var capturesContent = true
    /// Quanto si vedono titoli, figurine e comandi (0 appena il libro si è aperto, poi salgono a 1).
    private var contentAlpha: CGFloat = 1
    private var contentTimer: Timer?
    /// Se si preme una freccia mentre una pagina sta girando, la prossima parte appena finisce (una sola, l'ultima).
    private var queuedSpread: Int?

    var onBack: (() -> Void)?

    private static let lastSpreadKey = "albumSpread"

    init(garden: Garden, profile: Profile) {
        self.garden = garden
        self.profile = profile
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        appearance = NSAppearance(named: .aqua)
        setAccessibilityLabel("L'album delle figurine")
        let back = BackToMenuButton(target: self, action: #selector(backPressed))
        back.setFrameOrigin(NSPoint(x: 16, y: 14))
        addSubview(back)
        backButton = back
        garden.addObserver { [weak self] in
            guard let self, self.window.map({ $0.isVisible || $0.isMiniaturized }) ?? true else { return }
            self.needsDisplay = true
        }
    }

    required init?(coder: NSCoder) { nil }

    @objc private func backPressed() { onBack?() }

    /// Alla riapertura il libro è chiuso; se ci sono figurine nuove si aprirà sulla loro pagina.
    func prepare() {
        cancelAnimation()
        mode = .cover
        newOnes = garden.unseen
        message = nil
        let saved = UserDefaults.standard.integer(forKey: Self.lastSpreadKey)
        spread = min(max(saved, 0), spreadList.count - 1)
        needsDisplay = true
    }

    private func open() {
        guard mode == .cover, !isAnimating else { return }
        // si apre sulla doppia pagina della prima figurina nuova, se c'è
        var target = spread
        if let first = newOnes.first(where: { id in spreadList.contains { s in (s.left.items + (s.right?.items ?? [])).contains { $0.id == id } } }),
           let index = spreadList.firstIndex(where: { s in (s.left.items + (s.right?.items ?? [])).contains { $0.id == first } }) {
            target = index
        }
        // la copertina si fotografa prima di segnare le figurine come viste (dice quante sono nuove)
        let cover = canAnimate ? snapshot(mode: .cover, spread: spread, content: false) : nil
        spread = target
        garden.markSeen()
        window?.makeFirstResponder(self)
        if let cover, let book = snapshot(mode: .open, spread: spread, content: false), playOpening(cover: cover, book: book) { return }
        openImmediately()
    }

    /// Il libro si apre di colpo, senza animazione (se mancano i disegni o si è chiesto meno movimento).
    func openImmediately() {
        mode = .open
        needsDisplay = true
    }

    private func turn(by step: Int) {
        goToSpread((queuedSpread ?? spread) + step)
    }

    private func goTo(_ category: GardenCategory) {
        guard let index = spreadList.firstIndex(where: { $0.left.category == category }) else { return }
        goToSpread(index)
    }

    private func goToSpread(_ index: Int) {
        let target = min(max(index, 0), spreadList.count - 1)
        if isAnimating {
            if mode == .open { queuedSpread = target }
            return
        }
        guard target != spread else { return }
        let from = spread
        let pages = canAnimate ? (snapshot(mode: .open, spread: from, content: true), snapshot(mode: .open, spread: target, content: true)) : (nil, nil)
        spread = target
        UserDefaults.standard.set(spread, forKey: Self.lastSpreadKey)
        message = nil
        needsDisplay = true
        if let old = pages.0, let new = pages.1 { playTurn(from: old, to: new, forward: target > from) }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: if mode == .open { turn(by: -1) }
        case 124: if mode == .open { turn(by: 1) } else { open() }
        case 36, 49: open()
        default: super.keyDown(with: event)
        }
    }

    // MARK: - Geometria

    /// Il colore dei comandi sotto il libro (frecce, sezioni, messaggi) e quello del testo sul pulsante scelto: dipendono dallo sfondo.
    private var deskInk: NSColor { MeadowBackdrop.isDark ? Self.goldInk : Self.leatherDark }
    private var deskInkOn: NSColor { MeadowBackdrop.isDark ? Self.leatherDark : Self.paperLight }
    private static let leather = NSColor(calibratedRed: 0.42, green: 0.25, blue: 0.14, alpha: 1)
    private static let leatherDark = NSColor(calibratedRed: 0.29, green: 0.16, blue: 0.08, alpha: 1)
    private static let goldInk = NSColor(calibratedRed: 0.90, green: 0.73, blue: 0.34, alpha: 1)
    private static let paperLight = NSColor(calibratedRed: 1.0, green: 0.975, blue: 0.89, alpha: 1)
    private static let paperDark = NSColor(calibratedRed: 0.93, green: 0.88, blue: 0.76, alpha: 1)

    /// Il libro aperto disegnato (assets/album/doppia_pagina.png: due pagine con le fasce dei titoli vuote). Se manca si disegna a mano.
    private static let spreadImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "album_doppia_pagina", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    /// Dove sta il libro disegnato (la sua proporzione è quella dell'immagine); senza immagine è il libro fatto a mano.
    private var spreadRect: NSRect {
        guard let image = Self.spreadImage else { return boardRect }
        let width: CGFloat = 920
        return NSRect(x: (Self.size.width - width) / 2, y: 40, width: width, height: width * image.size.height / image.size.width)
    }

    /// L'ombra sul tavolo del libro chiuso e di quello aperto (nella vista capovolta), per disegnarla e per animarla dall'una all'altra.
    private static func closedShadow(for cover: NSRect) -> NSRect {
        NSRect(x: cover.minX + 8, y: cover.minY + 6, width: cover.width - 14, height: cover.height * 0.95 - 8).offsetBy(dx: 5, dy: 9)
    }

    private static func openShadow(for spread: NSRect) -> NSRect {
        NSRect(x: spread.minX + spread.width * 0.03, y: spread.minY + spread.height * 0.05, width: spread.width * 0.94, height: spread.height * 0.89)
            .offsetBy(dx: 4, dy: 9)
    }

    /// Un punto del libro disegnato, dalle frazioni dell'immagine (u verso destra, v verso il basso).
    private func onSpread(_ u: CGFloat, _ v: CGFloat) -> NSPoint {
        NSPoint(x: spreadRect.minX + spreadRect.width * u, y: spreadRect.minY + spreadRect.height * v)
    }

    /// Dove cadono, nell'immagine, il centro delle due pagine, il centro delle fasce dei titoli e quello dei numeri di pagina.
    private static let pageCenterU: (left: CGFloat, right: CGFloat) = (0.291, 0.707)
    private static let bandCenterV: CGFloat = 0.18
    private static let pageNumberV: CGFloat = 0.838
    private static let slotsTopV: CGFloat = 0.285

    private var boardRect: NSRect { NSRect(x: 30, y: 46, width: Self.size.width - 60, height: 580) }
    private var leftPage: NSRect { NSRect(x: boardRect.minX + 10, y: boardRect.minY + 10, width: (boardRect.width - 20) / 2, height: boardRect.height - 20) }
    private var rightPage: NSRect { NSRect(x: leftPage.maxX, y: leftPage.minY, width: leftPage.width, height: leftPage.height) }
    private var coverRect: NSRect { NSRect(x: (Self.size.width - 450) / 2, y: 40, width: 450, height: 540) }

    private struct Controls {
        var previous: NSRect
        var next: NSRect
        var tabs: [(category: GardenCategory, rect: NSRect)]
    }

    private static let tabFont = NSFont.systemFont(ofSize: 12.5, weight: .semibold)

    private func controls() -> Controls {
        let y = spreadRect.maxY + (Self.spreadImage == nil ? 16 : 7)
        var tabs: [(category: GardenCategory, rect: NSRect)] = []
        let widths = GardenCategory.allCases.map { ceil(($0.title as NSString).size(withAttributes: [.font: Self.tabFont]).width) + 26 }
        var x = (Self.size.width - (widths.reduce(0, +) + CGFloat(widths.count - 1) * 8)) / 2
        for (category, width) in zip(GardenCategory.allCases, widths) {
            tabs.append((category, NSRect(x: x, y: y, width: width, height: 28)))
            x += width + 8
        }
        return Controls(previous: NSRect(x: spreadRect.minX, y: y - 2, width: 38, height: 32),
                        next: NSRect(x: spreadRect.maxX - 38, y: y - 2, width: 38, height: 32), tabs: tabs)
    }

    /// Le sei caselle di una pagina (3 colonne per 2 righe).
    private func slots(isLeft: Bool) -> [NSRect] {
        let illustrated = Self.spreadImage != nil
        let size = illustrated ? NSSize(width: 98, height: 132) : NSSize(width: 108, height: 142)
        let gapX: CGFloat = illustrated ? 9 : 8, gapY: CGFloat = illustrated ? 36 : 30
        let center = illustrated ? onSpread(isLeft ? Self.pageCenterU.left : Self.pageCenterU.right, 0).x : (isLeft ? leftPage : rightPage).midX
        let top = illustrated ? onSpread(0, Self.slotsTopV).y : leftPage.minY + 96
        let originX = center - (size.width * 3 + gapX * 2) / 2
        return (0..<GardenAlbum.perPage).map { index in
            let row = index / 3, column = index % 3
            return NSRect(x: originX + CGFloat(column) * (size.width + gapX), y: top + CGFloat(row) * (size.height + gapY),
                          width: size.width, height: size.height)
        }
    }

    // MARK: - Disegno

    private func text(_ string: String, in rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .center) {
        let para = NSMutableParagraphStyle()
        para.alignment = alignment
        para.lineBreakMode = .byTruncatingTail
        (string as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
    }

    override func draw(_ dirtyRect: NSRect) {
        if !capturing {
            MeadowBackdrop.draw(in: bounds, scale: window?.backingScaleFactor ?? 2, season: GardenSky.shownSeason(date: Date(), calendar: StudyPeriod.calendar()))
        }
        switch mode {
        case .cover: drawCover()
        case .opening: break
        case .open: drawSpread()
        }
    }

    private func drawLeather(_ rect: NSRect, radius: CGFloat, seed: UInt32) {
        let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        NSGradient(colors: [Self.leather, Self.leatherDark])?.draw(in: rect, angle: -55)
        // la grana della pelle: puntini chiari e scuri, sempre gli stessi
        var stream = GardenDrops.Stream(seed: seed)
        for _ in 0..<900 {
            let p = NSPoint(x: rect.minX + CGFloat(stream.next()) * rect.width, y: rect.minY + CGFloat(stream.next()) * rect.height)
            let size = 0.8 + CGFloat(stream.next()) * 1.6
            (stream.next() < 0.5 ? NSColor.black : NSColor.white).withAlphaComponent(0.05).setFill()
            NSBezierPath(ovalIn: NSRect(x: p.x, y: p.y, width: size, height: size)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.35).setStroke()
        shape.lineWidth = 1.5
        shape.stroke()
    }

    private func drawGoldFrame(_ rect: NSRect) {
        for (inset, width) in [(16.0, 2.4), (23.0, 0.9)] as [(CGFloat, CGFloat)] {
            let frame = NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), xRadius: 8, yRadius: 8)
            Self.goldInk.withAlphaComponent(0.9).setStroke()
            frame.lineWidth = width
            frame.stroke()
        }
        // gli angoli
        for corner in [NSPoint(x: rect.minX + 16, y: rect.minY + 16), NSPoint(x: rect.maxX - 16, y: rect.minY + 16),
                       NSPoint(x: rect.minX + 16, y: rect.maxY - 16), NSPoint(x: rect.maxX - 16, y: rect.maxY - 16)] {
            let dot = NSBezierPath(ovalIn: NSRect(x: corner.x - 5, y: corner.y - 5, width: 10, height: 10))
            Self.leatherDark.setFill()
            dot.fill()
            Self.goldInk.setStroke()
            dot.lineWidth = 1.5
            dot.stroke()
        }
    }

    // MARK: la copertina

    /// La copertina disegnata (assets/album/copertina.png: un libro in pelle con la targa vuota e il segnalibro). Se manca si disegna a mano.
    private static let coverImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "album_copertina", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    /// Dove sta la copertina disegnata nella finestra (la sua proporzione è quella dell'immagine).
    private var coverImageRect: NSRect {
        guard let image = Self.coverImage else { return coverRect }
        let height: CGFloat = 628
        let width = height * image.size.width / image.size.height
        return NSRect(x: (Self.size.width - width) / 2, y: 28, width: width, height: height)
    }

    private func drawCover() {
        guard let image = Self.coverImage else {
            drawHandMadeCover()
            return
        }
        let rect = coverImageRect
        // l'ombra sul tavolo, sotto il libro (il segnalibro sporge, e non fa ombra)
        if !capturing {
            NSColor.black.withAlphaComponent(0.32).setFill()
            NSBezierPath(roundedRect: Self.closedShadow(for: rect), xRadius: 12, yRadius: 12).fill()
        }
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        // il titolo sulla targa (che nell'immagine è vuota), e il resto sulla pelle
        let centerX = rect.minX + rect.width * 0.547
        let ink = NSColor(calibratedRed: 0.30, green: 0.18, blue: 0.09, alpha: 1)
        text("L'album", in: NSRect(x: centerX - 140, y: rect.minY + rect.height * 0.19, width: 280, height: 52), font: Paper.markerFont(42), color: ink)
        let owner = profile.name.map { "di \($0)" } ?? "delle figurine"
        text(owner, in: NSRect(x: centerX - 140, y: rect.minY + rect.height * 0.285, width: 280, height: 28), font: Paper.markerFont(21), color: ink.withAlphaComponent(0.8))
        let count = "\(garden.foundCount) su \(GardenCatalog.items.count) figurine"
        text(count, in: NSRect(x: centerX - 140, y: rect.minY + rect.height * 0.45, width: 280, height: 22),
             font: NSFont.systemFont(ofSize: 15, weight: .semibold), color: Self.goldInk)
        if !garden.unseen.isEmpty {
            let news = garden.unseen.count == 1 ? "C'è una figurina nuova!" : "Ci sono \(garden.unseen.count) figurine nuove!"
            text(news, in: NSRect(x: centerX - 140, y: rect.minY + rect.height * 0.515, width: 280, height: 22),
                 font: NSFont.systemFont(ofSize: 14, weight: .semibold), color: NSColor(calibratedRed: 1, green: 0.93, blue: 0.75, alpha: 1))
        }
        text("Tocca per aprirlo", in: NSRect(x: centerX - 150, y: rect.minY + rect.height * 0.74, width: 300, height: 18),
             font: NSFont.systemFont(ofSize: 12.5, weight: .medium), color: Self.goldInk.withAlphaComponent(0.85))
    }

    private func drawHandMadeCover() {
        let rect = coverRect
        // l'ombra sul tavolo
        NSColor.black.withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: rect.offsetBy(dx: 5, dy: 9), xRadius: 14, yRadius: 14).fill()
        drawLeather(rect, radius: 14, seed: 77)
        // il dorso
        NSColor.black.withAlphaComponent(0.28).setFill()
        NSRect(x: rect.minX, y: rect.minY, width: 22, height: rect.height).fill(using: .sourceOver)
        NSColor.white.withAlphaComponent(0.06).setFill()
        NSRect(x: rect.minX + 22, y: rect.minY, width: 3, height: rect.height).fill()
        drawGoldFrame(rect)
        let titleFont = Paper.markerFont(46)
        let gold = Self.goldInk
        text("L'album", in: NSRect(x: rect.minX + 30, y: rect.minY + 150, width: rect.width - 50, height: 60), font: titleFont, color: gold)
        let owner = profile.name.map { "di \($0)" } ?? "delle figurine"
        text(owner, in: NSRect(x: rect.minX + 30, y: rect.minY + 214, width: rect.width - 50, height: 30), font: Paper.markerFont(22), color: gold.withAlphaComponent(0.85))
        // un fregio
        let mid = rect.minX + 22 + (rect.width - 22) / 2
        gold.withAlphaComponent(0.7).setStroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: mid - 60, y: rect.minY + 262)); line.line(to: NSPoint(x: mid - 10, y: rect.minY + 262))
        line.move(to: NSPoint(x: mid + 10, y: rect.minY + 262)); line.line(to: NSPoint(x: mid + 60, y: rect.minY + 262))
        line.lineWidth = 1.2
        line.stroke()
        let star = NSBezierPath()
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4 - .pi / 2
            let r: CGFloat = i % 2 == 0 ? 7 : 2.4
            let p = NSPoint(x: mid + cos(angle) * r, y: rect.minY + 262 + sin(angle) * r)
            if i == 0 { star.move(to: p) } else { star.line(to: p) }
        }
        star.close()
        gold.setFill()
        star.fill()
        let count = "\(garden.foundCount) su \(GardenCatalog.items.count) figurine"
        text(count, in: NSRect(x: rect.minX + 30, y: rect.minY + 290, width: rect.width - 50, height: 20),
             font: NSFont.systemFont(ofSize: 14, weight: .medium), color: gold.withAlphaComponent(0.9))
        let hint = garden.unseen.isEmpty ? "Tocca per aprirlo" : "Ci sono figurine nuove: tocca per aprirlo"
        text(hint, in: NSRect(x: rect.minX + 30, y: rect.maxY - 70, width: rect.width - 50, height: 18),
             font: NSFont.systemFont(ofSize: 12), color: gold.withAlphaComponent(0.7))
        // il segnalibro che sporge
        let ribbon = NSBezierPath()
        let rx = rect.maxX - 70
        ribbon.move(to: NSPoint(x: rx, y: rect.maxY - 2))
        ribbon.line(to: NSPoint(x: rx, y: rect.maxY + 22))
        ribbon.line(to: NSPoint(x: rx + 9, y: rect.maxY + 14))
        ribbon.line(to: NSPoint(x: rx + 18, y: rect.maxY + 22))
        ribbon.line(to: NSPoint(x: rx + 18, y: rect.maxY - 2))
        ribbon.close()
        NSColor(calibratedRed: 0.70, green: 0.15, blue: 0.14, alpha: 1).setFill()
        ribbon.fill()
    }

    // MARK: le doppie pagine

    private func drawSpread() {
        let current = spreadList[spread]
        if let image = Self.spreadImage {
            let rect = spreadRect
            // l'ombra sul tavolo, sotto il libro
            if !capturing {
                NSColor.black.withAlphaComponent(0.30).setFill()
                NSBezierPath(roundedRect: Self.openShadow(for: rect), xRadius: 14, yRadius: 14).fill()
            }
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        } else {
            drawHandMadeSpread(current)
        }
        guard capturesContent else { return }
        // titoli, figurine e comandi (appena aperto il libro compaiono piano piano)
        let context = NSGraphicsContext.current?.cgContext
        let fading = contentAlpha < 1
        if fading {
            context?.saveGState()
            context?.setAlpha(contentAlpha)
            context?.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        if Self.spreadImage != nil {
            drawPage(spreadRect, page: current.left, isLeft: true)
            if let right = current.right { drawPage(spreadRect, page: right, isLeft: false) }
        }
        drawSeal(for: current)
        if !capturing { drawControls() }
        if fading {
            context?.endTransparencyLayer()
            context?.restoreGState()
        }
        // il messaggio in fondo
        if let message, !capturing {
            text(message, in: NSRect(x: 60, y: Self.size.height - 24, width: Self.size.width - 120, height: 18),
                 font: NSFont.systemFont(ofSize: 13, weight: .medium), color: deskInk)
        }
    }

    /// Il libro fatto a mano (pelle e carta disegnate nel codice), per quando manca l'immagine.
    private func drawHandMadeSpread(_ current: (left: GardenAlbum.Page, right: GardenAlbum.Page?)) {
        let board = boardRect
        NSColor.black.withAlphaComponent(0.38).setFill()
        NSBezierPath(roundedRect: board.offsetBy(dx: 5, dy: 9), xRadius: 14, yRadius: 14).fill()
        drawLeather(board, radius: 14, seed: 41)

        let (leftShape, rightShape) = (leftPage, rightPage)
        // lo spessore delle pagine, ai lati
        for i in 0..<4 {
            Self.paperDark.withAlphaComponent(0.9 - CGFloat(i) * 0.12).setFill()
            NSRect(x: leftShape.minX - CGFloat(i) * 1.4, y: leftShape.minY + CGFloat(i), width: 2, height: leftShape.height - CGFloat(i) * 2).fill()
            NSRect(x: rightShape.maxX - 2 + CGFloat(i) * 1.4, y: rightShape.minY + CGFloat(i), width: 2, height: rightShape.height - CGFloat(i) * 2).fill()
        }
        drawPage(leftShape, page: current.left, isLeft: true)
        if let right = current.right {
            drawPage(rightShape, page: right, isLeft: false)
        } else {
            drawBlankPage(rightShape)
        }
        // la piega al centro
        let spine = NSGradient(colors: [NSColor.black.withAlphaComponent(0), NSColor.black.withAlphaComponent(0.30), NSColor.black.withAlphaComponent(0)])
        spine?.draw(in: NSRect(x: leftShape.maxX - 26, y: leftShape.minY, width: 52, height: leftShape.height), angle: 0)
        NSColor.black.withAlphaComponent(0.35).setFill()
        NSRect(x: leftShape.maxX - 0.5, y: leftShape.minY, width: 1, height: leftShape.height).fill()
        drawBookmark()
    }

    private func drawPaper(_ page: NSRect, isLeft: Bool) {
        let shape = NSBezierPath(roundedRect: page, xRadius: 4, yRadius: 4)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        NSGradient(colors: isLeft ? [Self.paperLight, Self.paperDark] : [Self.paperDark, Self.paperLight])?.draw(in: page, angle: 0)
        // la grana della carta
        var stream = GardenDrops.Stream(seed: isLeft ? 5 : 6)
        for _ in 0..<500 {
            let p = NSPoint(x: page.minX + CGFloat(stream.next()) * page.width, y: page.minY + CGFloat(stream.next()) * page.height)
            NSColor(calibratedRed: 0.55, green: 0.42, blue: 0.25, alpha: 0.045).setFill()
            NSBezierPath(ovalIn: NSRect(x: p.x, y: p.y, width: 1.4, height: 1.4)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawBlankPage(_ page: NSRect) {
        drawPaper(page, isLeft: false)
    }

    /// Una pagina: il titolo della sezione e i numeri, le sei figurine, il numero di pagina. `rect` è la pagina (nel libro disegnato, tutto il libro).
    private func drawPage(_ rect: NSRect, page: GardenAlbum.Page, isLeft: Bool) {
        let illustrated = Self.spreadImage != nil
        if !illustrated { drawPaper(rect, isLeft: isLeft) }
        let first = page.items.first.flatMap { GardenCatalog.number(of: $0.id) } ?? 0
        let last = page.items.last.flatMap { GardenCatalog.number(of: $0.id) } ?? 0
        let range = "n. \(first) – \(last)"
        if illustrated {
            // nella fascia del titolo, che nell'immagine è vuota
            let centerX = onSpread(isLeft ? Self.pageCenterU.left : Self.pageCenterU.right, 0).x
            let mid = onSpread(0, Self.bandCenterV).y
            text(page.category.title, in: NSRect(x: centerX - 160, y: mid - 28, width: 320, height: 38),
                 font: Paper.markerFont(isLeft ? 31 : 24), color: isLeft ? Paper.ink : Paper.inkLight)
            text(range, in: NSRect(x: centerX - 100, y: mid + 11, width: 200, height: 16),
                 font: NSFont.systemFont(ofSize: 11.5, weight: .medium), color: Paper.inkLight)
        } else {
            if isLeft {
                text(page.category.title, in: NSRect(x: rect.minX + 30, y: rect.minY + 24, width: rect.width - 60, height: 40),
                     font: Paper.markerFont(32), color: Paper.ink)
            } else {
                text(page.category.title, in: NSRect(x: rect.minX + 30, y: rect.minY + 32, width: rect.width - 60, height: 28),
                     font: Paper.markerFont(20), color: Paper.inkLight)
            }
            text(range, in: NSRect(x: rect.minX + 30, y: rect.minY + 66, width: rect.width - 60, height: 16),
                 font: NSFont.systemFont(ofSize: 11.5, weight: .medium), color: Paper.inkLight)
            let line = NSBezierPath()
            line.move(to: NSPoint(x: rect.minX + 70, y: rect.minY + 88)); line.line(to: NSPoint(x: rect.maxX - 70, y: rect.minY + 88))
            Paper.paperEdge.withAlphaComponent(0.55).setStroke()
            line.lineWidth = 0.8
            line.stroke()
        }

        for (slot, item) in zip(slots(isLeft: isLeft), page.items) {
            let number = GardenCatalog.number(of: item.id) ?? 0
            let look = Sticker.Look(item: item, number: number, found: garden.copies(of: item.id) > 0, copies: garden.copies(of: item.id),
                                    isNew: newOnes.contains(item.id), placing: placing(of: item))
            if look.found {
                // incollata un po' storta, sempre nello stesso modo
                let tilt = (CGFloat(GardenDrops.hash(item.id) % 9) - 4) * 0.45
                NSGraphicsContext.saveGraphicsState()
                let t = NSAffineTransform()
                t.translateX(by: slot.midX, yBy: slot.midY)
                t.rotate(byDegrees: tilt)
                t.translateX(by: -slot.midX, yBy: -slot.midY)
                t.concat()
                NSColor.black.withAlphaComponent(0.18).setFill()
                NSBezierPath(roundedRect: slot.offsetBy(dx: 1.5, dy: 2.5), xRadius: 11, yRadius: 11).fill()
                Sticker.draw(look, in: slot)
                NSGraphicsContext.restoreGraphicsState()
            } else {
                Sticker.draw(look, in: slot)
            }
        }
        // il numero di pagina (nell'immagine, dentro la macchia in basso)
        let pageNumber = (spread * 2) + (isLeft ? 1 : 2)
        let numberY = illustrated ? onSpread(0, Self.pageNumberV).y - 9 : rect.maxY - 30
        let numberRect = illustrated ? NSRect(x: onSpread(isLeft ? Self.pageCenterU.left : Self.pageCenterU.right, 0).x - 30, y: numberY, width: 60, height: 18)
            : NSRect(x: rect.minX, y: numberY, width: rect.width, height: 16)
        text("\(pageNumber)", in: numberRect, font: Paper.markerFont(illustrated ? 15 : 14), color: Paper.inkLight.withAlphaComponent(0.85))
    }

    /// Il sigillo d'oro quando la doppia pagina è completa.
    private func drawSeal(for spread: (left: GardenAlbum.Page, right: GardenAlbum.Page?)) {
        let items = spread.left.items + (spread.right?.items ?? [])
        guard !items.isEmpty, items.allSatisfy({ garden.copies(of: $0.id) > 0 }) else { return }
        let center = Self.spreadImage == nil ? NSPoint(x: leftPage.maxX, y: leftPage.minY + 56) : onSpread(0.498, 0.185)
        NSColor.black.withAlphaComponent(0.25).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 30, y: center.y - 28, width: 60, height: 60)).fill()
        let seal = NSBezierPath(ovalIn: NSRect(x: center.x - 29, y: center.y - 30, width: 58, height: 58))
        NSGradient(colors: [NSColor(calibratedRed: 0.97, green: 0.83, blue: 0.42, alpha: 1), NSColor(calibratedRed: 0.78, green: 0.58, blue: 0.16, alpha: 1)])?.draw(in: seal, angle: -60)
        Self.leatherDark.withAlphaComponent(0.6).setStroke()
        seal.lineWidth = 1.2
        seal.stroke()
        let star = NSBezierPath()
        for i in 0..<10 {
            let angle = CGFloat(i) * .pi / 5 - .pi / 2
            let r: CGFloat = i % 2 == 0 ? 15 : 7
            let p = NSPoint(x: center.x + cos(angle) * r, y: center.y - 1 + sin(angle) * r)
            if i == 0 { star.move(to: p) } else { star.line(to: p) }
        }
        star.close()
        Self.leatherDark.withAlphaComponent(0.75).setFill()
        star.fill()
        text("completa", in: NSRect(x: center.x - 40, y: center.y + 32, width: 80, height: 14), font: NSFont.systemFont(ofSize: 10.5, weight: .bold),
             color: Self.spreadImage == nil ? Self.goldInk : Paper.ink)
    }

    private func drawBookmark() {
        let x = rightPage.maxX - 60
        let ribbon = NSBezierPath()
        ribbon.move(to: NSPoint(x: x, y: boardRect.minY + 8))
        ribbon.line(to: NSPoint(x: x, y: boardRect.minY + 78))
        ribbon.line(to: NSPoint(x: x + 9, y: boardRect.minY + 68))
        ribbon.line(to: NSPoint(x: x + 18, y: boardRect.minY + 78))
        ribbon.line(to: NSPoint(x: x + 18, y: boardRect.minY + 8))
        ribbon.close()
        NSColor(calibratedRed: 0.70, green: 0.15, blue: 0.14, alpha: 1).setFill()
        ribbon.fill()
        NSColor.black.withAlphaComponent(0.25).setStroke()
        ribbon.lineWidth = 0.8
        ribbon.stroke()
    }

    private func drawControls() {
        let c = controls()
        for (pointsLeft, rect, enabled) in [(true, c.previous, spread > 0), (false, c.next, spread < spreadList.count - 1)] {
            let shape = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
            deskInk.withAlphaComponent(enabled ? 0.18 : 0.06).setFill()
            shape.fill()
            // la freccia
            let arrow = NSBezierPath()
            let cx = rect.midX, cy = rect.midY, d: CGFloat = pointsLeft ? -1 : 1
            arrow.move(to: NSPoint(x: cx - d * 4, y: cy - 8))
            arrow.line(to: NSPoint(x: cx + d * 4, y: cy))
            arrow.line(to: NSPoint(x: cx - d * 4, y: cy + 8))
            deskInk.withAlphaComponent(enabled ? 1 : 0.35).setStroke()
            arrow.lineWidth = 2.4
            arrow.lineCapStyle = .round
            arrow.lineJoinStyle = .round
            arrow.stroke()
        }
        let currentCategory = spreadList[spread].left.category
        for tab in c.tabs {
            let selected = tab.category == currentCategory
            let path = NSBezierPath(roundedRect: tab.rect, xRadius: 14, yRadius: 14)
            if selected {
                deskInk.setFill()
                path.fill()
            } else {
                deskInk.withAlphaComponent(0.55).setStroke()
                path.lineWidth = 1.2
                path.stroke()
            }
            text(tab.category.title, in: NSRect(x: tab.rect.minX, y: tab.rect.minY + 6, width: tab.rect.width, height: 16),
                 font: Self.tabFont, color: selected ? deskInkOn : deskInk.withAlphaComponent(0.85))
        }
        let total = "\(garden.foundCount) su \(GardenCatalog.items.count)"
        text(total, in: NSRect(x: c.previous.maxX + 10, y: c.previous.minY + 8, width: 140, height: 16), font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
             color: deskInk.withAlphaComponent(0.8), alignment: .left)
    }

    // MARK: - Il mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        switch mode {
        case .cover:
            if (Self.coverImage == nil ? coverRect : coverImageRect).contains(p) { open() }
        case .opening:
            break
        case .open:
            let c = controls()
            if c.previous.contains(p) { turn(by: -1); return }
            if c.next.contains(p) { turn(by: 1); return }
            if let tab = c.tabs.first(where: { $0.rect.contains(p) }) { goTo(tab.category); return }
            let current = spreadList[spread]
            for (isLeft, items) in [(true, current.left.items), (false, current.right?.items ?? [])] {
                for (slot, item) in zip(slots(isLeft: isLeft), items) where slot.contains(p) {
                    describe(item)
                    return
                }
            }
        }
    }

    /// Il nome dell'animale a cui appartiene un'isola.
    private func ownerName(_ island: String) -> String { Pet.all.first { $0.id == island }?.name ?? island }

    /// Il segno sulla figurina: universale, o solo sull'isola del suo animale.
    private func placing(of item: GardenItem) -> Sticker.Placing {
        item.island.map { .onlyOn(island: $0, name: ownerName($0)) } ?? .everywhere
    }

    private func describe(_ item: GardenItem) {
        let number = GardenCatalog.number(of: item.id) ?? 0
        let rule = item.islandRule(ownerName: item.island.map(ownerName) ?? "")
        if garden.copies(of: item.id) > 0 {
            let copies = garden.copies(of: item.id)
            let placed = garden.count(of: item.id)
            flash("\(item.name) · n. \(number) · \(item.rarity.title) · \(rule) · \(copies == 1 ? "1 copia" : "\(copies) copie")\(placed > 0 ? ", \(placed) nel prato" : "")")
        } else if let owner = item.island, !profile.isCompanionUnlocked(owner) {
            // le cose di un animale non sbloccato non escono ai regali: si aspetta il compagno
            flash("n. \(number) · \(item.rarity.title) · \(rule): ancora da trovare. Esce a fine focus quando sblocchi \(ownerName(owner)).")
        } else {
            flash("n. \(number) · \(item.rarity.title) · \(rule): ancora da trovare. Esce a fine focus.")
        }
    }

    private func flash(_ string: String) {
        message = string
        messageTimer?.invalidate()
        messageTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            self?.message = nil
            self?.needsDisplay = true
        }
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        guard mode == .open, abs(event.scrollingDeltaX) > 8 || abs(event.scrollingDeltaY) > 8 else { return }
        // un solo giro per gesto
        if event.phase == .began || event.phase == [] { turn(by: (event.scrollingDeltaX + event.scrollingDeltaY) < 0 ? 1 : -1) }
    }
}

/// Lo sfondo dietro il libro e dietro l'isola del giardino: il prato (assets/giardino/prato.png) che riempie la finestra centrato sul casale,
/// con una luce calda sopra e i bordi appena scuriti perché il resto resti il protagonista. Se il disegno manca, un tavolo marrone.
enum MeadowBackdrop {
    private static let lock = NSLock()
    private static var cache: [String: CGImage] = [:]
    private static var rendered: [String: CGImage] = [:]
    private static let ciContext = CIContext()

    /// Lo sfondo: il paesaggio con il lago (assets/giardino/sfondo.png, da `tools/prepara_sfondo.py`); in mancanza, il vecchio prato dipinto.
    private static let landscapeURL = Bundle.main.url(forResource: "giardino_sfondo", withExtension: "png")
    private static let meadowURL: URL? = landscapeURL ?? Bundle.main.url(forResource: "giardino_prato", withExtension: "png")

    /// L'inverno ha il suo paesaggio (assets/giardino/sfondo_inverno.png): il lago ghiacciato, il casale con la neve sul tetto. Se manca, resta quello solito.
    private static let frozenURL = Bundle.main.url(forResource: "giardino_sfondo_inverno", withExtension: "png")

    private static func isFrozen(_ season: Season) -> Bool { season == .winter && frozenURL != nil }
    private static func pictureURL(_ season: Season) -> URL? { isFrozen(season) ? frozenURL : meadowURL }

    /// Dove sta il casale nello sfondo nuovo e quanto è piccolo: il fumo e la luce delle finestre si adattano. Con il vecchio prato dipinto il casale
    /// è più grande, e questi numeri sono quelli di allora.
    private static let hasLandscape = landscapeURL != nil

    /// Sul tavolo marrone i comandi sotto il libro sono dorati, sul prato scuri.
    static let isDark = meadowURL == nil

    static var base: NSColor {
        isDark ? NSColor(calibratedRed: 0.24, green: 0.17, blue: 0.12, alpha: 1) : NSColor(calibratedRed: 0.62, green: 0.75, blue: 0.55, alpha: 1)
    }

    /// Il prato a misura della finestra (al doppio dei punti, per gli schermi retina), preso al 40 % da sinistra, sfocato di `blur` punti.
    private static func meadow(size: NSSize, blur: CGFloat, season: Season) -> CGImage? {
        let key = "\(Int(size.width))x\(Int(size.height))-\(blur)-\(isFrozen(season) ? "inverno" : "prato")"
        if let known = cache[key] { return known }
        guard let url = pictureURL(season), let picture = CIImage(contentsOf: url) else { return nil }
        let target = CGSize(width: size.width * 2, height: size.height * 2)
        let scale = max(target.width / picture.extent.width, target.height / picture.extent.height)
        var scaled = picture.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let crop = CGRect(x: (scaled.extent.width - target.width) * 0.40, y: 0, width: target.width, height: target.height)
        if blur > 0 { scaled = scaled.clampedToExtent().applyingGaussianBlur(sigma: Double(blur * 2)) }
        let image = scaled.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        guard let cg = ciContext.createCGImage(image, from: CGRect(origin: .zero, size: target)) else { return nil }
        cache[key] = cg
        return cg
    }

    // MARK: - Il paesaggio «del mondo» (il giardino: ci si sposta e si ingrandisce, il paesaggio con l'isola e la collina)

    /// Di quanto il paesaggio del mondo è più grande della finestra, da ogni lato (in punti): serve per spostarsi (l'isola più vicina al bordo) e per rimpicciolire
    /// senza che si veda finire il disegno.
    static let worldMargin = (top: CGFloat(340), left: CGFloat(480), bottom: CGFloat(520), right: CGFloat(480))
    private static var worldCache: [String: CGImage] = [:]

    /// Il paesaggio con la stessa inquadratura di `meadow(size:…)` al centro, e tutt'attorno altre copie del disegno capovolte (riflesse): continua senza stacchi.
    /// Un pixel per punto (è sfocato, e si disegna ingrandito).
    static func world(size: NSSize, blur: CGFloat, season: Season) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        let key = "\(Int(size.width))x\(Int(size.height))-\(blur)-\(isFrozen(season) ? "inverno" : "prato")"
        if let known = worldCache[key] { return known }
        guard let url = pictureURL(season), let picture = CIImage(contentsOf: url) else { return nil }
        let scale = max(size.width / picture.extent.width, size.height / picture.extent.height)
        let scaled = picture.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let w = scaled.extent.width, h = scaled.extent.height
        var padded = scaled
        for dx in -1...1 {
            for dy in -1...1 where dx != 0 || dy != 0 {
                let mirror = CGAffineTransform(a: dx == 0 ? 1 : -1, b: 0, c: 0, d: dy == 0 ? 1 : -1,
                                               tx: dx == 1 ? 2 * w : 0, ty: dy == 1 ? 2 * h : 0)
                padded = scaled.transformed(by: mirror).composited(over: padded)
            }
        }
        let m = worldMargin
        let baseX = (w - size.width) * 0.40
        let crop = CGRect(x: baseX - m.left, y: -m.bottom, width: size.width + m.left + m.right, height: size.height + m.top + m.bottom)
        var image = padded
        if blur > 0 { image = padded.clampedToExtent().applyingGaussianBlur(sigma: Double(blur)) }
        image = image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        guard let cg = ciContext.createCGImage(image, from: CGRect(origin: .zero, size: crop.size)) else { return nil }
        worldCache[key] = cg
        return cg
    }

    /// Disegna il paesaggio come lo vede la telecamera del giardino: spostato di `pan` e ingrandito di `zoom` attorno al centro della scena `scene` (come l'isola e la
    /// collina: quando ci si muove, si muove tutto il mondo insieme), poi il velo, su tutto `fill` (che può essere più grande della scena: la scena preparata in
    /// anticipo). Gli angoli scuri (`vignette`) stanno invece sullo schermo, non nel mondo: `drawVignette` li disegna a parte (nella vista capovolta).
    static func drawWorld(scene bounds: NSRect, fill: NSRect? = nil, zoom: CGFloat, pan: NSPoint, blur: CGFloat, veil: NSColor?, season: Season) {
        let area = fill ?? bounds
        guard let image = world(size: bounds.size, blur: blur, season: season) else {
            paint(in: area, blur: blur, veil: veil, season: season)
            return
        }
        base.setFill()
        area.fill()
        let m = worldMargin
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let origin = NSPoint(x: center.x + (bounds.minX - m.left - center.x) * zoom + pan.x, y: center.y + (bounds.minY - m.top - center.y) * zoom + pan.y)
        let rect = NSRect(x: origin.x, y: origin.y, width: (bounds.width + m.left + m.right) * zoom, height: (bounds.height + m.top + m.bottom) * zoom)
        NSImage(cgImage: image, size: rect.size).draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                                                       hints: [.interpolation: NSImageInterpolation.low])
        (veil ?? defaultVeil(season)).setFill()
        area.fill()
    }

    /// I bordi scuriti del paesaggio (verdi sul prato, azzurri sul ghiaccio).
    static func drawVignette(in bounds: NSRect, season: Season) {
        let edge = isFrozen(season) ? (0.14, 0.19, 0.28, 0.26) : (0.15, 0.20, 0.10, 0.30)
        NSGradient(colors: [rgb(edge.0, edge.1, edge.2, 0), rgb(edge.0, edge.1, edge.2, edge.3)])?.draw(in: bounds, relativeCenterPosition: NSPoint(x: 0, y: 0))
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(calibratedRed: r, green: g, blue: b, alpha: a) }

    private static let sourcePixels: CGSize? = meadowURL.flatMap { CIImage(contentsOf: $0) }.map { $0.extent.size }
    private static let frozenPixels: CGSize? = frozenURL.flatMap { CIImage(contentsOf: $0) }.map { $0.extent.size }

    /// Dove cade, nella scena (origine in alto), un punto del disegno del prato (`u` e `v` da 0 a 1 dall'angolo in alto a sinistra), con lo
    /// stesso ritaglio con cui si disegna lo sfondo: serve a mettere il fumo sul camino e la luce alle finestre del casale.
    static func scenePoint(u: Double, v: Double, in size: NSSize, season: Season) -> NSPoint? {
        guard let source = isFrozen(season) ? frozenPixels : sourcePixels else { return nil }
        let target = CGSize(width: size.width * 2, height: size.height * 2)
        let scale = max(target.width / source.width, target.height / source.height)
        let scaled = CGSize(width: source.width * scale, height: source.height * scale)
        let cropX = (scaled.width - target.width) * 0.40
        return NSPoint(x: (CGFloat(u) * scaled.width - cropX) / 2, y: (target.height - CGFloat(1 - v) * scaled.height) / 2)
    }

    /// Dove stanno, nel disegno del prato, la bocca del camino e le finestre del casale (frazioni dell'immagine; i numeri li stampa `tools/prepara_sfondo.py`).
    static func chimney(_ season: Season) -> (u: Double, v: Double) {
        if isFrozen(season) { return (0.1198, 0.3110) }
        return hasLandscape ? (0.1336, 0.3111) : (0.305, 0.229)
    }

    static func windows(_ season: Season) -> [(u: Double, v: Double)] {
        if isFrozen(season) { return [(0.0813, 0.3990), (0.0875, 0.3644), (0.0938, 0.3993), (0.1072, 0.4040), (0.1228, 0.4010), (0.1432, 0.3631)] }
        return hasLandscape ? [(0.0921, 0.3576), (0.1114, 0.3904), (0.1263, 0.3916), (0.1456, 0.3564)] : [(0.376, 0.346), (0.310, 0.440)]
    }

    /// Quanto è grande il casale rispetto a quello vecchio (fumo e finestre): quello d'inverno ha la stessa larghezza di quello d'estate.
    static func houseScale(_ season: Season) -> CGFloat { hasLandscape || isFrozen(season) ? 0.5 : 1 }

    /// Il velo che si stende sullo sfondo quando non se ne dà uno: caldo di norma, freddo sul lago ghiacciato.
    private static func defaultVeil(_ season: Season) -> NSColor { isFrozen(season) ? rgb(0.88, 0.93, 1, 0.20) : rgb(1, 0.96, 0.86, 0.16) }

    /// Lo sfondo finito (immagine, velo e bordi scuriti) alla grandezza e alla scala (pixel per punto) volute, già pronto: ridisegnarlo ogni volta
    /// costava più di tutto il resto del giardino. Si può preparare anche in un altro thread (prima che serva), e due richieste uguali non si fanno due volte.
    static func rendered(size: NSSize, scale: CGFloat, blur: CGFloat, veil: NSColor?, season: Season, colorSpace: CGColorSpace? = nil) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        let space = colorSpace ?? GardenDisplay.colorSpace()
        let veilColor = (veil ?? defaultVeil(season)).usingColorSpace(.deviceRGB)
        let veilKey = veilColor.map { "\($0.redComponent),\($0.greenComponent),\($0.blueComponent),\($0.alphaComponent)" } ?? "-"
        let key = "\(Int(size.width))x\(Int(size.height))@\(scale)-\(blur)-\(veilKey)-\(isFrozen(season) ? "inverno" : "prato")-\(GardenDisplay.name(space))"
        if let known = rendered[key] { return known }
        guard let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: 0, y: -size.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current?.imageInterpolation = .high
        paint(in: NSRect(origin: .zero, size: size), blur: blur, veil: veilColor, season: season)
        NSGraphicsContext.restoreGraphicsState()
        let image = context.makeImage()
        if let image { rendered[key] = image }
        return image
    }

    /// Disegna lo sfondo (nella vista capovolta: l'origine è in alto).
    /// `veil`: il velo di colore che si stende sopra (di norma uno caldo; il giardino ne usa uno per stagione). `scale`: i pixel per punto dello schermo.
    static func draw(in bounds: NSRect, blur: CGFloat = 0, veil: NSColor? = nil, scale: CGFloat = 2, season: Season) {
        if let image = rendered(size: bounds.size, scale: scale, blur: blur, veil: veil, season: season) {
            GardenBlit.draw(image, in: bounds, copy: true)
        } else {
            paint(in: bounds, blur: blur, veil: veil, season: season)
        }
    }

    private static func paint(in bounds: NSRect, blur: CGFloat, veil: NSColor?, season: Season) {
        base.setFill()
        bounds.fill()
        guard let picture = meadow(size: bounds.size, blur: blur, season: season) else {
            NSGradient(colors: [rgb(0.36, 0.26, 0.18), base])?.draw(in: bounds, relativeCenterPosition: NSPoint(x: 0, y: 0.2))
            return
        }
        NSImage(cgImage: picture, size: bounds.size).draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                                                          hints: [.interpolation: NSImageInterpolation.high])
        (veil ?? defaultVeil(season)).setFill()
        bounds.fill()
        // i bordi scuriti: verdi sul prato, azzurri sul ghiaccio
        let edge = isFrozen(season) ? (0.14, 0.19, 0.28, 0.26) : (0.15, 0.20, 0.10, 0.30)
        NSGradient(colors: [rgb(edge.0, edge.1, edge.2, 0), rgb(edge.0, edge.1, edge.2, edge.3)])?.draw(in: bounds, relativeCenterPosition: NSPoint(x: 0, y: 0))
    }
}

/// Lo strato su cui girano la copertina e le pagine: c'è solo mentre dura un'animazione e lascia passare i clic.
private final class BookStage: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Le animazioni: la copertina che si apre e le pagine che girano

/// Il libro si fotografa (copertina, metà delle pagine) e le foto diventano strati di Core Animation: la copertina e la pagina che gira
/// sono fogli con un davanti e un dietro, appesi al dorso, che ruotano in 3D con un po' di prospettiva.
extension AlbumView {
    fileprivate struct Snapshot {
        let image: CGImage
        let scale: CGFloat

        /// Un pezzo della foto, dal rettangolo (in punti, nelle coordinate della vista).
        func crop(_ rect: NSRect) -> CGImage? {
            image.cropping(to: CGRect(x: (rect.minX * scale).rounded(), y: (rect.minY * scale).rounded(),
                                      width: (rect.width * scale).rounded(), height: (rect.height * scale).rounded()))
        }
    }

    /// Le animazioni ci sono solo se ci sono i disegni del libro (altrimenti si apre e basta) e se non si è chiesto meno movimento.
    fileprivate var canAnimate: Bool {
        Self.coverImage != nil && Self.spreadImage != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    fileprivate func cancelAnimation() {
        queuedSpread = nil
        stage?.removeFromSuperview()
        stage = nil
        contentTimer?.invalidate()
        contentTimer = nil
        contentAlpha = 1
    }

    /// Una foto del libro (solo il libro: niente tavolo, ombra, comandi). `content`: con titoli e figurine, o solo con il disegno.
    fileprivate func snapshot(mode: Mode, spread index: Int, content: Bool) -> Snapshot? {
        let saved = (self.mode, spread, contentAlpha)
        self.mode = mode
        spread = index
        contentAlpha = 1
        capturing = true
        capturesContent = content
        backButton?.isHidden = true
        defer {
            self.mode = saved.0
            spread = saved.1
            contentAlpha = saved.2
            capturing = false
            capturesContent = true
            backButton?.isHidden = false
        }
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        if let data = rep.bitmapData { memset(data, 0, rep.bytesPerRow * rep.pixelsHigh) }
        cacheDisplay(in: bounds, to: rep)
        guard let image = rep.cgImage else { return nil }
        return Snapshot(image: image, scale: CGFloat(image.width) / bounds.width)
    }

    // MARK: strumenti

    /// Dal rettangolo della vista (origine in alto) a quello degli strati (origine in basso).
    private func layerRect(_ rect: NSRect) -> CGRect {
        CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
    }

    private func imageLayer(_ image: CGImage, frame: CGRect, scale: CGFloat) -> CALayer {
        let layer = CALayer()
        layer.frame = frame
        layer.contents = image
        layer.contentsScale = scale
        layer.contentsGravity = .resize
        layer.magnificationFilter = .linear
        layer.minificationFilter = .trilinear
        return layer
    }

    /// Un foglio che gira: il davanti e il dietro (di cui si vede solo il lato rivolto a noi), con un'ombra che li scurisce a metà giro.
    /// `forward`: appeso al dorso sul lato destro e gira verso sinistra; altrimenti il contrario.
    private func makeLeaf(front: CGImage, frontSize: CGSize, back: CGImage, backSize: CGSize, size: CGSize, scale: CGFloat,
                          forward: Bool) -> (leaf: CATransformLayer, frontShade: CALayer, backShade: CALayer) {
        let leaf = CATransformLayer()
        leaf.bounds = CGRect(origin: .zero, size: size)
        leaf.anchorPoint = CGPoint(x: forward ? 0 : 1, y: 0.5)

        func face(_ image: CGImage, _ faceSize: CGSize, turned: Bool) -> (CALayer, CALayer) {
            let layer = imageLayer(image, frame: CGRect(x: forward ? 0 : size.width - faceSize.width, y: (size.height - faceSize.height) / 2,
                                                        width: faceSize.width, height: faceSize.height), scale: scale)
            layer.isDoubleSided = false
            if turned { layer.transform = CATransform3DMakeRotation(.pi, 0, 1, 0) }
            let shade = CALayer()
            shade.frame = layer.bounds
            shade.backgroundColor = NSColor.black.cgColor
            shade.opacity = 0
            layer.addSublayer(shade)
            leaf.addSublayer(layer)
            return (layer, shade)
        }
        let front = face(front, frontSize, turned: false)
        let back = face(back, backSize, turned: true)
        return (leaf, front.1, back.1)
    }

    private func animate(_ layer: CALayer, _ keyPath: String, from: Any, to: Any, duration: CFTimeInterval, delay: CFTimeInterval = 0,
                         timing: CAMediaTimingFunctionName = .easeInEaseOut) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
        animation.fillMode = .both
        animation.timingFunction = CAMediaTimingFunction(name: timing)
        layer.add(animation, forKey: keyPath)
    }

    private func perspective() -> CATransform3D {
        var transform = CATransform3DIdentity
        transform.m34 = -1.0 / 3200
        return transform
    }

    private func makeStage() -> (stage: BookStage, book: CALayer)? {
        guard let backing = { () -> CALayer? in
            let stage = BookStage(frame: bounds)
            if let backButton { addSubview(stage, positioned: .below, relativeTo: backButton) } else { addSubview(stage) }
            self.stage = stage
            return stage.layer
        }() else { return nil }
        let book = CALayer()
        book.frame = CGRect(origin: .zero, size: bounds.size)
        book.sublayerTransform = perspective()
        backing.addSublayer(book)
        return (stage!, book)
    }

    // MARK: la copertina che si apre

    /// Il libro chiuso scivola verso il centro mentre la copertina gira attorno al dorso e mostra la pagina sinistra; poi compaiono
    /// titoli e figurine. Dà false se qualcosa non torna (il libro si apre senza animazione).
    fileprivate func playOpening(cover: Snapshot, book: Snapshot) -> Bool {
        let closed = coverImageRect, opened = spreadRect
        let spineWidth = closed.width * 0.10
        let hingeClosed = closed.minX + spineWidth
        let slide = CGSize(width: opened.midX - hingeClosed, height: opened.midY - closed.midY)
        let halfWidth = opened.width / 2
        let leftHalf = NSRect(x: opened.minX, y: opened.minY, width: halfWidth, height: opened.height)
        let rightHalf = NSRect(x: opened.midX, y: opened.minY, width: halfWidth, height: opened.height)
        let boardWidth = closed.maxX - hingeClosed
        guard let rightImage = book.crop(rightHalf), let leftImage = book.crop(leftHalf),
              let boardImage = cover.crop(NSRect(x: hingeClosed, y: closed.minY, width: boardWidth, height: closed.height)),
              let spineImage = cover.crop(NSRect(x: closed.minX, y: closed.minY, width: spineWidth, height: closed.height)),
              let (stage, container) = makeStage(), let backing = stage.layer else { return false }
        let scale = book.scale
        mode = .opening
        needsDisplay = true
        displayIfNeeded()

        // L'ombra sul tavolo passa da quella del libro chiuso a quella del libro aperto.
        let shadowFrom = layerRect(Self.closedShadow(for: closed)), shadowTo = layerRect(Self.openShadow(for: opened))
        let shadow = CALayer()
        shadow.bounds = CGRect(origin: .zero, size: shadowTo.size)
        shadow.position = CGPoint(x: shadowTo.midX, y: shadowTo.midY)
        shadow.cornerRadius = 13
        shadow.backgroundColor = NSColor.black.withAlphaComponent(0.31).cgColor
        backing.insertSublayer(shadow, below: container)

        // Il libro è messo dove sta da aperto; all'inizio è spostato, così da combaciare con la copertina com'era.
        let rightLayer = imageLayer(rightImage, frame: layerRect(rightHalf), scale: scale)
        let spineLayer = imageLayer(spineImage, frame: layerRect(NSRect(x: opened.midX - spineWidth, y: closed.minY + slide.height, width: spineWidth, height: closed.height)), scale: scale)
        let leafSize = CGSize(width: halfWidth, height: closed.height)
        let parts = makeLeaf(front: boardImage, frontSize: CGSize(width: boardWidth, height: closed.height), back: leftImage,
                             backSize: CGSize(width: halfWidth, height: opened.height), size: leafSize, scale: scale, forward: true)
        parts.leaf.position = CGPoint(x: opened.midX, y: bounds.height - (closed.minY + slide.height + closed.height / 2))
        // All'inizio la pagina destra si vede solo dove la copertina chiusa ha il suo corpo (da sotto non deve sporgere niente), poi si scopre tutta.
        let reveal = CALayer()
        reveal.backgroundColor = NSColor.black.cgColor
        reveal.anchorPoint = .zero
        let cutBottom = max(0, opened.maxY - (closed.minY + slide.height + closed.height * 0.95))
        let early = CGRect(x: 0, y: cutBottom, width: boardWidth, height: opened.height - cutBottom)
        let full = CGRect(origin: .zero, size: layerRect(rightHalf).size)
        reveal.bounds = full
        reveal.position = .zero
        rightLayer.mask = reveal
        container.addSublayer(rightLayer)
        container.addSublayer(spineLayer)
        container.addSublayer(parts.leaf)

        let turnTime: CFTimeInterval = 0.85, turnDelay: CFTimeInterval = 0.08
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in self?.finishOpening() }
        parts.leaf.transform = CATransform3DMakeRotation(-.pi, 0, 1, 0)
        parts.frontShade.opacity = 0.35
        parts.backShade.opacity = 0
        spineLayer.opacity = 0
        animate(container, "transform.translation.x", from: -slide.width, to: 0, duration: 0.95, timing: .easeOut)
        animate(container, "transform.translation.y", from: slide.height, to: 0, duration: 0.95, timing: .easeOut)
        animate(parts.leaf, "transform.rotation.y", from: 0, to: -Double.pi, duration: turnTime, delay: turnDelay)
        animate(parts.frontShade, "opacity", from: 0, to: 0.35, duration: turnTime, delay: turnDelay)
        animate(parts.backShade, "opacity", from: 0.35, to: 0, duration: turnTime, delay: turnDelay)
        animate(spineLayer, "opacity", from: 1, to: 0, duration: 0.25, delay: 0.35, timing: .linear)
        animate(reveal, "bounds", from: NSValue(rect: CGRect(origin: .zero, size: early.size)), to: NSValue(rect: full), duration: 0.3, delay: 0.25, timing: .easeIn)
        animate(reveal, "position", from: NSValue(point: early.origin), to: NSValue(point: .zero), duration: 0.3, delay: 0.25, timing: .easeIn)
        animate(shadow, "bounds", from: NSValue(rect: CGRect(origin: .zero, size: shadowFrom.size)), to: NSValue(rect: shadow.bounds), duration: 0.95)
        animate(shadow, "position", from: NSValue(point: CGPoint(x: shadowFrom.midX, y: shadowFrom.midY)), to: NSValue(point: shadow.position), duration: 0.95)
        CATransaction.commit()
        return true
    }

    private func finishOpening() {
        guard stage != nil, mode == .opening else { return }
        // prima si disegna il libro aperto, poi si toglie lo strato: niente lampo in mezzo
        mode = .open
        contentAlpha = 0
        needsDisplay = true
        displayIfNeeded()
        stage?.removeFromSuperview()
        stage = nil
        let start = Date()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let t = min(Date().timeIntervalSince(start) / 0.3, 1)
            self.contentAlpha = CGFloat(t)
            self.needsDisplay = true
            if t >= 1 {
                timer.invalidate()
                self.contentTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        contentTimer = timer
    }

    // MARK: la pagina che gira

    /// Una pagina che gira da destra a sinistra (avanti) o da sinistra a destra (indietro), con sotto le pagine che si scoprono.
    fileprivate func playTurn(from old: Snapshot, to new: Snapshot, forward: Bool) {
        let opened = spreadRect
        let halfWidth = opened.width / 2
        let leftHalf = NSRect(x: opened.minX, y: opened.minY, width: halfWidth, height: opened.height)
        let rightHalf = NSRect(x: opened.midX, y: opened.minY, width: halfWidth, height: opened.height)
        let size = CGSize(width: halfWidth, height: opened.height)
        guard let oldLeft = old.crop(leftHalf), let oldRight = old.crop(rightHalf), let newLeft = new.crop(leftHalf), let newRight = new.crop(rightHalf),
              let (stage, container) = makeStage() else { return }
        _ = stage
        // sotto: la pagina che resta ferma e quella che si scopre
        let lowerLeft = imageLayer(forward ? oldLeft : newLeft, frame: layerRect(leftHalf), scale: old.scale)
        let lowerRight = imageLayer(forward ? newRight : oldRight, frame: layerRect(rightHalf), scale: old.scale)
        container.addSublayer(lowerLeft)
        container.addSublayer(lowerRight)
        // l'ombra che il foglio butta sulla pagina che copre
        let covered = forward ? lowerRight : lowerLeft
        let cast = CAGradientLayer()
        cast.frame = covered.bounds
        cast.colors = [NSColor.black.withAlphaComponent(0.38).cgColor, NSColor.black.withAlphaComponent(0).cgColor]
        cast.startPoint = CGPoint(x: forward ? 0 : 1, y: 0.5)
        cast.endPoint = CGPoint(x: forward ? 0.55 : 0.45, y: 0.5)
        cast.opacity = 0
        covered.addSublayer(cast)

        let parts = makeLeaf(front: forward ? oldRight : oldLeft, frontSize: size, back: forward ? newLeft : newRight, backSize: size, size: size,
                             scale: old.scale, forward: forward)
        parts.leaf.position = CGPoint(x: opened.midX, y: bounds.height - opened.midY)
        container.addSublayer(parts.leaf)

        let angle = forward ? -Double.pi : Double.pi
        let duration: CFTimeInterval = 0.6
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in self?.finishTurn() }
        parts.leaf.transform = CATransform3DMakeRotation(CGFloat(angle), 0, 1, 0)
        parts.frontShade.opacity = 0.3
        parts.backShade.opacity = 0
        animate(parts.leaf, "transform.rotation.y", from: 0, to: angle, duration: duration)
        animate(parts.frontShade, "opacity", from: 0, to: 0.3, duration: duration)
        animate(parts.backShade, "opacity", from: 0.3, to: 0, duration: duration)
        let castAnimation = CAKeyframeAnimation(keyPath: "opacity")
        castAnimation.values = [0, 1, 0]
        castAnimation.keyTimes = [0, 0.5, 1]
        castAnimation.duration = duration
        castAnimation.beginTime = cast.convertTime(CACurrentMediaTime(), from: nil)
        castAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cast.add(castAnimation, forKey: "opacity")
        CATransaction.commit()
    }

    private func finishTurn() {
        guard stage != nil, mode == .open else { return }
        needsDisplay = true
        displayIfNeeded()
        stage?.removeFromSuperview()
        stage = nil
        if let next = queuedSpread {
            queuedSpread = nil
            goToSpread(next)
        }
    }
}

/// Tiene la finestra dell'album.
final class AlbumController {
    private var window: NSWindow?
    private var view: AlbumView?
    /// Chiamata dal pulsante «‹ Menu»: la finestra si chiude e si torna alla scheda del menu.
    var onBack: (() -> Void)?

    func show() {
        if window == nil {
            let view = AlbumView(garden: .shared, profile: .shared)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: AlbumView.size), styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.contentView = view
            window.isReleasedWhenClosed = false
            window.backgroundColor = MeadowBackdrop.base
            window.appearance = NSAppearance(named: .aqua)
            view.onBack = { [weak self, weak window] in
                window?.orderOut(nil)
                self?.onBack?()
            }
            window.center()
            self.window = window
            self.view = view
        }
        window?.title = Profile.shared.albumTitle
        view?.prepare()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(view)
    }
}
