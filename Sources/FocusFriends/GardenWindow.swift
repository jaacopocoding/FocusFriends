import AppKit

/// Il giardino: un prato tuo, che arredi con gli oggetti che sblocchi studiando. I punti si guadagnano con le ore di
/// studio (GardenPoints) e si spendono nel negozio, a destra: un oggetto si sblocca una volta e poi se ne mettono
/// quanti se ne vogliono. Si trascina tutto dove si vuole. I compagni sbloccati stanno qui, e se li tocchi parlano.
///
/// La scena è un disegno solo; gli oggetti e i compagni si disegnano sopra, più piccoli verso il fondo.
final class GardenView: NSView, NSViewToolTipOwner {
    /// La scena (senza il negozio): la proporzione è quella del disegno del prato (1024×506).
    static let sceneSize = NSSize(width: 1000, height: 494)
    static let shopWidth: CGFloat = 330
    private static let pad: CGFloat = 14

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private let log: SessionLog
    private let garden: Garden
    private let profile: Profile
    private let now: () -> Date
    private let calendar = StudyPeriod.calendar()

    // I punti, ricavati dal registro (reload).
    private var earned = 0
    private var balance = 0
    private var streak = StudyStreak.Result(perDay: [:], days: 0, isFrozen: false, studiedToday: false)
    private var factor = 1.0

    // Il negozio.
    private(set) var isShopOpen = false
    private var category: GardenCategory = .flowers
    private var scrollOffset: CGFloat = 0
    /// L'oggetto di cui si sta per spendere i punti: serve un secondo tocco per confermare.
    private var confirming: String?
    /// Una riga di spiegazione in fondo al negozio, per qualche secondo.
    private var message: String?
    private var messageTimer: Timer?

    // Quello che si sta trascinando.
    private enum Carry: Equatable {
        case placed(UUID)
        case companion(String)
        case fresh(String)
    }
    private var carry: Carry?
    private var carryFeet = NSPoint.zero
    private var carryGrab = NSSize.zero
    private var carryStart = NSPoint.zero
    private var carryMoved = false

    // Il fumetto di un compagno toccato.
    private var bubble: (petID: String, text: String)?
    private var bubbleTimer: Timer?

    private let shopButton: PillIconButton
    /// Chiamata dal pulsante «‹ Menu»: la finestra si chiude e si torna alla scheda del menu.
    var onBack: (() -> Void)?
    /// Chiamata quando il negozio si apre o si chiude: la finestra si allarga o si stringe.
    var onShopToggle: ((Bool) -> Void)?

    init(log: SessionLog, garden: Garden, profile: Profile, now: @escaping () -> Date = Date.init) {
        self.log = log
        self.garden = garden
        self.profile = profile
        self.now = now
        shopButton = PillIconButton(caption: "Negozio", symbol: "bag", size: NSSize(width: 112, height: 30),
                                    target: nil, action: #selector(toggleShop), tip: "Apri il negozio")
        super.init(frame: NSRect(origin: .zero, size: Self.sceneSize))
        appearance = NSAppearance(named: .aqua)
        setAccessibilityLabel("Il giardino")

        let back = BackToMenuButton(target: self, action: #selector(backPressed))
        back.setFrameOrigin(NSPoint(x: 16, y: 14))
        addSubview(back)

        shopButton.target = self
        shopButton.setFrameOrigin(NSPoint(x: Self.sceneSize.width - 16 - 112, y: 14))
        addSubview(shopButton)

        // Chiusa la finestra non serve ricalcolare: alla riapertura `show` lo fa. (Minimizzata sì: è ancora lì.)
        log.addObserver { [weak self] in
            guard let self, self.window.map({ $0.isVisible || $0.isMiniaturized }) ?? true else { return }
            self.reload()
        }
        garden.addObserver { [weak self] in self?.reload() }
        reload()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Dati

    /// Rifà i conti dei punti e ridisegna.
    func reload() {
        let today = now()
        streak = StudyStreak.analyze(sessions: log.sessions, now: today, calendar: calendar)
        let weighted = GardenPoints.weightedMinutes(sessions: log.sessions, now: today, calendar: calendar)
        earned = GardenPoints.points(forWeightedMinutes: weighted)
        balance = GardenPoints.balance(earned: earned, spent: garden.spent)
        factor = GardenPoints.multiplierToday(streak)
        removeAllToolTips()
        let hud = hudLayout()
        addToolTip(hud.points, owner: self, userData: UnsafeMutableRawPointer(bitPattern: 1))
        if let chip = hud.factor { addToolTip(chip, owner: self, userData: UnsafeMutableRawPointer(bitPattern: 2)) }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    /// Esc: chiude il negozio (o lascia a metà un oggetto che si sta trascinando).
    override func cancelOperation(_ sender: Any?) {
        if carry != nil {
            cancelCarry()
        } else if isShopOpen {
            setShopOpen(false)
        }
    }

    @objc private func backPressed() {
        cancelCarry()
        onBack?()
    }

    @objc private func toggleShop() {
        setShopOpen(!isShopOpen)
    }

    func setShopOpen(_ open: Bool) {
        guard open != isShopOpen else { return }
        cancelCarry()
        isShopOpen = open
        confirming = nil
        message = nil
        shopButton.caption = open ? "Chiudi" : "Negozio"
        shopButton.symbolName = open ? "xmark" : "bag"
        onShopToggle?(open)
        needsDisplay = true
    }

    private func cancelCarry() {
        carry = nil
        carryMoved = false
        NSCursor.arrow.set()
        needsDisplay = true
    }

    // MARK: - Geometria

    private var sceneW: CGFloat { Self.sceneSize.width }
    private var sceneH: CGFloat { Self.sceneSize.height }
    private var sceneRect: NSRect { NSRect(origin: .zero, size: Self.sceneSize) }
    private var shopRect: NSRect { NSRect(x: sceneW, y: 0, width: Self.shopWidth, height: sceneH) }

    private func point(for spot: GardenSpot) -> NSPoint {
        NSPoint(x: CGFloat(spot.x) * sceneW, y: CGFloat(spot.y) * sceneH)
    }

    private func spot(for point: NSPoint) -> GardenSpot {
        GardenScene.clamped(GardenSpot(x: Double(point.x / sceneW), y: Double(point.y / sceneH)))
    }

    /// L'altezza a cui si disegna un oggetto con i piedi in `spot`: più piccolo verso il fondo del prato.
    private func displayHeight(_ referenceHeight: Double, at spot: GardenSpot) -> CGFloat {
        CGFloat(referenceHeight * GardenScene.depthScale(y: spot.y)) * sceneH / CGFloat(GardenScene.size.height)
    }

    // MARK: - Le immagini

    private struct Sprite {
        let image: NSImage
        /// La parte che non è trasparente, in coordinate dell'immagine (origine in basso a sinistra).
        let source: NSRect
        /// Una griglia grossolana dei punti disegnati (dall'alto in basso), per capire se un clic cade sull'oggetto
        /// e non sul vuoto dentro il suo rettangolo (un arco, le bandierine).
        let mask: [Bool]
        let columns: Int
        let rows: Int
        var aspect: CGFloat { source.width / max(source.height, 1) }

        /// C'è qualcosa di disegnato in (u, v), dentro la parte visibile (v dall'alto), o a una cella di distanza?
        func isDrawn(u: CGFloat, v: CGFloat) -> Bool {
            guard columns > 0, rows > 0, !mask.isEmpty else { return true }
            let column = Int((u * CGFloat(columns)).rounded(.down)), row = Int((v * CGFloat(rows)).rounded(.down))
            for r in max(row - 1, 0)...min(row + 1, rows - 1) {
                for c in max(column - 1, 0)...min(column + 1, columns - 1) where mask[r * columns + c] { return true }
            }
            return false
        }
    }

    private static var sprites: [String: Sprite] = [:]

    private static func sprite(_ resource: String) -> Sprite? {
        if let known = sprites[resource] { return known }
        guard let url = Bundle.main.url(forResource: resource, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        let made = analyze(image)
        sprites[resource] = made
        return made
    }

    /// Cerca i pixel non trasparenti: i compagni hanno un bordo vuoto intorno, e i piedi devono stare dove dice il
    /// prato, non dove finisce l'immagine. Ne ricava anche la griglia dei punti disegnati (per i clic).
    private static func analyze(_ image: NSImage) -> Sprite {
        let full = Sprite(image: image, source: NSRect(origin: .zero, size: image.size), mask: [], columns: 0, rows: 0)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return full }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return full }
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return full }
        let threshold: UInt8 = 24
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h {
            for x in 0..<w where data[(y * w + x) * 4 + 3] > threshold {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return full }
        let boxW = maxX - minX + 1, boxH = maxY - minY + 1
        // La griglia dei clic: al massimo 64 celle sul lato lungo.
        let long = 64
        let columns = boxW >= boxH ? long : max(1, Int((Double(long) * Double(boxW) / Double(boxH)).rounded()))
        let rows = boxH > boxW ? long : max(1, Int((Double(long) * Double(boxH) / Double(boxW)).rounded()))
        var mask = [Bool](repeating: false, count: columns * rows)
        for y in minY...maxY {
            let row = min((y - minY) * rows / boxH, rows - 1)
            for x in minX...maxX where data[(y * w + x) * 4 + 3] > threshold {
                mask[row * columns + min((x - minX) * columns / boxW, columns - 1)] = true
            }
        }
        // La memoria parte dalla riga in alto: nell'immagine l'origine è in basso.
        let sx = image.size.width / CGFloat(w), sy = image.size.height / CGFloat(h)
        let source = NSRect(x: CGFloat(minX) * sx, y: CGFloat(h - 1 - maxY) * sy, width: CGFloat(boxW) * sx, height: CGFloat(boxH) * sy)
        return Sprite(image: image, source: source, mask: mask, columns: columns, rows: rows)
    }

    private lazy var meadow: NSImage? = {
        Bundle.main.url(forResource: "giardino_prato", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    }()

    // MARK: - Cosa c'è nel prato

    private enum Kind: Equatable {
        case placed(UUID)
        case companion(String)
    }

    /// Una cosa nel prato, con dove cade a schermo.
    private struct Entity {
        var kind: Kind
        var sprite: Sprite
        var spot: GardenSpot
        var feet: NSPoint
        var rect: NSRect
        var shadow: Bool
    }

    private func entity(kind: Kind, resource: String, referenceHeight: Double, spot: GardenSpot, shadow: Bool) -> Entity? {
        guard let sprite = Self.sprite(resource) else { return nil }
        let feet = point(for: spot)
        let height = displayHeight(referenceHeight, at: spot)
        let width = height * sprite.aspect
        let rect = NSRect(x: feet.x - width / 2, y: feet.y - height, width: width, height: height)
        return Entity(kind: kind, sprite: sprite, spot: spot, feet: feet, rect: rect, shadow: shadow)
    }

    /// Gli oggetti e i compagni sbloccati, dal fondo al davanti. Quello che si sta trascinando sta dove lo tiene il
    /// mouse (e va per ultimo, sopra a tutto).
    private func entities() -> [Entity] {
        var result: [Entity] = []
        var lifted: Entity?
        for placement in garden.placements {
            guard let item = GardenCatalog.item(withID: placement.item) else { continue }
            let kind = Kind.placed(placement.id)
            var at = placement.spot
            let isCarried = carry == .placed(placement.id)
            if isCarried { at = spot(for: carryFeet) }
            guard let made = entity(kind: kind, resource: item.resource, referenceHeight: item.height, spot: at, shadow: item.castsShadow)
            else { continue }
            if isCarried { lifted = made } else { result.append(made) }
        }
        for (index, pet) in Pet.all.enumerated() where profile.isCompanionUnlocked(pet.id) {
            var at = garden.companionSpot(pet.id, index: index)
            let isCarried = carry == .companion(pet.id)
            if isCarried { at = spot(for: carryFeet) }
            guard let made = entity(kind: .companion(pet.id), resource: pet.iconResource,
                                    referenceHeight: GardenCatalog.companionHeight(for: pet.id), spot: at, shadow: true)
            else { continue }
            if isCarried { lifted = made } else { result.append(made) }
        }
        result.sort { $0.feet.y < $1.feet.y }
        if let lifted { result.append(lifted) }
        return result
    }

    /// La cosa più davanti sotto il mouse, contando solo dove l'immagine è disegnata (con una cella di margine):
    /// così si può toccare un compagno che sta dietro le bandierine o sotto l'arco.
    private func entity(at point: NSPoint) -> Entity? {
        for entity in entities().reversed() where entity.rect.contains(point) {
            let u = (point.x - entity.rect.minX) / entity.rect.width
            let v = (point.y - entity.rect.minY) / entity.rect.height
            if entity.sprite.isDrawn(u: u, v: v) { return entity }
        }
        return nil
    }

    // MARK: - Il negozio: disposizione

    private struct ShopLayout {
        var tabs: [(category: GardenCategory, rect: NSRect)]
        var area: NSRect
        var cards: [(item: GardenItem, rect: NSRect)]
        var contentHeight: CGFloat
    }

    private static let tabFont = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
    private static let cardHeight: CGFloat = 86
    private static let cardGap: CGFloat = 8
    private static let columns = 3

    private func shopLayout() -> ShopLayout {
        let x0 = shopRect.minX, pad = Self.pad
        var tabs: [(category: GardenCategory, rect: NSRect)] = []
        var tx = x0 + pad
        for cat in GardenCategory.allCases {
            let width = ceil((cat.title as NSString).size(withAttributes: [.font: Self.tabFont]).width) + 24
            tabs.append((cat, NSRect(x: tx, y: 54, width: width, height: 28)))
            tx += width + 6
        }
        let area = NSRect(x: x0 + pad, y: 90, width: Self.shopWidth - 2 * pad, height: sceneH - 90 - 34)
        let gap = Self.cardGap
        let cardWidth = floor((area.width - CGFloat(Self.columns - 1) * gap) / CGFloat(Self.columns))
        let items = GardenCatalog.items(in: category)
        var cards: [(item: GardenItem, rect: NSRect)] = []
        for (index, item) in items.enumerated() {
            let row = index / Self.columns, column = index % Self.columns
            cards.append((item, NSRect(x: area.minX + CGFloat(column) * (cardWidth + gap),
                                       y: area.minY + CGFloat(row) * (Self.cardHeight + gap) - scrollOffset,
                                       width: cardWidth, height: Self.cardHeight)))
        }
        let rows = (items.count + Self.columns - 1) / Self.columns
        let content = CGFloat(rows) * Self.cardHeight + CGFloat(max(rows - 1, 0)) * gap
        return ShopLayout(tabs: tabs, area: area, cards: cards, contentHeight: content)
    }

    private var maxScroll: CGFloat {
        let layout = shopLayout()
        return max(0, layout.contentHeight - layout.area.height)
    }

    // MARK: - I comandi in alto

    private struct HUDLayout {
        var points: NSRect
        var factor: NSRect?
    }

    private let numberFont = Paper.markerFont(20)
    private let smallFont = NSFont.systemFont(ofSize: 12, weight: .medium)

    private func pointsWord(_ count: Int) -> String { count == 1 ? "punto" : "punti" }

    private func hudLayout() -> HUDLayout {
        let numberWidth = ceil(("\(balance)" as NSString).size(withAttributes: [.font: numberFont]).width)
        let labelWidth = ceil((pointsWord(balance) as NSString).size(withAttributes: [.font: smallFont]).width)
        let width = 14 + numberWidth + 6 + labelWidth + 14
        let shopX = sceneW - 16 - 112
        let points = NSRect(x: shopX - 10 - width, y: 14, width: width, height: 30)
        var chip: NSRect?
        if factor > 1 || streak.isFrozen {
            let text = factor > 1 ? "×" + GardenPoints.text(forMultiplier: factor) : "ghiacciata"
            let textWidth = ceil((text as NSString).size(withAttributes: [.font: smallFont]).width)
            let icon: CGFloat = streak.isFrozen ? 18 : 0
            let chipWidth = 12 + icon + textWidth + 12
            chip = NSRect(x: points.minX - 8 - chipWidth, y: 14, width: chipWidth, height: 30)
        }
        return HUDLayout(points: points, factor: chip)
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        if Int(bitPattern: data) == 1 {
            return "Punti del giardino: uno per ogni ora di studio (anche dei focus interrotti). Con 3 giorni di fila "
                + "ogni minuto vale ×1,25, con 7 ×1,5, con 14 ×2. Servono per sbloccare gli oggetti del negozio."
        }
        var text = "Serie di \(streak.days) \(streak.days == 1 ? "giorno" : "giorni")"
        if factor > 1 {
            text += ": oggi ogni minuto vale ×\(GardenPoints.text(forMultiplier: factor))"
        }
        if streak.isFrozen {
            text += ". Ieri non hai studiato: la serie è ghiacciata, studia oggi per non perderla."
        }
        return text + "."
    }

    // MARK: - Disegno

    private func text(_ string: String, in rect: NSRect, font: NSFont, color: NSColor = Paper.ink,
                      alignment: NSTextAlignment = .left) {
        let para = NSMutableParagraphStyle()
        para.alignment = alignment
        para.lineBreakMode = .byTruncatingTail
        (string as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .high
        if let meadow {
            meadow.draw(in: sceneRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else {
            Paper.paper.setFill()
            sceneRect.fill()
        }
        let laid = entities()
        for entity in laid { drawEntity(entity, lifted: carry != nil && entity.kind == carryKind && carryMoved) }
        if let bubble, let target = laid.first(where: { $0.kind == .companion(bubble.petID) }) {
            drawBubble(bubble.text, above: target.rect)
        }
        drawHUD()
        if garden.placements.isEmpty && !isShopOpen && carry == nil {
            drawHint("Apri il negozio e trascina qualcosa nel prato.")
        }
        if isShopOpen { drawShop() }
        // Un oggetto nuovo preso dal negozio: si vede sotto al mouse.
        if case .fresh(let id)? = carry, carryMoved, let item = GardenCatalog.item(withID: id),
           let made = entity(kind: .placed(UUID()), resource: item.resource, referenceHeight: item.height,
                             spot: spot(for: carryFeet), shadow: item.castsShadow) {
            drawEntity(made, lifted: true)
        }
    }

    private var carryKind: Kind? {
        switch carry {
        case .placed(let id)?: return .placed(id)
        case .companion(let id)?: return .companion(id)
        default: return nil
        }
    }

    private func drawEntity(_ entity: Entity, lifted: Bool) {
        let rect = lifted ? entity.rect.offsetBy(dx: 0, dy: -4) : entity.rect
        if entity.shadow {
            let width = entity.rect.width * 0.7
            let height = max(entity.rect.height * 0.09, 5)
            let shadow = NSRect(x: entity.feet.x - width / 2, y: entity.feet.y - height * 0.45, width: width, height: height)
            NSColor(calibratedRed: 0.24, green: 0.32, blue: 0.20, alpha: lifted ? 0.18 : 0.26).setFill()
            NSBezierPath(ovalIn: shadow).fill()
        }
        entity.sprite.image.draw(in: rect, from: entity.sprite.source, operation: .sourceOver, fraction: 1,
                                 respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }

    private func drawChip(_ rect: NSRect, fill: NSColor, stroke: NSColor) {
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = 1.2
        path.stroke()
    }

    private func tinted(_ symbol: String, size: CGFloat, color: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        guard let source = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return nil }
        return NSImage(size: source.size, flipped: false) { box in
            source.draw(in: box)
            color.set()
            box.fill(using: .sourceAtop)
            return true
        }
    }

    private func drawHUD() {
        let hud = hudLayout()
        // I punti
        drawChip(hud.points, fill: NSColor(calibratedRed: 1, green: 0.99, blue: 0.94, alpha: 0.95), stroke: Paper.paperEdge)
        let numberWidth = ceil(("\(balance)" as NSString).size(withAttributes: [.font: numberFont]).width)
        text("\(balance)", in: NSRect(x: hud.points.minX + 14, y: hud.points.minY + 3, width: numberWidth + 2, height: 26), font: numberFont)
        text(pointsWord(balance), in: NSRect(x: hud.points.minX + 14 + numberWidth + 6, y: hud.points.minY + 8, width: 50, height: 16),
             font: smallFont, color: Paper.inkLight)
        // Il valore di un minuto, o la serie ghiacciata
        if let rect = hud.factor {
            let ice = NSColor(calibratedRed: 0.20, green: 0.38, blue: 0.58, alpha: 1)
            if streak.isFrozen {
                drawChip(rect, fill: NSColor(calibratedRed: 0.85, green: 0.93, blue: 0.99, alpha: 0.96),
                         stroke: NSColor(calibratedRed: 0.45, green: 0.66, blue: 0.86, alpha: 1))
                var x = rect.minX + 12
                if let flake = tinted("snowflake", size: 12, color: NSColor(calibratedRed: 0.30, green: 0.55, blue: 0.82, alpha: 1)) {
                    flake.draw(in: NSRect(x: x, y: rect.midY - flake.size.height / 2, width: flake.size.width, height: flake.size.height))
                    x += 18
                }
                let label = factor > 1 ? "×" + GardenPoints.text(forMultiplier: factor) : "ghiacciata"
                text(label, in: NSRect(x: x, y: rect.minY + 8, width: rect.maxX - x - 8, height: 16), font: smallFont, color: ice)
            } else {
                drawChip(rect, fill: Paper.accent.withAlphaComponent(0.18), stroke: Paper.accent.withAlphaComponent(0.5))
                text("×" + GardenPoints.text(forMultiplier: factor),
                     in: NSRect(x: rect.minX + 12, y: rect.minY + 8, width: rect.width - 24, height: 16),
                     font: smallFont, color: Paper.accentPressed)
            }
        }
    }

    private func drawHint(_ string: String) {
        let width: CGFloat = 400
        let rect = NSRect(x: (sceneW - width) / 2, y: sceneH - 50, width: width, height: 34)
        let pill = NSBezierPath(roundedRect: rect, xRadius: 17, yRadius: 17)
        Paper.paper.withAlphaComponent(0.88).setFill()
        pill.fill()
        text(string, in: NSRect(x: rect.minX, y: rect.minY + 8, width: rect.width, height: 18),
             font: NSFont.systemFont(ofSize: 13), color: Paper.inkLight, alignment: .center)
    }

    private func drawBubble(_ string: String, above rect: NSRect) {
        let font = NSFont.systemFont(ofSize: 12.5)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Paper.ink]
        let bounds = (string as NSString).boundingRect(with: NSSize(width: 230, height: 300),
                                                       options: [.usesLineFragmentOrigin], attributes: attributes)
        let width = ceil(bounds.width) + 24, height = ceil(bounds.height) + 18
        let x = min(max(rect.midX - width / 2, 8), sceneW - width - 8)
        let y = max(rect.minY - height - 12, 56)
        let box = NSRect(x: x, y: y, width: width, height: height)
        let path = NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12)
        let tailX = min(max(rect.midX, box.minX + 18), box.maxX - 18)
        path.move(to: NSPoint(x: tailX - 7, y: box.maxY - 0.5))
        path.line(to: NSPoint(x: tailX, y: box.maxY + 9))
        path.line(to: NSPoint(x: tailX + 7, y: box.maxY - 0.5))
        NSColor(calibratedRed: 1, green: 0.99, blue: 0.94, alpha: 0.97).setFill()
        path.fill()
        Paper.paperEdge.setStroke()
        path.lineWidth = 1.2
        path.stroke()
        (string as NSString).draw(in: NSRect(x: box.minX + 12, y: box.minY + 9, width: width - 24, height: height - 14),
                                  withAttributes: attributes)
    }

    // MARK: - Disegno del negozio

    private func drawShop() {
        let panel = shopRect
        Paper.paper.setFill()
        panel.fill()
        Paper.paperEdge.setStroke()
        let edge = NSBezierPath()
        edge.move(to: NSPoint(x: panel.minX + 0.5, y: 0))
        edge.line(to: NSPoint(x: panel.minX + 0.5, y: panel.maxY))
        edge.lineWidth = 1.5
        edge.stroke()

        let layout = shopLayout()
        let pad = Self.pad
        text("Il negozio", in: NSRect(x: panel.minX + pad, y: 14, width: 160, height: 30), font: Paper.markerFont(24))
        // il saldo
        let numberWidth = ceil(("\(balance)" as NSString).size(withAttributes: [.font: numberFont]).width)
        let labelWidth = ceil((pointsWord(balance) as NSString).size(withAttributes: [.font: smallFont]).width)
        let chipWidth = 14 + numberWidth + 6 + labelWidth + 14
        let chip = NSRect(x: panel.maxX - pad - chipWidth, y: 14, width: chipWidth, height: 30)
        drawChip(chip, fill: NSColor(calibratedRed: 0.97, green: 0.87, blue: 0.75, alpha: 1), stroke: .clear)
        text("\(balance)", in: NSRect(x: chip.minX + 14, y: chip.minY + 3, width: numberWidth + 2, height: 26), font: numberFont)
        text(pointsWord(balance), in: NSRect(x: chip.minX + 14 + numberWidth + 6, y: chip.minY + 8, width: 50, height: 16),
             font: smallFont, color: Paper.inkLight)
        // le schede
        for tab in layout.tabs {
            let selected = tab.category == category
            let path = NSBezierPath(roundedRect: tab.rect, xRadius: 14, yRadius: 14)
            if selected {
                Paper.accent.setFill()
                path.fill()
            } else {
                Paper.paperEdge.setStroke()
                path.lineWidth = 1.2
                path.stroke()
            }
            text(tab.category.title, in: NSRect(x: tab.rect.minX, y: tab.rect.minY + 6, width: tab.rect.width, height: 16),
                 font: Self.tabFont, color: selected ? .white : Paper.inkLight, alignment: .center)
        }
        // le carte, ritagliate nella loro area (si scorrono con la rotella)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: layout.area).addClip()
        for card in layout.cards where card.rect.maxY > layout.area.minY && card.rect.minY < layout.area.maxY {
            drawCard(card.item, in: card.rect)
        }
        NSGraphicsContext.restoreGraphicsState()
        // in fondo: cosa si può fare
        let footer = NSRect(x: panel.minX + pad, y: sceneH - 31, width: panel.width - 2 * pad, height: 28)
        let line = message ?? defaultShopHint
        (line as NSString).draw(in: footer, withAttributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: Paper.inkLight,
        ])
        // trascinando un oggetto del prato sul negozio: lo si toglie
        if case .placed? = carry, carryMoved, panel.contains(carryPointer) {
            Paper.accent.withAlphaComponent(0.14).setFill()
            panel.fill()
            text("Rilascia per togliere", in: NSRect(x: panel.minX, y: panel.midY - 12, width: panel.width, height: 26),
                 font: Paper.markerFont(20), color: Paper.accentPressed, alignment: .center)
        }
    }

    private var defaultShopHint: String {
        "Un oggetto si sblocca una volta, poi ne metti quanti vuoi. Trascinalo nel prato; per toglierlo, trascinalo qui."
    }

    private var carryPointer = NSPoint.zero

    private func drawCard(_ item: GardenItem, in rect: NSRect) {
        let unlocked = garden.isUnlocked(item.id)
        let affordable = unlocked || item.price <= balance
        let isConfirming = confirming == item.id
        let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        NSColor(calibratedRed: 1, green: 0.99, blue: 0.94, alpha: 1).setFill()
        path.fill()
        (isConfirming ? Paper.accent : Paper.paperEdge).setStroke()
        path.lineWidth = isConfirming ? 2.5 : 1.2
        path.stroke()

        if let sprite = Self.sprite(item.resource) {
            let box = NSRect(x: rect.minX + 8, y: rect.minY + 6, width: rect.width - 16, height: 44)
            let scale = min(box.width / sprite.source.width, box.height / sprite.source.height)
            let size = NSSize(width: sprite.source.width * scale, height: sprite.source.height * scale)
            let target = NSRect(x: box.midX - size.width / 2, y: box.maxY - size.height, width: size.width, height: size.height)
            sprite.image.draw(in: target, from: sprite.source, operation: .sourceOver, fraction: affordable ? 1 : 0.4,
                              respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        }
        var font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        if (item.name as NSString).size(withAttributes: [.font: font]).width > rect.width - 8 {
            font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        }
        text(item.name, in: NSRect(x: rect.minX + 3, y: rect.minY + 51, width: rect.width - 6, height: 14), font: font,
             color: affordable ? Paper.ink : Paper.inkLight, alignment: .center)

        let label: String
        let color: NSColor
        if unlocked {
            label = "Tuo"
            color = NSColor(calibratedRed: 0.38, green: 0.58, blue: 0.36, alpha: 1)
        } else if isConfirming {
            label = "Sblocca"
            color = Paper.accentPressed
        } else {
            label = "\(item.price) \(item.price == 1 ? "punto" : "punti")"
            color = affordable ? Paper.accent : NSColor(calibratedRed: 0.72, green: 0.68, blue: 0.62, alpha: 1)
        }
        let chipFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let chipWidth = ceil((label as NSString).size(withAttributes: [.font: chipFont]).width) + 16
        let chip = NSRect(x: rect.midX - chipWidth / 2, y: rect.minY + 66, width: chipWidth, height: 16)
        color.setFill()
        NSBezierPath(roundedRect: chip, xRadius: 8, yRadius: 8).fill()
        text(label, in: NSRect(x: chip.minX, y: chip.minY + 2, width: chip.width, height: 13), font: chipFont, color: .white,
             alignment: .center)
    }

    // MARK: - Il mouse

    private func flash(_ string: String) {
        message = string
        messageTimer?.invalidate()
        messageTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            self?.message = nil
            self?.needsDisplay = true
        }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        carryPointer = p
        carryStart = p
        carryMoved = false
        bubble = nil
        if isShopOpen && shopRect.contains(p) {
            shopMouseDown(at: p)
            return
        }
        confirming = nil
        guard sceneRect.contains(p), let found = entity(at: p) else {
            needsDisplay = true
            return
        }
        switch found.kind {
        case .placed(let id): carry = .placed(id)
        case .companion(let petID): carry = .companion(petID)
        }
        carryGrab = NSSize(width: found.feet.x - p.x, height: found.feet.y - p.y)
        carryFeet = found.feet
        needsDisplay = true
    }

    private func shopMouseDown(at p: NSPoint) {
        let layout = shopLayout()
        if let tab = layout.tabs.first(where: { $0.rect.contains(p) }) {
            category = tab.category
            scrollOffset = 0
            confirming = nil
            message = nil
            needsDisplay = true
            return
        }
        guard layout.area.contains(p), let card = layout.cards.first(where: { $0.rect.contains(p) }) else {
            confirming = nil
            needsDisplay = true
            return
        }
        let item = card.item
        if garden.isUnlocked(item.id) {
            // Si prende una copia: un clic la mette nel prato, trascinando la si mette dove si lascia.
            confirming = nil
            carry = .fresh(item.id)
            carryGrab = .zero
            carryFeet = p
        } else if item.price <= balance {
            if confirming == item.id {
                if garden.unlock(item.id, balance: balance) {
                    garden.place(item.id, at: GardenScene.defaultPlacementSpot(salt: garden.placements.count + item.id.count))
                    flash("\(item.name): sbloccato e messo nel prato. Puoi metterne quanti vuoi.")
                }
                confirming = nil
            } else {
                confirming = item.id
                flash("\(item.name) costa \(item.price) \(item.price == 1 ? "punto" : "punti"): tocca ancora per sbloccarlo.")
            }
        } else {
            confirming = nil
            let missing = item.price - balance
            flash("Ti manc\(missing == 1 ? "a" : "ano") \(missing) \(missing == 1 ? "punto" : "punti") per \(item.name).")
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard carry != nil else { return }
        let p = convert(event.locationInWindow, from: nil)
        carryPointer = p
        if !carryMoved, hypot(p.x - carryStart.x, p.y - carryStart.y) > 4 { carryMoved = true }
        if carryMoved {
            NSCursor.closedHand.set()
            carryFeet = NSPoint(x: p.x + carryGrab.width, y: p.y + carryGrab.height)
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let current = carry else { return }
        let p = convert(event.locationInWindow, from: nil)
        let overShop = isShopOpen && shopRect.contains(p)
        let landing = spot(for: carryFeet)
        carry = nil
        NSCursor.arrow.set()
        switch current {
        case .placed(let id):
            if carryMoved {
                if overShop { garden.remove(id) } else { garden.move(id, to: landing) }
            }
        case .companion(let petID):
            if carryMoved {
                if !overShop { garden.setCompanionSpot(petID, to: landing) }
            } else {
                speak(petID)
            }
        case .fresh(let id):
            if !carryMoved {
                garden.place(id, at: GardenScene.defaultPlacementSpot(salt: garden.placements.count + id.count))
            } else if sceneRect.contains(p) {
                garden.place(id, at: landing)
            }
        }
        carryMoved = false
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard isShopOpen, shopRect.contains(p), maxScroll > 0 else {
            super.scrollWheel(with: event)
            return
        }
        scrollOffset = min(max(scrollOffset - event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 8), 0), maxScroll)
        needsDisplay = true
    }

    /// Un clic con il tasto destro su una copia: toglierla dal prato.
    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        guard sceneRect.contains(p), let found = entity(at: p), case .placed(let id) = found.kind else { return nil }
        let menu = NSMenu()
        let item = NSMenuItem(title: "Togli dal giardino", action: #selector(removeFromMenu(_:)), keyEquivalent: "")
        item.representedObject = id
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func removeFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        garden.remove(id)
    }

    private func speak(_ petID: String) {
        guard let pet = Pet.all.first(where: { $0.id == petID }) else { return }
        let phrases = Quotes.load(for: pet)
        bubble = (petID, phrases.randomElement() ?? pet.fallbackQuote)
        bubbleTimer?.invalidate()
        bubbleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            self?.bubble = nil
            self?.needsDisplay = true
        }
    }
}

/// Tiene la finestra del giardino.
final class GardenController {
    private var window: NSWindow?
    private var view: GardenView?
    /// Chiamata dal pulsante «‹ Menu» nella pagina: la finestra si chiude e si torna alla scheda del menu.
    var onBack: (() -> Void)?

    /// Quanto rimpicciolire il giardino perché ci stia, con il negozio aperto, nello schermo (1 = a grandezza piena).
    static func scale(forScreenWidth width: CGFloat) -> CGFloat {
        let full = GardenView.sceneSize.width + GardenView.shopWidth
        return min(1, max((width - 40) / full, 0.5))
    }

    func show() {
        if window == nil {
            let scale = Self.scale(forScreenWidth: NSScreen.main?.visibleFrame.width ?? 1440)
            let size = NSSize(width: GardenView.sceneSize.width * scale, height: GardenView.sceneSize.height * scale)
            let view = GardenView(log: .shared, garden: .shared, profile: .shared)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = Profile.shared.gardenTitle
            window.contentView = view
            // Su uno schermo stretto il disegno si rimpicciolisce (il sistema di coordinate resta lo stesso, e
            // resta anche la proporzione quando la finestra si allarga per il negozio).
            if scale < 1 { view.setBoundsSize(GardenView.sceneSize) }
            window.isReleasedWhenClosed = false
            window.backgroundColor = Paper.paper
            window.appearance = NSAppearance(named: .aqua)
            view.onBack = { [weak self, weak window] in
                window?.orderOut(nil)
                self?.onBack?()
            }
            // Il negozio è un pannello a destra: la finestra si allarga per farlo stare, senza coprire il prato.
            view.onShopToggle = { [weak window] open in
                guard let window else { return }
                let target = (GardenView.sceneSize.width + (open ? GardenView.shopWidth : 0)) * scale
                var frame = window.frame
                frame.size.width += target - window.contentRect(forFrameRect: frame).width
                if let visible = window.screen?.visibleFrame, frame.maxX > visible.maxX {
                    frame.origin.x = max(visible.minX, visible.maxX - frame.width)
                }
                window.setFrame(frame, display: true, animate: scale == 1)
            }
            window.center()
            self.window = window
            self.view = view
        }
        window?.title = Profile.shared.gardenTitle      // se nel frattempo è cambiato il nome
        view?.reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
