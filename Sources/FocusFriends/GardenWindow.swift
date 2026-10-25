import AppKit

/// Il giardino: un'isola a tessere, vista di sbieco, che si riempie con le figurine che trovi a fine focus (GardenDrops). L'album delle
/// figurine è un'altra finestra (AlbumWindow); qui, in basso, c'è la cassetta con le copie ancora da mettere: si trascinano sull'isola
/// (le tessere libere si fanno verdi, quelle dove non ci sta diventano rosse), si spostano, si girano con R o dal tasto destro, e per
/// toglierne una la si trascina sulla cassetta. I compagni sbloccati camminano sulle tessere libere, e se li tocchi parlano.
///
/// Le regole di dove ci stanno le cose sono in GardenGrid.swift; qui c'è solo il disegno e il mouse.
final class GardenView: NSView, NSViewToolTipOwner {
    /// La scena: l'isola sta al centro, in alto c'è posto per le cose alte (il lampione, l'altalena).
    static let sceneSize = NSSize(width: 1000, height: 600)
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

    // La cassetta delle copie da mettere: chiusa (una pillola in basso a sinistra, per non coprire il davanti dell'isola) finché non la apri.
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
    /// Se la copia che si trascina è girata (R, o il tasto destro).
    private var carryTurned = false

    // Il fumetto di un compagno toccato.
    private var bubble: (petID: String, text: String)?
    private var bubbleTimer: Timer?

    // I compagni che camminano.
    private struct Walker {
        var from: GardenTile
        var to: GardenTile
        var progress: Double
        var rest: Double
    }
    private var walkers: [String: Walker] = [:]
    private var walkTimer: Timer?
    private var lastWalkTick = Date()
    private var skyTicks = 0
    private var lastSky: SkyState?

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
        // R: gira quello che si sta trascinando
        if event.charactersIgnoringModifiers?.lowercased() == "r", let current = carry, carryMoved {
            switch current {
            case .placed, .fresh:
                carryTurned.toggle()
                needsDisplay = true
                return
            case .companion:
                break
            }
        }
        if carry == nil {
            switch event.charactersIgnoringModifiers {
            case "+", "=": zoom(by: 1.3); return
            case "-": zoom(by: 1 / 1.3); return
            case "0": resetCamera(); return
            default: break
            }
        }
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

    /// L'isola vista di sbieco: ogni tessera è un rombo largo `tileW` e alto la metà.
    struct Iso {
        let size: Int
        let tileW: CGFloat
        /// Il vertice in alto (in fondo) dell'isola.
        let origin: NSPoint

        static let thickness: CGFloat = 16
        /// Dove cominciano l'isola (c'è posto sopra per le cose alte) e quanto resta sotto.
        static let top: CGFloat = 140
        static let bottomMargin: CGFloat = 44

        /// `zoom` e `pan`: la vista (1 e zero = tutta l'isola, a misura della finestra). Lo zoom è attorno al centro della scena.
        init(size: Int, scene: NSSize, zoom: CGFloat = 1, pan: NSPoint = .zero) {
            self.size = size
            let availableHeight = scene.height - Self.top - Self.bottomMargin - Self.thickness
            let fit = min((scene.width - 60) / CGFloat(size), 2 * availableHeight / CGFloat(size))
            tileW = fit * zoom
            let center = NSPoint(x: scene.width / 2, y: scene.height / 2)
            origin = NSPoint(x: center.x + (scene.width / 2 - center.x) * zoom + pan.x, y: center.y + (Self.top - center.y) * zoom + pan.y)
        }

        var tileH: CGFloat { tileW / 2 }
        /// Quanto si disegna grande un oggetto: l'altezza del catalogo ÷ 135 per la larghezza di una tessera.
        var scale: CGFloat { tileW / 135 }

        /// L'angolo della griglia (`col`, `row` interi sono gli angoli delle tessere).
        func point(col: Double, row: Double) -> NSPoint {
            NSPoint(x: origin.x + CGFloat(col - row) * tileW / 2, y: origin.y + CGFloat(col + row) * tileH / 2)
        }

        func center(of tile: GardenTile) -> NSPoint { point(col: Double(tile.col) + 0.5, row: Double(tile.row) + 0.5) }

        /// La griglia sotto un punto dello schermo (frazioni di tessera).
        func grid(at p: NSPoint) -> (col: Double, row: Double) {
            let a = Double((p.x - origin.x) / (tileW / 2)), b = Double((p.y - origin.y) / (tileH / 2))
            return ((a + b) / 2, (b - a) / 2)
        }
    }

    private var iso: Iso { Iso(size: garden.islandSize, scene: Self.sceneSize, zoom: zoom, pan: pan) }

    // MARK: - La vista: zoom e spostamenti

    static let zoomRange: ClosedRange<CGFloat> = 0.6...2.5
    /// Quanto è ingrandita la vista (1 = tutta l'isola) e di quanto è spostata.
    private(set) var zoom: CGFloat = 1
    private(set) var pan = NSPoint.zero
    private var panning = false
    private var panLast = NSPoint.zero

    /// Ingrandisce o rimpicciolisce di `factor` attorno a un punto della scena (quello sotto il mouse resta dov'è).
    func zoom(by factor: CGFloat, at point: NSPoint? = nil) {
        let target = min(max(zoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        guard target != zoom else { return }
        let center = NSPoint(x: sceneW / 2, y: sceneH / 2)
        let at = point ?? center
        let ratio = target / zoom
        pan = NSPoint(x: at.x - center.x - (at.x - center.x - pan.x) * ratio, y: at.y - center.y - (at.y - center.y - pan.y) * ratio)
        zoom = target
        clampCamera()
        needsDisplay = true
    }

    /// Tutta l'isola, a misura della finestra.
    func resetCamera() {
        zoom = 1
        pan = .zero
        needsDisplay = true
    }

    private func movePan(by delta: NSPoint) {
        pan = NSPoint(x: pan.x + delta.x, y: pan.y + delta.y)
        clampCamera()
        needsDisplay = true
    }

    /// Il centro della finestra resta sempre su un punto dell'isola (o a una tessera dal bordo): non si può perderla di vista.
    private func clampCamera() {
        let i = iso
        let n = Double(i.size)
        let center = NSPoint(x: sceneW / 2, y: sceneH / 2)
        let g = i.grid(at: center)
        let col = min(max(g.col, -1), n + 1), row = min(max(g.row, -1), n + 1)
        guard col != g.col || row != g.row else { return }
        let inside = i.point(col: col, row: row)
        pan = NSPoint(x: pan.x + center.x - inside.x, y: pan.y + center.y - inside.y)
    }

    private var zoomControlsRect: NSRect {
        NSRect(x: sceneW - 16 - 114, y: sceneH - 50 - (trayVisible ? Self.trayHeight : 0), width: 114, height: 34)
    }

    private func zoomButtonRects() -> [(symbol: String, rect: NSRect, action: () -> Void)] {
        let box = zoomControlsRect
        let width = box.width / 3
        return [
            ("minus", NSRect(x: box.minX, y: box.minY, width: width, height: box.height), { [weak self] in self?.zoom(by: 1 / 1.3) }),
            ("arrow.up.left.and.arrow.down.right", NSRect(x: box.minX + width, y: box.minY, width: width, height: box.height), { [weak self] in self?.resetCamera() }),
            ("plus", NSRect(x: box.minX + 2 * width, y: box.minY, width: width, height: box.height), { [weak self] in self?.zoom(by: 1.3) }),
        ]
    }

    private func drawZoomControls() {
        let box = zoomControlsRect
        drawChip(box, fill: NSColor(calibratedRed: 1, green: 0.99, blue: 0.94, alpha: 0.95), stroke: Paper.paperEdge)
        for (index, button) in zoomButtonRects().enumerated() {
            if index > 0 {
                Paper.paperEdge.withAlphaComponent(0.5).setStroke()
                let divider = NSBezierPath()
                divider.move(to: NSPoint(x: button.rect.minX, y: button.rect.minY + 8))
                divider.line(to: NSPoint(x: button.rect.minX, y: button.rect.maxY - 8))
                divider.lineWidth = 1
                divider.stroke()
            }
            let enabled = button.symbol == "minus" ? zoom > Self.zoomRange.lowerBound + 0.001
                : button.symbol == "plus" ? zoom < Self.zoomRange.upperBound - 0.001 : (zoom != 1 || pan != .zero)
            if let icon = tinted(button.symbol, size: 13, color: enabled ? Paper.ink : Paper.inkLight.withAlphaComponent(0.4)) {
                icon.draw(in: NSRect(x: button.rect.midX - icon.size.width / 2, y: button.rect.midY - icon.size.height / 2, width: icon.size.width, height: icon.size.height))
            }
        }
    }

    /// I piedi di un oggetto stanno un po' sotto il centro della sua tessera.
    private static let feetOffset: CGFloat = 0.22

    // MARK: - Cosa c'è sull'isola

    private enum Kind: Equatable {
        case placed(UUID)
        case companion(String)
    }

    /// Una cosa sull'isola, con dove cade a schermo.
    private struct Entity {
        var kind: Kind
        var sprite: GardenSprite
        var feet: NSPoint
        var rect: NSRect
        var shadow: NSRect?
        var turned: Bool
        /// Chi ha il numero più alto sta davanti.
        var depth: Double
        /// Quanto ondeggia col vento (0 = fermo), da dove parte l'onda, e dov'è l'acqua nel disegno, se c'è.
        var sway = 0.0
        var seed = 0.0
        var tile = GardenTile(col: 0, row: 0)
        var water: (u: Double, v: Double, halfWidth: Double, halfHeight: Double)?
    }

    private func entity(kind: Kind, resource: String, referenceHeight: Double, feet: NSPoint, shadowWidth: CGFloat?, turned: Bool,
                        depth: Double, iso: Iso) -> Entity? {
        guard let sprite = GardenSprites.sprite(resource) else { return nil }
        let height = CGFloat(referenceHeight) * iso.scale
        let width = height * sprite.aspect
        let rect = NSRect(x: feet.x - width / 2, y: feet.y - height, width: width, height: height)
        var shadow: NSRect?
        if let shadowWidth {
            let shadowHeight = max(shadowWidth * 0.34, 5)
            shadow = NSRect(x: feet.x - shadowWidth / 2, y: feet.y - shadowHeight * 0.55, width: shadowWidth, height: shadowHeight)
        }
        return Entity(kind: kind, sprite: sprite, feet: feet, rect: rect, shadow: shadow, turned: turned, depth: depth)
    }

    /// Dove sta un compagno in questo momento (cammina da una tessera all'altra).
    private func companionGround(_ petID: String, home: GardenTile, iso: Iso) -> (point: NSPoint, depth: Double) {
        let walker = walkers[petID] ?? Walker(from: home, to: home, progress: 1, rest: 2)
        let from = iso.center(of: walker.from), to = iso.center(of: walker.to)
        let t = CGFloat(walker.progress * walker.progress * (3 - 2 * walker.progress))
        let hop = CGFloat(sin(walker.progress * .pi)) * iso.tileH * (walker.progress < 1 ? 0.18 : 0)
        let point = NSPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t - hop)
        let cols = Double(walker.from.col) + (Double(walker.to.col) - Double(walker.from.col)) * Double(t)
        let rows = Double(walker.from.row) + (Double(walker.to.row) - Double(walker.from.row)) * Double(t)
        return (point, cols + rows + 1)
    }

    /// Gli oggetti e i compagni sbloccati, dal fondo al davanti. Quello che si sta trascinando non c'è: si disegna a parte (`drawGhost`).
    private func entities() -> [Entity] {
        let iso = self.iso
        var result: [Entity] = []
        for placement in garden.placements {
            guard let item = GardenCatalog.item(withID: placement.item) else { continue }
            if carryMoved, carry == .placed(placement.id) { continue }
            let footprint = item.footprint.applying(turned: placement.turned)
            let ground = iso.point(col: Double(placement.col) + Double(footprint.cols) / 2, row: Double(placement.row) + Double(footprint.rows) / 2)
            let feet = NSPoint(x: ground.x, y: ground.y + iso.tileH * Self.feetOffset)
            let front = Double(placement.col + footprint.cols - 1 + placement.row + footprint.rows - 1)
            let shadowWidth = item.castsShadow ? min(iso.tileW * 0.62 * CGFloat(max(footprint.cols, footprint.rows)), iso.tileW * 1.3) : nil
            guard var made = entity(kind: .placed(placement.id), resource: item.resource, referenceHeight: item.height, feet: feet,
                                    shadowWidth: shadowWidth, turned: placement.turned, depth: front + 0.5, iso: iso) else { continue }
            made.sway = item.swayStrength
            made.seed = Double(GardenDrops.hash(placement.id.uuidString) % 1000) / 1000
            made.tile = placement.tile
            made.water = item.waterSpot
            result.append(made)
        }
        for (index, pet) in Pet.all.enumerated() where profile.isCompanionUnlocked(pet.id) {
            if carryMoved, carry == .companion(pet.id) { continue }
            let home = garden.companionTile(pet.id, index: index)
            let ground = companionGround(pet.id, home: home, iso: iso)
            let feet = NSPoint(x: ground.point.x, y: ground.point.y + iso.tileH * Self.feetOffset)
            guard let made = entity(kind: .companion(pet.id), resource: pet.iconResource, referenceHeight: GardenCatalog.companionHeight(for: pet.id),
                                    feet: feet, shadowWidth: iso.tileW * 0.5, turned: false, depth: ground.depth, iso: iso) else { continue }
            result.append(made)
        }
        result.sort { $0.depth < $1.depth }
        return result
    }

    /// La cosa più davanti sotto il mouse, contando solo dove l'immagine è disegnata (con una cella di margine):
    /// così si può toccare un compagno che sta dietro le bandierine o sotto l'arco.
    private func entity(at point: NSPoint) -> Entity? {
        for entity in entities().reversed() where entity.rect.contains(point) {
            var u = (point.x - entity.rect.minX) / entity.rect.width
            let v = (point.y - entity.rect.minY) / entity.rect.height
            if entity.turned { u = 1 - u }
            if entity.sprite.isDrawn(u: u, v: v) { return entity }
        }
        return nil
    }

    // MARK: - I compagni camminano

    /// Fa fare un passo ai compagni (`dt` secondi): ogni tanto uno si sposta su una tessera libera accanto. Ritorna true se qualcuno si muove.
    @discardableResult
    func advanceWalkers(by dt: TimeInterval) -> Bool {
        if reduceMotion { return false }
        let size = garden.islandSize
        let occupied = garden.occupiedTiles()
        var moving = false
        let pets = Pet.all.enumerated().filter { profile.isCompanionUnlocked($0.element.id) }
        for (index, pet) in pets {
            if carry == .companion(pet.id) { continue }
            let home = garden.companionTile(pet.id, index: index)
            var walker = walkers[pet.id] ?? Walker(from: home, to: home, progress: 1, rest: 1 + Double.random(in: 0...3))
            if !GardenLayout.isWalkable(walker.from, size: size, occupied: occupied) || !GardenLayout.isWalkable(walker.to, size: size, occupied: occupied) {
                // Gli hanno messo un oggetto sotto i piedi (o l'isola è cambiata): torna a casa.
                walker = Walker(from: home, to: home, progress: 1, rest: 1)
            }
            if walker.progress < 1 {
                walker.progress = min(1, walker.progress + dt / 1.3)
                moving = true
            } else {
                walker.from = walker.to
                walker.rest -= dt
                if walker.rest <= 0 {
                    let taken = Set(walkers.filter { $0.key != pet.id }.flatMap { [$0.value.from, $0.value.to] })
                    let around = [(1, 0), (-1, 0), (0, 1), (0, -1)].map { GardenTile(col: walker.from.col + $0.0, row: walker.from.row + $0.1) }
                    let free = around.filter { GardenLayout.isWalkable($0, size: size, occupied: occupied) && !taken.contains($0) }
                    if let next = free.randomElement() {
                        walker.to = next
                        walker.progress = 0
                        moving = true
                    }
                    walker.rest = 1.5 + Double.random(in: 0...3.5)
                }
            }
            walkers[pet.id] = walker
        }
        return moving
    }

    private func startWalking() {
        walkTimer?.invalidate()
        lastWalkTick = Date()
        let timer = Timer(timeInterval: 1.0 / 24, repeats: true) { [weak self] _ in
            guard let self, let window = self.window, window.isVisible, window.occlusionState.contains(.visible) else { return }
            let elapsed = min(Date().timeIntervalSince(self.lastWalkTick), 0.2)
            self.lastWalkTick = Date()
            let walking = self.advanceWalkers(by: elapsed)
            // di tanto in tanto si guarda se la luce è cambiata (sta calando la sera): altrimenti si ridisegna solo se qualcosa si muove
            self.skyTicks += 1
            var changed = false
            if self.skyTicks % 30 == 0 {
                let light = self.skyState()
                if light != self.lastSky { changed = true }
                self.lastSky = light
            }
            if walking || changed || self.skyIsAnimated() { self.needsDisplay = true }
        }
        RunLoop.main.add(timer, forMode: .common)
        walkTimer = timer
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            walkTimer?.invalidate()
            walkTimer = nil
        } else {
            startWalking()
        }
    }

    /// Dove cadrebbe la cosa che si sta trascinando, e se ci sta.
    private struct CarryTarget {
        var origin: GardenTile
        var tiles: [GardenTile]
        var valid: Bool
    }

    private func carryTarget() -> CarryTarget? {
        guard let current = carry, carryMoved else { return nil }
        let iso = self.iso
        let ground = NSPoint(x: carryFeet.x, y: carryFeet.y - iso.tileH * Self.feetOffset)
        let g = iso.grid(at: ground)
        switch current {
        case .companion(let petID):
            let tile = GardenTile(col: Int(g.col.rounded(.down)), row: Int(g.row.rounded(.down)))
            let others = Pet.all.enumerated().filter { $0.element.id != petID && profile.isCompanionUnlocked($0.element.id) }
                .map { garden.companionTile($0.element.id, index: $0.offset) }
            let valid = GardenLayout.isWalkable(tile, size: iso.size, occupied: garden.occupiedTiles()) && !others.contains(tile)
            return CarryTarget(origin: tile, tiles: [tile], valid: valid)
        case .placed(let id):
            guard let placement = garden.placements.first(where: { $0.id == id }), let item = GardenCatalog.item(withID: placement.item) else { return nil }
            return itemTarget(item, grid: g, ignoring: id, needsCopy: false)
        case .fresh(let id):
            guard let item = GardenCatalog.item(withID: id) else { return nil }
            return itemTarget(item, grid: g, ignoring: nil, needsCopy: true)
        }
    }

    private func itemTarget(_ item: GardenItem, grid g: (col: Double, row: Double), ignoring: UUID?, needsCopy: Bool) -> CarryTarget {
        let footprint = item.footprint.applying(turned: carryTurned)
        let origin = GardenTile(col: Int((g.col - Double(footprint.cols) / 2).rounded()), row: Int((g.row - Double(footprint.rows) / 2).rounded()))
        var valid = garden.canPlace(item.id, at: origin, turned: carryTurned, ignoring: ignoring)
        if needsCopy && !(garden.available(item.id) > 0 || Profile.isDeveloper) { valid = false }
        return CarryTarget(origin: origin, tiles: GardenLayout.tiles(of: footprint, at: origin), valid: valid)
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

    /// La fascia si vede solo aperta (toglierne una dall'isola è un'altra cosa: `removeZoneRect`).
    private var trayVisible: Bool { trayOpen && !trayItems().isEmpty }

    /// Trascinando una copia dell'isola, in basso a sinistra compare dove lasciarla per toglierla (fuori dall'isola, che sta più in alto).
    private var removeZoneRect: NSRect { NSRect(x: 16, y: sceneH - 64, width: 236, height: 46) }

    private var isCarryingPlaced: Bool {
        if case .placed? = carry, carryMoved { return true }
        return false
    }

    /// La pillola «Da mettere · 7», quando la cassetta è chiusa e c'è qualcosa dentro.
    private var trayPillRect: NSRect { NSRect(x: 16, y: sceneH - 46, width: 156, height: 30) }

    private var showsTrayPill: Bool { !trayVisible && !trayItems().isEmpty && !(carry != nil && carryMoved) }

    private func drawRemoveZone() {
        let rect = removeZoneRect
        let hovering = rect.contains(carryPointer)
        let path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
        (hovering ? Paper.accent.withAlphaComponent(0.30) : Paper.paper.withAlphaComponent(0.92)).setFill()
        path.fill()
        Paper.accent.setStroke()
        path.lineWidth = hovering ? 2.4 : 1.4
        path.setLineDash([6, 4], count: 2, phase: 0)
        path.stroke()
        text("Rilascia qui per toglierla", in: NSRect(x: rect.minX, y: rect.minY + 12, width: rect.width, height: 22),
             font: Paper.markerFont(18), color: Paper.accentPressed, alignment: .center)
    }

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
        let sky = skyState()
        MeadowBackdrop.draw(in: sceneRect, blur: 5, veil: palette(sky.season).veil)
        let iso = self.iso
        let target = carryTarget()
        drawChimneySmoke(season: sky.season)
        drawIslandGround(iso, season: sky.season)
        drawHighlight(target, iso: iso)
        let laid = entities()
        for entity in laid {
            drawEntity(entity)
            if let spot = entity.water { drawWater(entity, spot: spot, light: sky.light) }
        }
        drawGhost(target, iso: iso)
        drawWeather(sky.season)
        applyLight(sky.light)
        drawLampGlows(laid, iso: iso, light: sky.light)
        drawCottageWindows(light: sky.light, iso: iso)
        drawFireflies(season: sky.season, light: sky.light)
        if let bubble, let owner = laid.first(where: { $0.kind == .companion(bubble.petID) }) {
            drawBubble(bubble.text, above: owner.rect)
        }
        drawHUD()
        if trayVisible { drawTray() } else if showsTrayPill { drawTrayPill() }
        drawZoomControls()
        if isCarryingPlaced { drawRemoveZone() }
        if let message {
            drawHint(message)
        } else if garden.placements.isEmpty && carry == nil {
            drawHint("Trova le figurine a fine focus: si mettono qui da sole.")
        }
    }

    // MARK: - Il cielo e le stagioni

    private struct SkyState: Equatable {
        var season: Season
        var light: GardenLight
    }

    /// Che stagione e che luce c'è adesso. Per provarle senza aspettare: `defaults write com.jacopo.focusfriends gardenHour -float 21`
    /// (l'ora, con la virgola) e `gardenSeason -string winter` (spring, summer, autumn, winter); `defaults delete …` le toglie.
    private func skyState() -> SkyState {
        let defaults = UserDefaults.standard
        let date = now()
        var hour = GardenSky.hour(of: date, calendar: calendar)
        var season = Season.of(date, calendar: calendar)
        if defaults.object(forKey: "gardenHour") != nil { hour = defaults.double(forKey: "gardenHour") }
        if let raw = defaults.string(forKey: "gardenSeason"), let forced = Season(rawValue: raw) { season = forced }
        return SkyState(season: season, light: GardenSky.light(hour: hour, season: season))
    }

    /// I colori dell'isola in una stagione, e il velo sullo sfondo.
    private struct Palette {
        var grassA: (CGFloat, CGFloat, CGFloat)
        var grassB: (CGFloat, CGFloat, CGFloat)
        var pathA: (CGFloat, CGFloat, CGFloat)
        var pathB: (CGFloat, CGFloat, CGFloat)
        var tuft: NSColor
        var veil: NSColor
    }

    private func palette(_ season: Season) -> Palette {
        switch season {
        case .spring:
            return Palette(grassA: (160, 204, 120), grassB: (152, 197, 112), pathA: (226, 208, 170), pathB: (218, 199, 160),
                           tuft: Self.color(104, 156, 80), veil: Self.color(255, 232, 238, 0.14))
        case .summer:
            return Palette(grassA: (146, 195, 100), grassB: (138, 187, 92), pathA: (230, 208, 160), pathB: (222, 199, 150),
                           tuft: Self.color(96, 150, 68), veil: Self.color(255, 244, 200, 0.12))
        case .autumn:
            return Palette(grassA: (184, 178, 100), grassB: (174, 168, 92), pathA: (216, 194, 152), pathB: (208, 185, 142),
                           tuft: Self.color(150, 112, 56), veil: Self.color(255, 190, 110, 0.24))
        case .winter:
            return Palette(grassA: (232, 240, 244), grassB: (222, 233, 240), pathA: (205, 212, 224), pathB: (197, 205, 218),
                           tuft: Self.color(132, 164, 186), veil: Self.color(225, 238, 255, 0.34))
        }
    }

    /// L'ora del cielo e degli effetti, in secondi (un banco di prova la può fissare).
    var effectsClock: () -> Double = { CACurrentMediaTime() }

    /// Petali, foglie o neve che cadono, a seconda della stagione.
    private func drawWeather(_ season: Season) {
        guard let kind = GardenSky.particleKind(season), !reduceMotion else { return }
        let time = effectsClock()
        let leafColors = [Self.color(214, 120, 50), Self.color(190, 84, 44), Self.color(226, 168, 60), Self.color(150, 104, 52)]
        for index in 0..<GardenSky.particleCount(kind) {
            let p = GardenSky.particle(kind: kind, index: index, time: time, width: Double(sceneW), height: Double(sceneH))
            let size = CGFloat(p.size)
            let color: NSColor
            switch kind {
            case .petal: color = p.tone < 0.5 ? Self.color(255, 196, 214, p.alpha) : Self.color(255, 238, 242, p.alpha)
            case .leaf: color = leafColors[min(Int(p.tone * Double(leafColors.count)), leafColors.count - 1)].withAlphaComponent(CGFloat(p.alpha))
            case .snow: color = NSColor.white.withAlphaComponent(CGFloat(p.alpha) * 0.9)
            }
            color.setFill()
            if kind == .snow {
                NSBezierPath(ovalIn: NSRect(x: CGFloat(p.x) - size / 2, y: CGFloat(p.y) - size / 2, width: size, height: size)).fill()
                continue
            }
            NSGraphicsContext.saveGraphicsState()
            let turn = NSAffineTransform()
            turn.translateX(by: CGFloat(p.x), yBy: CGFloat(p.y))
            turn.rotate(byRadians: CGFloat(p.angle))
            turn.concat()
            let width = kind == .leaf ? size * 1.7 : size * 1.5, height = kind == .leaf ? size * 0.85 : size
            NSBezierPath(ovalIn: NSRect(x: -width / 2, y: -height / 2, width: width, height: height)).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// La luce del momento: la scena si moltiplica per un colore (bianco di giorno, azzurro scuro di notte) e di sera i bordi si scuriscono.
    private func applyLight(_ light: GardenLight) {
        guard light.tintStrength > 0.001 else { return }
        let m = light.multiplier
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setBlendMode(.multiply)
        NSColor(calibratedRed: CGFloat(m.red / 255), green: CGFloat(m.green / 255), blue: CGFloat(m.blue / 255), alpha: 1).setFill()
        sceneRect.fill(using: .multiply)
        if light.darkness > 0.1 {
            NSGradient(colors: [NSColor(calibratedRed: 0.55, green: 0.58, blue: 0.80, alpha: 0), NSColor(calibratedRed: 0.28, green: 0.30, blue: 0.55, alpha: CGFloat(min(light.darkness * 1.3, 0.7)))])?
                .draw(in: sceneRect, relativeCenterPosition: .zero)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// I lampioni accesi: una luce calda in cima e una pozza sul prato.
    private func drawLampGlows(_ laid: [Entity], iso: Iso, light: GardenLight) {
        let strength = CGFloat(light.lamp)
        guard strength > 0.01 else { return }
        let lamps = Set(garden.placements.filter { $0.item == "lampione" }.map { $0.id })
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setBlendMode(.plusLighter)
        let warm = Self.color(255, 196, 104)
        for entity in laid {
            guard case .placed(let id) = entity.kind, lamps.contains(id) else { continue }
            let top = NSPoint(x: entity.rect.midX, y: entity.rect.minY + entity.rect.height * 0.10)
            NSGradient(colors: [warm.withAlphaComponent(0.48 * strength), warm.withAlphaComponent(0.14 * strength), warm.withAlphaComponent(0)])?
                .draw(fromCenter: top, radius: 0, toCenter: top, radius: iso.tileW * 1.25, options: [])
            // la pozza di luce sul prato, schiacciata come l'isola
            NSGraphicsContext.saveGraphicsState()
            let squash = NSAffineTransform()
            squash.translateX(by: entity.feet.x, yBy: entity.feet.y)
            squash.scaleX(by: 1, yBy: 0.5)
            squash.concat()
            NSGradient(colors: [warm.withAlphaComponent(0.34 * strength), warm.withAlphaComponent(0)])?
                .draw(fromCenter: .zero, radius: 0, toCenter: .zero, radius: iso.tileW * 1.5, options: [])
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Le lucciole: di sera, soprattutto d'estate.
    private func drawFireflies(season: Season, light: GardenLight) {
        let amount = CGFloat(GardenSky.fireflyAmount(season: season, light: light))
        guard amount > 0.01, !reduceMotion else { return }
        let time = effectsClock()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setBlendMode(.plusLighter)
        let glowColor = Self.color(255, 238, 140), core = Self.color(255, 252, 210)
        for index in 0..<GardenSky.fireflyCount {
            let f = GardenSky.firefly(index: index, time: time, width: Double(sceneW), height: Double(sceneH))
            let a = CGFloat(f.glow) * amount
            guard a > 0.02 else { continue }
            let c = NSPoint(x: CGFloat(f.x), y: CGFloat(f.y))
            NSGradient(colors: [glowColor.withAlphaComponent(0.85 * a), glowColor.withAlphaComponent(0)])?
                .draw(fromCenter: c, radius: 0, toCenter: c, radius: 10, options: [])
            core.withAlphaComponent(min(1, a * 1.3)).setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - 1.4, y: c.y - 1.4, width: 2.8, height: 2.8)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// C'è qualcosa che si muove (le piante nel vento, il fumo, l'acqua, e quello che cade o vola) e quindi si ridisegna di continuo?
    /// Con «Riduci movimento» no.
    private func skyIsAnimated() -> Bool { !reduceMotion }

    // MARK: - La vita ferma: piante nel vento, acqua che luccica, fumo dal camino

    /// Chi ha chiesto «Riduci movimento» nelle impostazioni di accessibilità: niente vento, fumo, neve, lucciole né passeggiate.
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Disegna una pianta piegata dal vento: a strisce orizzontali, ognuna spostata di lato un po' di più della sottostante, così la base
    /// sta ferma e la cima oscilla.
    private func drawSwaying(_ entity: Entity, rect: NSRect, alpha: CGFloat) {
        let iso = self.iso
        let time = effectsClock()
        let wind = GardenSky.wind(skyState().season)
        let amplitude = CGFloat(entity.sway * wind) * 2.6 * iso.tileW / 94
        let strips = 14
        let source = entity.sprite.source
        for index in 0..<strips {
            let top = CGFloat(index) / CGFloat(strips), bottom = CGFloat(index + 1) / CGFloat(strips)
            let height = 1 - Double(top + bottom) / 2
            let dx = CGFloat(GardenSky.sway(time: time, col: entity.tile.col, row: entity.tile.row, seed: entity.seed, height: height)) * amplitude
            let overlap: CGFloat = index == strips - 1 ? 0 : 0.8
            let target = NSRect(x: rect.minX + dx, y: rect.minY + top * rect.height, width: rect.width, height: (bottom - top) * rect.height + overlap)
            let overlapInSource = overlap / rect.height * source.height
            let piece = NSRect(x: source.minX, y: source.minY + (1 - bottom) * source.height - overlapInSource, width: source.width,
                               height: (bottom - top) * source.height + overlapInSource)
            entity.sprite.image.draw(in: target, from: piece, operation: .sourceOver, fraction: alpha, respectFlipped: true,
                                     hints: [.interpolation: NSImageInterpolation.high])
        }
    }

    /// I luccichii e il cerchio d'acqua sulla vaschetta del bagnetto.
    private func drawWater(_ entity: Entity, spot: (u: Double, v: Double, halfWidth: Double, halfHeight: Double), light: GardenLight) {
        let rect = entity.rect
        let center = NSPoint(x: rect.minX + CGFloat(spot.u) * rect.width, y: rect.minY + CGFloat(spot.v) * rect.height)
        let halfW = CGFloat(spot.halfWidth) * rect.width, halfH = CGFloat(spot.halfHeight) * rect.height
        let time = reduceMotion ? 0 : effectsClock()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: NSRect(x: center.x - halfW, y: center.y - halfH, width: halfW * 2, height: halfH * 2)).addClip()
        // il cerchio di una goccia
        let ripple = GardenSky.ripple(time: time, seed: Double(entity.tile.col * 7 + entity.tile.row * 3) / 31)
        if !reduceMotion, ripple.alpha > 0.01 {
            let r = CGFloat(ripple.phase)
            let ring = NSBezierPath(ovalIn: NSRect(x: center.x + CGFloat(ripple.x) * halfW - r * halfW * 0.5, y: center.y + CGFloat(ripple.y) * halfH - r * halfH * 0.5,
                                                   width: r * halfW, height: r * halfH))
            NSColor.white.withAlphaComponent(CGFloat(ripple.alpha)).setStroke()
            ring.lineWidth = 1
            ring.stroke()
        }
        // i luccichii (di notte più piano)
        NSGraphicsContext.current?.cgContext.setBlendMode(.plusLighter)
        let strength: CGFloat = 1 - CGFloat(light.darkness) * 0.8
        for index in 0..<GardenSky.sparkleCount {
            let s = GardenSky.sparkle(index: index, time: time)
            let a = CGFloat(s.glow) * strength
            guard a > 0.03 else { continue }
            let c = NSPoint(x: center.x + CGFloat(s.x) * halfW, y: center.y + CGFloat(s.y) * halfH)
            NSGradient(colors: [NSColor.white.withAlphaComponent(0.8 * a), NSColor.white.withAlphaComponent(0)])?
                .draw(fromCenter: c, radius: 0, toCenter: c, radius: 4.5, options: [])
            NSColor.white.withAlphaComponent(min(1, a * 1.2)).setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - 1, y: c.y - 1, width: 2, height: 2)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Il fumo che esce dal camino del casale (sullo sfondo, dietro l'isola): sbuffi chiari che salgono e si piegano col vento.
    private func drawChimneySmoke(season: Season) {
        let amount = GardenSky.smokeAmount(season)
        guard amount > 0.01, let mouth = MeadowBackdrop.scenePoint(u: MeadowBackdrop.chimney.u, v: MeadowBackdrop.chimney.v, in: Self.sceneSize) else { return }
        let time = reduceMotion ? 3 : effectsClock()
        let wind = GardenSky.wind(season)
        let color = Self.color(226, 222, 224)
        for index in 0..<GardenSky.smokeCount {
            let puff = GardenSky.smoke(index: index, time: time, wind: wind)
            let a = min(CGFloat(puff.alpha * amount) * 1.5, 0.8)
            guard a > 0.01 else { continue }
            let c = NSPoint(x: mouth.x + CGFloat(puff.dx), y: mouth.y + CGFloat(puff.dy))
            NSGradient(colors: [color.withAlphaComponent(a), color.withAlphaComponent(a * 0.55), color.withAlphaComponent(0)])?
                .draw(fromCenter: c, radius: 0, toCenter: c, radius: CGFloat(puff.radius) * 1.7, options: [])
        }
    }

    /// Di sera le finestre del casale si accendono (non sopra l'isola, che sta davanti).
    private func drawCottageWindows(light: GardenLight, iso: Iso) {
        let strength = CGFloat(light.lamp)
        guard strength > 0.02 else { return }
        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(rect: sceneRect.insetBy(dx: -20, dy: -20))
        clip.append(islandOutline(iso))
        clip.windingRule = .evenOdd
        clip.addClip()
        NSGraphicsContext.current?.cgContext.setBlendMode(.plusLighter)
        let warm = Self.color(255, 208, 120)
        for window in MeadowBackdrop.windows {
            guard let c = MeadowBackdrop.scenePoint(u: window.u, v: window.v, in: Self.sceneSize) else { continue }
            NSGradient(colors: [warm.withAlphaComponent(0.8 * strength), warm.withAlphaComponent(0.25 * strength), warm.withAlphaComponent(0)])?
                .draw(fromCenter: c, radius: 0, toCenter: c, radius: 20, options: [])
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Il contorno dell'isola con i suoi lati di terra.
    private func islandOutline(_ iso: Iso) -> NSBezierPath {
        let n = Double(iso.size)
        let top = iso.point(col: 0, row: 0), right = iso.point(col: n, row: 0), front = iso.point(col: n, row: n), left = iso.point(col: 0, row: n)
        let t = Iso.thickness
        let path = NSBezierPath()
        path.move(to: top)
        path.line(to: right)
        path.line(to: NSPoint(x: right.x, y: right.y + t))
        path.line(to: NSPoint(x: front.x, y: front.y + t))
        path.line(to: NSPoint(x: left.x, y: left.y + t))
        path.line(to: left)
        path.close()
        return path
    }

    // MARK: - L'isola

    private static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    private func diamond(_ tile: GardenTile, iso: Iso, inset: CGFloat = 0) -> NSBezierPath {
        let top = iso.point(col: Double(tile.col), row: Double(tile.row))
        let right = iso.point(col: Double(tile.col + 1), row: Double(tile.row))
        let bottom = iso.point(col: Double(tile.col + 1), row: Double(tile.row + 1))
        let left = iso.point(col: Double(tile.col), row: Double(tile.row + 1))
        let path = NSBezierPath()
        path.move(to: NSPoint(x: top.x, y: top.y + inset * 0.5))
        path.line(to: NSPoint(x: right.x - inset, y: right.y))
        path.line(to: NSPoint(x: bottom.x, y: bottom.y - inset * 0.5))
        path.line(to: NSPoint(x: left.x + inset, y: left.y))
        path.close()
        return path
    }

    /// Il terreno: i lati di terra, le tessere d'erba e di sentiero, la griglia (più visibile mentre si trascina) e, se si sta
    /// trascinando qualcosa, le tessere dove cadrebbe (verdi se ci sta, rosse se no).
    /// Le dodici tessere d'erba disegnate (rombi 2:1, già pronte da `tools/cutout_tessere.py`); se ne manca una, si disegna l'erba a mano.
    private static var grassImages: [NSImage]? = {
        let images = (1...GardenTerrain.grassCount).compactMap { index in
            Bundle.main.url(forResource: "giardino_tessera_erba_\(index)", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
        }
        return images.count == GardenTerrain.grassCount ? images : nil
    }()

    /// Le otto tessere del sentiero.
    private static var pathImages: [NSImage]? = {
        let images = (1...GardenTerrain.pathCount).compactMap { index in
            Bundle.main.url(forResource: "giardino_tessera_sentiero_\(index)", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
        }
        return images.count == GardenTerrain.pathCount ? images : nil
    }()

    private static var grassGrids: [Int: [Int]] = [:]

    /// Disegna il terreno (ombra, lati, tessere); `carrying`: la griglia si vede di più mentre si trascina.
    private func paintIslandGround(_ iso: Iso, season: Season, carrying: Bool) {
        let pal = palette(season)
        let grassGrid = Self.grassGrids[iso.size] ?? { let grid = GardenTerrain.grassGrid(size: iso.size); Self.grassGrids[iso.size] = grid; return grid }()
        let pathTiles = GardenIsland.pathTiles(size: iso.size)
        let pathIndex = Dictionary(uniqueKeysWithValues: pathTiles.enumerated().map { ($1, $0) })
        let pathVariants = GardenTerrain.pathVariants(count: pathTiles.count)
        let n = Double(iso.size)
        let thickness = Iso.thickness
        // l'ombra sul prato, sotto l'isola
        let front = iso.point(col: n, row: n)
        let shadow = NSRect(x: iso.origin.x - iso.tileW * CGFloat(n) * 0.46, y: front.y - iso.tileH * 0.5, width: iso.tileW * CGFloat(n) * 0.92, height: iso.tileH * 1.6)
        NSColor(calibratedRed: 0.16, green: 0.22, blue: 0.10, alpha: 0.16).setFill()
        NSBezierPath(ovalIn: shadow).fill()
        // i lati
        let left = iso.point(col: 0, row: n), right = iso.point(col: n, row: 0)
        let leftSide = NSBezierPath()
        leftSide.move(to: left); leftSide.line(to: front)
        leftSide.line(to: NSPoint(x: front.x, y: front.y + thickness)); leftSide.line(to: NSPoint(x: left.x, y: left.y + thickness)); leftSide.close()
        Self.color(133, 100, 66).setFill()
        leftSide.fill()
        let rightSide = NSBezierPath()
        rightSide.move(to: right); rightSide.line(to: front)
        rightSide.line(to: NSPoint(x: front.x, y: front.y + thickness)); rightSide.line(to: NSPoint(x: right.x, y: right.y + thickness)); rightSide.close()
        Self.color(108, 78, 50).setFill()
        rightSide.fill()
        // le tessere
        for row in 0..<iso.size {
            for col in 0..<iso.size {
                let tile = GardenTile(col: col, row: row)
                let seed = GardenDrops.hash("\(col),\(row)")
                let variation = CGFloat(Int(seed % 11)) - 5
                let isPath = GardenIsland.isPath(tile)
                let base = isPath ? ((col + row) % 2 == 0 ? pal.pathA : pal.pathB) : ((col + row) % 2 == 0 ? pal.grassA : pal.grassB)
                let path = diamond(tile, iso: iso)
                // l'erba disegnata (d'inverno, finché non c'è la neve disegnata, si usa quella a mano: bianca)
                var grass: NSImage?
                if season != .winter {
                    if isPath, let index = pathIndex[tile] { grass = Self.pathImages?[pathVariants[index]] }
                    else if !isPath { grass = Self.grassImages?[grassGrid[row * iso.size + col]] }
                }
                if let grass {
                    grass.draw(in: path.bounds.insetBy(dx: -0.6, dy: -0.3), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                               hints: [.interpolation: NSImageInterpolation.high])
                    if season == .autumn {
                        NSGraphicsContext.saveGraphicsState()
                        NSGraphicsContext.current?.cgContext.setBlendMode(.multiply)
                        (isPath ? Self.color(244, 220, 178) : Self.color(236, 196, 120)).setFill()
                        path.fill()
                        NSGraphicsContext.restoreGraphicsState()
                    }
                } else {
                    Self.color(base.0 + variation, base.1 + variation, base.2 + variation).setFill()
                    path.fill()
                }
                NSColor.white.withAlphaComponent(carrying ? 0.34 : 0.14).setStroke()
                path.lineWidth = 1
                path.stroke()
                let center = iso.center(of: tile)
                if isPath, grass == nil {
                    // qualche sasso
                    for k in 0..<3 {
                        let h = GardenDrops.hash("sasso\(col),\(row),\(k)")
                        let dx = (CGFloat(h % 41) - 20) * iso.tileW / 140, dy = (CGFloat((h >> 8) % 21) - 10) * iso.tileH / 60
                        Self.color(196, 176, 138, 0.8).setFill()
                        NSBezierPath(ovalIn: NSRect(x: center.x + dx - 4, y: center.y + dy - 2, width: 8, height: 4)).fill()
                    }
                } else if grass == nil, seed % 3 == 0 {
                    // un ciuffo d'erba
                    pal.tuft.setStroke()
                    for k in 0..<3 {
                        let h = GardenDrops.hash("erba\(col),\(row),\(k)")
                        let x = center.x + (CGFloat(h % 45) - 22) * iso.tileW / 140, y = center.y + (CGFloat((h >> 8) % 17) - 8) * iso.tileH / 60
                        let blade = NSBezierPath()
                        blade.move(to: NSPoint(x: x, y: y)); blade.line(to: NSPoint(x: x + CGFloat(k - 1) * 1.5, y: y - 5))
                        blade.lineWidth = 1.2
                        blade.stroke()
                    }
                }
            }
        }
    }

    /// Il terreno, da un disegno già pronto finché non cambia niente (l'isola, lo zoom, la stagione, la griglia): disegnare le tessere ad
    /// ogni fotogramma costerebbe molto di più che copiare un'immagine.
    private var groundCache: (key: String, image: CGImage)?

    private func drawIslandGround(_ iso: Iso, season: Season) {
        let carrying = carry != nil && carryMoved
        let scale = window?.backingScaleFactor ?? 2
        let key = "\(iso.size)|\(iso.tileW)|\(iso.origin.x)|\(iso.origin.y)|\(season.rawValue)|\(carrying)|\(scale)"
        if groundCache?.key != key {
            groundCache = nil
            let width = Int(sceneW * scale), height = Int(sceneH * scale)
            if let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                cg.scaleBy(x: scale, y: -scale)
                cg.translateBy(x: 0, y: -sceneH)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
                NSGraphicsContext.current?.imageInterpolation = .high
                paintIslandGround(iso, season: season, carrying: carrying)
                NSGraphicsContext.restoreGraphicsState()
                if let image = cg.makeImage() { groundCache = (key, image) }
            }
        }
        if let cached = groundCache?.image {
            NSImage(cgImage: cached, size: Self.sceneSize).draw(in: sceneRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                                                                hints: [.interpolation: NSImageInterpolation.high])
        } else {
            paintIslandGround(iso, season: season, carrying: carrying)
        }
    }

    /// Dove cadrebbe quello che si trascina: tessere verdi se ci sta, rosse se no.
    private func drawHighlight(_ highlight: CarryTarget?, iso: Iso) {
        guard let highlight else { return }
        let good = highlight.valid
        for tile in highlight.tiles where GardenIsland.contains(tile, size: iso.size) {
            let path = diamond(tile, iso: iso, inset: 2)
            (good ? Self.color(80, 200, 105, 0.5) : Self.color(226, 80, 66, 0.5)).setFill()
            path.fill()
            (good ? Self.color(60, 160, 85) : Self.color(190, 56, 46)).setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }

    private func drawEntity(_ entity: Entity, alpha: CGFloat = 1, lift: CGFloat = 0) {
        let rect = entity.rect.offsetBy(dx: 0, dy: -lift)
        if let shadow = entity.shadow {
            NSColor(calibratedRed: 0.24, green: 0.32, blue: 0.20, alpha: 0.28 * alpha).setFill()
            NSBezierPath(ovalIn: shadow).fill()
        }
        NSGraphicsContext.saveGraphicsState()
        if entity.turned {
            let flip = NSAffineTransform()
            flip.translateX(by: rect.midX, yBy: 0)
            flip.scaleX(by: -1, yBy: 1)
            flip.translateX(by: -rect.midX, yBy: 0)
            flip.concat()
        }
        if entity.sway > 0, lift == 0, !reduceMotion {
            drawSwaying(entity, rect: rect, alpha: alpha)
        } else {
            entity.sprite.image.draw(in: rect, from: entity.sprite.source, operation: .sourceOver, fraction: alpha,
                                     respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Quello che si sta trascinando: sulla tessera dove cadrebbe (se ci sta), altrimenti sotto il mouse, più trasparente.
    private func drawGhost(_ target: CarryTarget?, iso: Iso) {
        guard let current = carry, carryMoved, let target else { return }
        var resource: String?
        var height: Double = 100
        var shadowWidth: CGFloat? = iso.tileW * 0.5
        var footprint = GardenFootprint(cols: 1, rows: 1)
        switch current {
        case .placed(let id):
            if let placement = garden.placements.first(where: { $0.id == id }), let item = GardenCatalog.item(withID: placement.item) {
                resource = item.resource; height = item.height; footprint = item.footprint.applying(turned: carryTurned)
                shadowWidth = item.castsShadow ? min(iso.tileW * 0.62 * CGFloat(max(footprint.cols, footprint.rows)), iso.tileW * 1.3) : nil
            }
        case .fresh(let id):
            if let item = GardenCatalog.item(withID: id) {
                resource = item.resource; height = item.height; footprint = item.footprint.applying(turned: carryTurned)
                shadowWidth = item.castsShadow ? min(iso.tileW * 0.62 * CGFloat(max(footprint.cols, footprint.rows)), iso.tileW * 1.3) : nil
            }
        case .companion(let petID):
            if let pet = Pet.all.first(where: { $0.id == petID }) {
                resource = pet.iconResource; height = GardenCatalog.companionHeight(for: petID)
            }
        }
        guard let resource else { return }
        let feet: NSPoint
        if target.valid {
            let ground = iso.point(col: Double(target.origin.col) + Double(footprint.cols) / 2, row: Double(target.origin.row) + Double(footprint.rows) / 2)
            feet = NSPoint(x: ground.x, y: ground.y + iso.tileH * Self.feetOffset)
        } else {
            feet = carryFeet
        }
        guard let made = entity(kind: .placed(UUID()), resource: resource, referenceHeight: height, feet: feet, shadowWidth: shadowWidth,
                                turned: carryTurned && { if case .companion = current { return false } else { return true } }(),
                                depth: 0, iso: iso) else { return }
        drawEntity(made, alpha: target.valid ? 0.95 : 0.6, lift: 6)
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
        text(items.isEmpty ? "niente per ora" : "trascina sull'isola", in: NSRect(x: 18, y: band.minY + 42, width: 100, height: 28),
             font: NSFont.systemFont(ofSize: 11), color: Paper.inkLight)
        let layout = trayLayout()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: layout.area).addClip()
        for cell in layout.cells where cell.rect.maxX > layout.area.minX && cell.rect.minX < layout.area.maxX {
            drawTrayCell(cell.item, count: cell.count, in: cell.rect)
        }
        NSGraphicsContext.restoreGraphicsState()
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
        if let button = zoomButtonRects().first(where: { $0.rect.contains(p) }) {
            button.action()
            return
        }
        guard sceneRect.contains(p), let found = entity(at: p) else {
            // sullo sfondo: due tocchi ingrandiscono (o, già ingrandita, rimettono tutta l'isola), trascinando ci si sposta
            if event.clickCount == 2 {
                if zoom > 1.05 { resetCamera() } else { zoom(by: 1.8, at: p) }
            } else {
                panning = true
                panLast = p
                NSCursor.closedHand.set()
            }
            needsDisplay = true
            return
        }
        switch found.kind {
        case .placed(let id):
            carry = .placed(id)
            carryTurned = garden.placements.first(where: { $0.id == id })?.turned ?? false
        case .companion(let petID):
            carry = .companion(petID)
            carryTurned = false
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
        // Si prende una copia: un tocco la mette sull'isola, trascinando la si mette dove si lascia.
        carry = .fresh(cell.item.id)
        carryTurned = false
        carryGrab = .zero
        carryFeet = p
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if panning {
            let q = convert(event.locationInWindow, from: nil)
            movePan(by: NSPoint(x: q.x - panLast.x, y: q.y - panLast.y))
            panLast = q
            return
        }
        guard carry != nil else { return }
        let p = convert(event.locationInWindow, from: nil)
        carryPointer = p
        if !carryMoved, hypot(p.x - carryStart.x, p.y - carryStart.y) > 4 {
            carryMoved = true
            if case .fresh? = carry { trayOpen = false }      // presa una copia, la fascia si toglie di mezzo: il davanti dell'isola è libero
        }
        if carryMoved {
            NSCursor.closedHand.set()
            carryFeet = NSPoint(x: p.x + carryGrab.width, y: p.y + carryGrab.height)
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        if panning {
            panning = false
            NSCursor.arrow.set()
            return
        }
        guard let current = carry else { return }
        let p = convert(event.locationInWindow, from: nil)
        let overTray = removeZoneRect.contains(p) && isCarryingPlaced
        let target = carryTarget()
        let wasMoved = carryMoved
        carry = nil
        carryMoved = false
        NSCursor.arrow.set()
        switch current {
        case .placed(let id):
            if wasMoved {
                if overTray {
                    garden.remove(id)
                } else if let target, target.valid {
                    garden.move(id, to: target.origin, turned: carryTurned)
                } else if sceneRect.contains(p) {
                    flash("Lì non ci sta: serve una tessera libera, fuori dal sentiero.")
                }
            }
        case .companion(let petID):
            if wasMoved {
                if !overTray, let target, target.valid {
                    garden.setCompanionTile(petID, to: target.origin)
                    walkers[petID] = Walker(from: target.origin, to: target.origin, progress: 1, rest: 3)
                }
            } else {
                speak(petID)
            }
        case .fresh(let id):
            if !wasMoved {
                if garden.placeSomewhere(id) == nil { flash("Non c'è più posto sull'isola: togli qualcosa, o completa una doppia pagina dell'album per allargarla.") }
            } else if let target, target.valid {
                garden.place(id, at: target.origin, turned: carryTurned)
            } else if sceneRect.contains(p), !overTray {
                flash("Lì non ci sta: serve una tessera libera, fuori dal sentiero.")
            }
        }
        carryTurned = false
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if trayVisible, trayRect.contains(p) {
            guard maxTrayScroll > 0 else { return }
            let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : -event.scrollingDeltaY
            trayScroll = min(max(trayScroll + delta * (event.hasPreciseScrollingDeltas ? 1 : 8), 0), maxTrayScroll)
            needsDisplay = true
            return
        }
        let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 8
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
            // con ⌘ (o ⌥) la rotella ingrandisce
            zoom(by: exp(event.scrollingDeltaY * factor * 0.01), at: p)
        } else {
            movePan(by: NSPoint(x: event.scrollingDeltaX * factor, y: event.scrollingDeltaY * factor))
        }
    }

    /// Il pizzico sul trackpad ingrandisce attorno al mouse.
    override func magnify(with event: NSEvent) {
        zoom(by: 1 + event.magnification, at: convert(event.locationInWindow, from: nil))
    }

    /// Un clic con il tasto destro su una copia: girarla o toglierla dall'isola.
    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        guard sceneRect.contains(p), let found = entity(at: p), case .placed(let id) = found.kind else { return nil }
        let menu = NSMenu()
        let turn = NSMenuItem(title: "Gira", action: #selector(turnFromMenu(_:)), keyEquivalent: "")
        turn.representedObject = id
        turn.target = self
        menu.addItem(turn)
        let remove = NSMenuItem(title: "Togli dal giardino", action: #selector(removeFromMenu(_:)), keyEquivalent: "")
        remove.representedObject = id
        remove.target = self
        menu.addItem(remove)
        return menu
    }

    @objc private func removeFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        garden.remove(id)
    }

    @objc private func turnFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        if !garden.rotate(id) { flash("Girata non ci sta: c'è qualcosa accanto.") }
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
    static func scale(forScreenWidth width: CGFloat, height: CGFloat = .greatestFiniteMagnitude) -> CGFloat {
        min(1, max(min((width - 40) / GardenView.sceneSize.width, (height - 90) / GardenView.sceneSize.height), 0.5))
    }

    func show() {
        if window == nil {
            let scale = Self.scale(forScreenWidth: NSScreen.main?.visibleFrame.width ?? 1440, height: NSScreen.main?.visibleFrame.height ?? 900)
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
        view?.resetCamera()
        view?.reload()
        view?.announceGifts(gifts.count)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
