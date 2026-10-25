import AppKit

/// Il giardino: un prato tuo, che si riempie con le figurine che trovi a fine focus (GardenDrops). L'album delle figurine è un'altra
/// finestra (AlbumWindow); qui, in basso, c'è la cassetta con le copie ancora da mettere: si trascinano nel prato, si spostano, e per
/// toglierne una dal prato la si trascina sulla cassetta. I compagni sbloccati stanno qui, e se li tocchi parlano.
///
/// La scena è un disegno solo; gli oggetti e i compagni si disegnano sopra, più piccoli verso il fondo.
final class GardenView: NSView, NSViewToolTipOwner {
    /// La scena (senza il negozio): la proporzione è quella del disegno del prato (1024×506).
    static let sceneSize = NSSize(width: 1000, height: 494)
        private static let pad: CGFloat = 14

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private let log: SessionLog
    private let garden: Garden
    private let profile: Profile
    private let now: () -> Date
    private let calendar = StudyPeriod.calendar()

    // La serie di giorni (dal registro, in reload): più è lunga, più le figurine rare sono probabili.
    private var streak = StudyStreak.Result(perDay: [:], days: 0, isFrozen: false, studiedToday: false)

    // La cassetta delle copie da mettere: chiusa (una pillola in basso a sinistra, per non coprire il davanti del prato) finché non la apri.
    private var trayOpen = false
    private var trayScroll: CGFloat = 0
    /// Una riga di spiegazione in basso, per qualche secondo.
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

    private let albumButton: PillIconButton
    /// Chiamata dal pulsante «‹ Menu»: la finestra si chiude e si torna alla scheda del menu.
    var onBack: (() -> Void)?
    /// Chiamata dal pulsante «Album»: si apre la finestra dell'album.
    var onShowAlbum: (() -> Void)?

    init(log: SessionLog, garden: Garden, profile: Profile, now: @escaping () -> Date = Date.init) {
        self.log = log
        self.garden = garden
        self.profile = profile
        self.now = now
        albumButton = PillIconButton(caption: "Album", symbol: "book.closed", size: NSSize(width: 112, height: 30),
                                     target: nil, action: #selector(showAlbum), tip: "Apri l'album delle figurine")
        super.init(frame: NSRect(origin: .zero, size: Self.sceneSize))
        appearance = NSAppearance(named: .aqua)
        setAccessibilityLabel("Il giardino")

        let back = BackToMenuButton(target: self, action: #selector(backPressed))
        back.setFrameOrigin(NSPoint(x: 16, y: 14))
        addSubview(back)

        albumButton.target = self
        albumButton.setFrameOrigin(NSPoint(x: Self.sceneSize.width - 16 - 112, y: 14))
        addSubview(albumButton)

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

    /// Rifà i conti della serie e ridisegna.
    func reload() {
        streak = StudyStreak.analyze(sessions: log.sessions, now: now(), calendar: calendar)
        removeAllToolTips()
        let hud = hudLayout()
        addToolTip(hud.album, owner: self, userData: UnsafeMutableRawPointer(bitPattern: 1))
        if let chip = hud.streak { addToolTip(chip, owner: self, userData: UnsafeMutableRawPointer(bitPattern: 2)) }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    /// Esc: lascia a metà un oggetto che si sta trascinando.
    override func cancelOperation(_ sender: Any?) {
        if carry != nil { cancelCarry() }
    }

    @objc private func backPressed() {
        cancelCarry()
        onBack?()
    }

    @objc private func showAlbum() {
        cancelCarry()
        onShowAlbum?()
    }

    /// I regali del giardino della versione 1 (i punti non spesi) si sono appena aperti: una riga lo dice.
    func announceGifts(_ count: Int) {
        guard count > 0 else { return }
        flash(count == 1 ? "Il giardino è cambiato: c'è una figurina nuova per i punti che avevi. La trovi nell'album."
                         : "Il giardino è cambiato: ci sono \(count) figurine nuove per i punti che avevi. Le trovi nell'album.")
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
    private var trayRect: NSRect { NSRect(x: 0, y: sceneH - Self.trayHeight, width: sceneW, height: Self.trayHeight) }

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
        var sprite: GardenSprite
        var spot: GardenSpot
        var feet: NSPoint
        var rect: NSRect
        var shadow: Bool
    }

    private func entity(kind: Kind, resource: String, referenceHeight: Double, spot: GardenSpot, shadow: Bool) -> Entity? {
        guard let sprite = GardenSprites.sprite(resource) else { return nil }
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

    // MARK: - La cassetta: disposizione

    private static let trayHeight: CGFloat = 96
    private static let trayCell = NSSize(width: 84, height: 78)

    /// Le copie ancora da mettere nel prato, nell'ordine dell'album.
    private func trayItems() -> [(item: GardenItem, count: Int)] {
        GardenCatalog.items.compactMap { item in
            let count = garden.available(item.id)
            return count > 0 ? (item, count) : nil
        }
    }

    /// La fascia si vede aperta, oppure trascinando una copia del prato (per toglierla).
    private var trayVisible: Bool {
        (trayOpen && !trayItems().isEmpty) || (carryMoved && { if case .placed? = carry { return true } else { return false } }())
    }

    /// La pillola «Da mettere · 7», quando la cassetta è chiusa e c'è qualcosa dentro.
    private var trayPillRect: NSRect { NSRect(x: 16, y: sceneH - 46, width: 156, height: 30) }

    private var showsTrayPill: Bool { !trayVisible && !trayItems().isEmpty && !(carry != nil && carryMoved) }

    private struct TrayLayout {
        var area: NSRect
        var cells: [(item: GardenItem, count: Int, rect: NSRect)]
        var contentWidth: CGFloat
    }

    private func trayLayout() -> TrayLayout {
        let area = NSRect(x: 118, y: trayRect.minY + 8, width: sceneW - 118 - 16, height: Self.trayHeight - 16)
        let items = trayItems()
        var cells: [(item: GardenItem, count: Int, rect: NSRect)] = []
        for (index, entry) in items.enumerated() {
            cells.append((entry.item, entry.count, NSRect(x: area.minX + CGFloat(index) * Self.trayCell.width - trayScroll, y: area.minY + 2,
                                                          width: Self.trayCell.width - 4, height: Self.trayCell.height)))
        }
        return TrayLayout(area: area, cells: cells, contentWidth: CGFloat(items.count) * Self.trayCell.width)
    }

    private var maxTrayScroll: CGFloat {
        let layout = trayLayout()
        return max(0, layout.contentWidth - layout.area.width)
    }

    // MARK: - I comandi in alto

    private struct HUDLayout {
        /// «Album 12/36».
        var album: NSRect
        /// La serie di giorni (o il ghiaccio), se c'è.
        var streak: NSRect?
    }

    private let numberFont = Paper.markerFont(20)
    private let smallFont = NSFont.systemFont(ofSize: 12, weight: .medium)

    private var albumLabel: String { "\(garden.foundCount)/\(GardenCatalog.items.count)" }

    private var streakLabel: String? {
        if streak.isFrozen { return "ghiacciata" }
        return streak.days >= 2 ? "serie di \(streak.days)" : nil
    }

    private func hudLayout() -> HUDLayout {
        let numberWidth = ceil((albumLabel as NSString).size(withAttributes: [.font: numberFont]).width)
        let labelWidth = ceil(("figurine" as NSString).size(withAttributes: [.font: smallFont]).width)
        let width = 14 + numberWidth + 6 + labelWidth + 14
        let buttonX = sceneW - 16 - 112
        let album = NSRect(x: buttonX - 10 - width, y: 14, width: width, height: 30)
        var chip: NSRect?
        if let label = streakLabel {
            let textWidth = ceil((label as NSString).size(withAttributes: [.font: smallFont]).width)
            let icon: CGFloat = 18
            let chipWidth = 12 + icon + textWidth + 12
            chip = NSRect(x: album.minX - 8 - chipWidth, y: 14, width: chipWidth, height: 30)
        }
        return HUDLayout(album: album, streak: chip)
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        if Int(bitPattern: data) == 1 {
            return "L'album: \(garden.foundCount) figurine su \(GardenCatalog.items.count). Le trovi a fine focus (completato, con almeno 20 minuti): "
                + "una volta su cinque non esce niente. Con più giorni di fila e con i focus lunghi le figurine rare sono più probabili."
        }
        var text = "Serie di \(streak.days) \(streak.days == 1 ? "giorno" : "giorni")"
        if streak.isFrozen {
            text += ". Ieri non hai studiato: la serie è ghiacciata, studia oggi per non perderla."
        } else {
            text += ": con la serie le figurine rare sono più probabili."
        }
        return text
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
        if trayVisible { drawTray() } else if showsTrayPill { drawTrayPill() }
        if let message {
            drawHint(message)
        } else if garden.placements.isEmpty && carry == nil {
            drawHint("Trova le figurine a fine focus: si mettono qui da sole.")
        }
        // Una copia presa dall'album: si vede sotto al mouse.
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
        // L'album
        drawChip(hud.album, fill: NSColor(calibratedRed: 1, green: 0.99, blue: 0.94, alpha: 0.95), stroke: Paper.paperEdge)
        let numberWidth = ceil((albumLabel as NSString).size(withAttributes: [.font: numberFont]).width)
        text(albumLabel, in: NSRect(x: hud.album.minX + 14, y: hud.album.minY + 3, width: numberWidth + 2, height: 26), font: numberFont)
        text("figurine", in: NSRect(x: hud.album.minX + 14 + numberWidth + 6, y: hud.album.minY + 8, width: 70, height: 16),
             font: smallFont, color: Paper.inkLight)
        // La serie di giorni, o il ghiaccio
        if let rect = hud.streak, let label = streakLabel {
            if streak.isFrozen {
                let ice = NSColor(calibratedRed: 0.20, green: 0.38, blue: 0.58, alpha: 1)
                drawChip(rect, fill: NSColor(calibratedRed: 0.85, green: 0.93, blue: 0.99, alpha: 0.96),
                         stroke: NSColor(calibratedRed: 0.45, green: 0.66, blue: 0.86, alpha: 1))
                if let flake = tinted("snowflake", size: 12, color: NSColor(calibratedRed: 0.30, green: 0.55, blue: 0.82, alpha: 1)) {
                    flake.draw(in: NSRect(x: rect.minX + 12, y: rect.midY - flake.size.height / 2, width: flake.size.width, height: flake.size.height))
                }
                text(label, in: NSRect(x: rect.minX + 30, y: rect.minY + 8, width: rect.width - 38, height: 16), font: smallFont, color: ice)
            } else {
                drawChip(rect, fill: Paper.accent.withAlphaComponent(0.18), stroke: Paper.accent.withAlphaComponent(0.5))
                if let flame = tinted("flame", size: 12, color: Paper.accentPressed) {
                    flame.draw(in: NSRect(x: rect.minX + 12, y: rect.midY - flame.size.height / 2, width: flame.size.width, height: flame.size.height))
                }
                text(label, in: NSRect(x: rect.minX + 30, y: rect.minY + 8, width: rect.width - 38, height: 16), font: smallFont, color: Paper.accentPressed)
            }
        }
    }

    private func drawHint(_ string: String) {
        let width: CGFloat = 520
        let rect = NSRect(x: (sceneW - width) / 2, y: sceneH - 50 - (trayVisible ? Self.trayHeight : 0), width: width, height: 34)
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

    // MARK: - Disegno della cassetta

    private func drawTray() {
        let band = trayRect
        Paper.paper.withAlphaComponent(0.95).setFill()
        band.fill()
        Paper.paperEdge.setStroke()
        let edge = NSBezierPath()
        edge.move(to: NSPoint(x: 0, y: band.minY + 0.75))
        edge.line(to: NSPoint(x: band.maxX, y: band.minY + 0.75))
        edge.lineWidth = 1.5
        edge.stroke()
        text("Da mettere", in: NSRect(x: 18, y: band.minY + 14, width: 100, height: 26), font: Paper.markerFont(19))
        let items = trayItems()
        text(items.isEmpty ? "niente per ora" : "trascina nel prato", in: NSRect(x: 18, y: band.minY + 42, width: 100, height: 28),
             font: NSFont.systemFont(ofSize: 11), color: Paper.inkLight)
        let layout = trayLayout()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: layout.area).addClip()
        for cell in layout.cells where cell.rect.maxX > layout.area.minX && cell.rect.minX < layout.area.maxX {
            drawTrayCell(cell.item, count: cell.count, in: cell.rect)
        }
        NSGraphicsContext.restoreGraphicsState()
        // trascinando una copia del prato sulla cassetta: la si toglie (torna qui)
        if case .placed? = carry, carryMoved, band.contains(carryPointer) {
            Paper.accent.withAlphaComponent(0.16).setFill()
            band.fill()
            text("Rilascia per toglierla", in: NSRect(x: band.minX, y: band.midY - 14, width: band.width, height: 28),
                 font: Paper.markerFont(22), color: Paper.accentPressed, alignment: .center)
        }
    }

    private func drawTrayPill() {
        let rect = trayPillRect
        let count = trayItems().reduce(0) { $0 + $1.count }
        drawChip(rect, fill: NSColor(calibratedRed: 1, green: 0.99, blue: 0.94, alpha: 0.96), stroke: Paper.paperEdge)
        if let tray = tinted("tray.and.arrow.down", size: 13, color: Paper.accentPressed) {
            tray.draw(in: NSRect(x: rect.minX + 12, y: rect.midY - tray.size.height / 2, width: tray.size.width, height: tray.size.height))
        }
        text("Da mettere · \(count)", in: NSRect(x: rect.minX + 34, y: rect.minY + 8, width: rect.width - 42, height: 16), font: smallFont)
    }

    private func drawTrayCell(_ item: GardenItem, count: Int, in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        Sticker.card.setFill()
        path.fill()
        Sticker.color(for: item.rarity).setStroke()
        path.lineWidth = item.rarity == .common ? 1.2 : item.rarity == .rare ? 2 : 2.6
        path.stroke()
        if let sprite = GardenSprites.sprite(item.resource) {
            let box = NSRect(x: rect.minX + 6, y: rect.minY + 5, width: rect.width - 12, height: rect.height - 25)
            let scale = min(box.width / sprite.source.width, box.height / sprite.source.height)
            let size = NSSize(width: sprite.source.width * scale, height: sprite.source.height * scale)
            let target = NSRect(x: box.midX - size.width / 2, y: box.maxY - size.height, width: size.width, height: size.height)
            sprite.image.draw(in: target, from: sprite.source, operation: .sourceOver, fraction: 1, respectFlipped: true,
                              hints: [.interpolation: NSImageInterpolation.high])
        }
        var font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        if (item.name as NSString).size(withAttributes: [.font: font]).width > rect.width - 8 { font = NSFont.systemFont(ofSize: 8.5, weight: .semibold) }
        text(item.name, in: NSRect(x: rect.minX + 2, y: rect.maxY - 17, width: rect.width - 4, height: 13), font: font, alignment: .center)
        if count > 1 {
            let label = "×\(count)"
            let badgeFont = NSFont.systemFont(ofSize: 9.5, weight: .bold)
            let width = ceil((label as NSString).size(withAttributes: [.font: badgeFont]).width) + 10
            let badge = NSRect(x: rect.maxX - width - 3, y: rect.minY + 3, width: width, height: 15)
            Paper.accent.setFill()
            NSBezierPath(roundedRect: badge, xRadius: 7.5, yRadius: 7.5).fill()
            text(label, in: NSRect(x: badge.minX, y: badge.minY + 2, width: badge.width, height: 12), font: badgeFont, color: .white, alignment: .center)
        }
    }

    private var carryPointer = NSPoint.zero

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
        if showsTrayPill && trayPillRect.contains(p) {
            trayOpen = true
            needsDisplay = true
            return
        }
        if trayVisible && trayRect.contains(p) {
            trayMouseDown(at: p)
            return
        }
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

    private func trayMouseDown(at p: NSPoint) {
        let layout = trayLayout()
        guard layout.area.contains(p), let cell = layout.cells.first(where: { $0.rect.contains(p) }) else {
            trayOpen = false          // un tocco sul resto della fascia la richiude
            needsDisplay = true
            return
        }
        // Si prende una copia: un tocco la mette nel prato, trascinando la si mette dove si lascia.
        carry = .fresh(cell.item.id)
        carryGrab = .zero
        carryFeet = p
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard carry != nil else { return }
        let p = convert(event.locationInWindow, from: nil)
        carryPointer = p
        if !carryMoved, hypot(p.x - carryStart.x, p.y - carryStart.y) > 4 {
            carryMoved = true
            if case .fresh? = carry { trayOpen = false }      // presa una copia, la fascia si toglie di mezzo: il davanti del prato è libero
        }
        if carryMoved {
            NSCursor.closedHand.set()
            carryFeet = NSPoint(x: p.x + carryGrab.width, y: p.y + carryGrab.height)
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let current = carry else { return }
        let p = convert(event.locationInWindow, from: nil)
        let overTray = trayVisible && trayRect.contains(p)
        let landing = spot(for: carryFeet)
        carry = nil
        NSCursor.arrow.set()
        switch current {
        case .placed(let id):
            if carryMoved {
                if overTray { garden.remove(id) } else { garden.move(id, to: landing) }
            }
        case .companion(let petID):
            if carryMoved {
                if !overTray { garden.setCompanionSpot(petID, to: landing) }
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
        guard trayVisible, trayRect.contains(p), maxTrayScroll > 0 else {
            super.scrollWheel(with: event)
            return
        }
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : -event.scrollingDeltaY
        trayScroll = min(max(trayScroll + delta * (event.hasPreciseScrollingDeltas ? 1 : 8), 0), maxTrayScroll)
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
    /// Chiamata dal pulsante «Album»: si apre la finestra dell'album.
    var onShowAlbum: (() -> Void)?

    /// Quanto rimpicciolire il giardino perché ci stia nello schermo (1 = a grandezza piena).
    static func scale(forScreenWidth width: CGFloat) -> CGFloat {
        min(1, max((width - 40) / GardenView.sceneSize.width, 0.5))
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
            // resta anche la proporzione quando la finestra si allarga per l'album).
            if scale < 1 { view.setBoundsSize(GardenView.sceneSize) }
            window.isReleasedWhenClosed = false
            window.backgroundColor = Paper.paper
            window.appearance = NSAppearance(named: .aqua)
            view.onBack = { [weak self, weak window] in
                window?.orderOut(nil)
                self?.onBack?()
            }
            view.onShowAlbum = { [weak self] in self?.onShowAlbum?() }
            window.center()
            self.window = window
            self.view = view
        }
        window?.title = Profile.shared.gardenTitle      // se nel frattempo è cambiato il nome
        // Chi aveva il giardino della versione 1: i punti non spesi diventano figurine, e l'album si apre a mostrarle.
        let gifts = Garden.shared.openPendingGifts()
        view?.reload()
        view?.announceGifts(gifts.count)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
