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
        /// Se sta andando in un angolo a fare una posa: il resto della strada.
        var errand: Errand?
        /// Se sta facendo la posa (dorme, mangia, saltella, sbatte le ali…).
        var activity: Activity?
        /// Da quanti secondi non fa niente di speciale: dopo una posa passa un po' prima della prossima. Parte alto, così la prima viene presto.
        var idle: Double = 20
    }
    private struct Errand {
        var route: [GardenTile]
        var affinity: GardenAffinity
    }
    private struct Activity {
        var affinity: GardenAffinity
        var remaining: Double
    }
    private var walkers: [String: Walker] = [:]

    /// Un ospite che è venuto a trovarti: arriva da un bordo dell'isola, cammina fino a una tessera accanto a quello che l'ha attirato, aspetta e se ne va.
    private struct Visitor {
        enum Phase { case arriving, staying, leaving }
        var attraction: GardenVisitors.Attraction
        /// La strada, dalla tessera d'ingresso a quella dove si ferma.
        var path: [GardenTile]
        /// La tessera dove sta (o da cui parte) e quella verso cui cammina (la stessa se sta fermo); `progress` è a che punto del passo.
        var index: Int
        var next: Int
        var progress: Double
        var phase: Phase
        var remaining: Double
        var greeted: Bool
        var fade: Double
        var facingRight: Bool
    }
    private var visitor: Visitor?
    /// Le fasce della giornata in cui è già venuto qualcuno (o nessuno) da quando la finestra è aperta: non si ripete.
    private var visitedSlots = Set<String>()
    private var visitorClock = 0.0
    private var visitorCheck = 0.0
    private var walkTimer: Timer?
    private var lastWalkTick = Date()
    private var skyTicks = 0
    private var frameTick = 0
    private var lastSky: SkyState?

    /// Uno sblocco in corso: le stelline escono dal centro dell'angolo e in alto compare la scritta «Hai sbloccato…».
    private struct Celebration {
        /// La riga piccola («Hai sbloccato», «Nuovo ospite») e quella grande (il nome dell'angolo o dell'ospite).
        var caption: String
        var title: String
        /// Le cose dell'angolo (le stelline escono dal loro centro), o la specie dell'ospite (escono da lui).
        var members: [UUID]
        var visitor: String?
        /// Quando è cominciata: si imposta al primo disegno (se la finestra era chiusa, non si perde).
        var start: Double?
    }
    private var celebrations: [Celebration] = []
    /// Quanto dura la scritta (le stelline, un po' meno).
    private static let celebrationLength = 4.6

    /// L'arrivo di un compagno, alla prima entrata nel giardino dopo averlo sbloccato: la telecamera scivola a inquadrare le isole, gli eventuali ponti compaiono pezzo per pezzo e
    /// alla fine i ponti si salvano come costruiti, l'isola è accolta e arriva il regalo di benvenuto. I ponti possono mancare (un compagno in diagonale rispetto alle isole aperte non
    /// ne ha: resta il regalo, con la scritta «Nuova isola») e gli accolti possono mancare (un ponte fra due isole già accolte). Prima della fine non si salva niente: se la finestra si
    /// chiude a metà, riparte. Le prove a vuoto (`rehearsalIsland`, la chiave `replayBridges`) rifanno la costruzione senza salvare né regalare niente.
    private struct ArrivalCeremony {
        var bridges: [GardenBridge]
        /// Le isole che ricevono il regalo (una per compagno appena sbloccato).
        var welcomed: [String]
        var from: (zoom: CGFloat, pan: NSPoint)
        var to: (zoom: CGFloat, pan: NSPoint)
        /// Quando è cominciata (`effectsClock`) e quanti pezzi di ponte compaiono in tutto.
        var start: Double
        var pieces: Int
        /// La telecamera sta scivolando; si ferma se chi guarda la sposta lui.
        var gliding = true
        /// La prova a vuoto (`replayBridges`): l'isola che si prova. Non si salva né si regala niente.
        var rehearsalIsland: String?
    }
    private var ceremony: ArrivalCeremony?
    private static let ceremonyGlide = 1.2, ceremonyPieceGap = 0.38, ceremonyPieceFade = 0.5, ceremonyHold = 0.6

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
        // un angolo che c'era già prima di aprire la finestra si sblocca adesso (e si annuncia), una volta sola
        garden.discoverCorners()
        garden.addObserver { [weak self] in self?.reload() }
        resetCamera()
        reload()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Dati

    /// Rifà i conti della serie e ridisegna.
    func reload() {
        streak = StudyStreak.analyze(sessions: log.sessions, now: now(), calendar: calendar)
        for id in garden.takeNewCorners() {
            if let corner = GardenCorners.corner(withID: id) {
                celebrations.append(Celebration(caption: "Hai sbloccato", title: corner.name, members: garden.formedCorners[id] ?? [], visitor: nil, start: nil))
            }
        }
        removeAllToolTips()
        let hud = hudLayout()
        addToolTip(hud.album, owner: self, userData: UnsafeMutableRawPointer(bitPattern: 1))
        if let chip = hud.streak { addToolTip(chip, owner: self, userData: UnsafeMutableRawPointer(bitPattern: 2)) }
        addToolTip(captionRect, owner: self, userData: UnsafeMutableRawPointer(bitPattern: 3))
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
            case "m": toggleWorldView(); return
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

    /// Le cose degli animali sono appena passate sulle loro isole (`Garden.settleRules`): una riga lo dice, una volta sola.
    func announceRules() {
        guard let report = garden.takeRulesNotice() else { return }
        flash(report.line, seconds: 6)
    }

    /// Se la cosa non può stare sull'isola mostrata perché è di un altro animale: la riga che lo dice («La casa del gatto sta solo sull'isola di Gattino.»).
    private func wrongIslandLine(for itemID: String?) -> String? {
        guard let itemID, let item = GardenCatalog.item(withID: itemID), let owner = item.island, !item.fits(island: garden.shownIsland) else { return nil }
        return item.wrongIslandLine(ownerName: petName(owner))
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

        /// Quanto posto si lascia sotto l'isola per il suo lato di terra (che poi si disegna alto un po' più di un quarto di tessera: `edge`).
        static let thickness: CGFloat = 24
        /// Dove cominciano l'isola (c'è posto sopra per le cose alte) e quanto resta sotto.
        static let top: CGFloat = 140
        /// Con la collina c'è meno posto sotto, quindi l'isola comincia più in alto (le cose alte sono più piccole, perché l'isola lo è).
        static let hillTop: CGFloat = 104
        static let bottomMargin: CGFloat = 44

        /// Quanto è larga una tessera, a zoom 1, per un'isola di `size` tessere per lato: con la collina sotto deve starci tutta (è larga quasi due isole e scende sotto),
        /// quindi l'isola è un po' più piccola e comincia più in alto.
        static func fit(size: Int, scene: NSSize) -> CGFloat {
            let hill = GardenView.hasHill
            let top = hill ? hillTop : Self.top
            let availableHeight = scene.height - top - bottomMargin - thickness
            var fit = min((scene.width - 60) / CGFloat(size), 2 * availableHeight / CGFloat(size))
            if hill {
                let widthFit = (scene.width - 16) / (CGFloat(size) * CGFloat(GardenHill.widthRatio))
                let heightFit = (scene.height - top - 14) / (CGFloat(size) * CGFloat(GardenHill.heightRatio))
                fit = min(widthFit, heightFit)
            }
            return fit
        }

        /// Dove comincia l'isola (il suo vertice in alto) a zoom 1.
        static var sceneTop: CGFloat { GardenView.hasHill ? hillTop : top }

        init(size: Int, tileW: CGFloat, origin: NSPoint) {
            self.size = size
            self.tileW = tileW
            self.origin = origin
        }

        var tileH: CGFloat { tileW / 2 }
        /// L'altezza del lato di terra, in proporzione alle tessere.
        var edge: CGFloat { max(tileW * 0.26, 8) }
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

    /// L'isola mostrata (quella «viva»: ci camminano i compagni, ci si trascinano le cose) alla vista di adesso.
    private var iso: Iso { isoOf(garden.shownIsland) ?? Iso(size: garden.islandSize, tileW: 40, origin: .zero) }

    /// I pixel per punto dello schermo su cui sta la finestra.
    private var backingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    // MARK: - La vista: zoom e spostamenti

    /// La telecamera è una sola per tutto il mondo (le quattro isole): lo zoom 1 è una tessera larga quanto per un'isola grande al massimo, che alla sua isola sta tutta nella
    /// finestra; rimpicciolendo si vedono le altre isole, e ci si sposta da una all'altra trascinando.
    static var zoomRange: ClosedRange<CGFloat> { hasHill ? 0.4...2.5 : 0.3...2.5 }
    /// Quanto è ingrandita la vista e di quanto è spostata.
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
        cameraMoved()
    }

    /// Tutta l'isola mostrata, a misura della finestra.
    func resetCamera() {
        let camera = islandCamera(garden.shownIsland)
        zoom = camera.zoom
        pan = camera.pan
        needsDisplay = true
    }

    private func movePan(by delta: NSPoint) {
        pan = NSPoint(x: pan.x + delta.x, y: pan.y + delta.y)
        cameraMoved()
    }

    /// Dopo uno zoom o uno spostamento: il centro della finestra resta nel mondo, e l'isola viva è quella più vicina al centro.
    private func cameraMoved() {
        ceremony?.gliding = false
        clampCamera()
        updateFocus()
        needsDisplay = true
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
                : button.symbol == "plus" ? zoom < Self.zoomRange.upperBound - 0.001 : !isFitted()
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
        /// Un ospite (la specie, `GardenVisitor.id`).
        case visitor(String)
    }

    /// Una cosa sull'isola, con dove cade a schermo.
    private struct Entity {
        var kind: Kind
        var sprite: GardenSprite
        var resource = ""
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
        /// Quanto si vede (un ospite compare e sparisce piano).
        var alpha: CGFloat = 1
        /// L'isola a cui sta (l'id): un tocco su una cosa di un'altra isola la porta in primo piano.
        var island = ""
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
        return Entity(kind: kind, sprite: sprite, resource: resource, feet: feet, rect: rect, shadow: shadow, turned: turned, depth: depth)
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

    /// I compagni che stanno sull'isola mostrata: ognuno vive solo sulla sua (l'id dell'isola è quello del compagno), se è sbloccato.
    private func companionsHere() -> [(offset: Int, element: Pet)] {
        Pet.all.enumerated().filter { profile.isCompanionUnlocked($0.element.id) && $0.element.id == garden.shownIsland }
    }

    /// Gli oggetti e i compagni sbloccati, dal fondo al davanti. Quello che si sta trascinando non c'è: si disegna a parte (`drawGhost`).
    private func entities() -> [Entity] {
        let iso = self.iso
        var result: [Entity] = []
        // le bandierine di una festa in giardino ondeggiano di più
        let party = Set(garden.formedCorners["festa"] ?? [])
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
            made.sway = item.swayStrength * (party.contains(placement.id) ? 1.7 : 1)
            made.seed = Double(GardenDrops.hash(placement.id.uuidString) % 1000) / 1000
            made.tile = placement.tile
            made.water = item.waterSpot
            result.append(made)
        }
        for (index, pet) in companionsHere() {
            if carryMoved, carry == .companion(pet.id) { continue }
            let home = garden.companionTile(pet.id, index: index)
            let ground = companionGround(pet.id, home: home, iso: iso)
            let feet = NSPoint(x: ground.point.x, y: ground.point.y + iso.tileH * Self.feetOffset)
            // se sta facendo una posa si disegna il fotogramma di quel momento (e, se manca l'immagine, quella ferma)
            var resource = pet.iconResource
            if let activity = walkers[pet.id]?.activity,
               let pose = GardenCompanions.resource(pet: pet.id, pose: activity.affinity.pose, time: effectsClock()), GardenSprites.sprite(pose) != nil {
                resource = pose
            }
            guard let made = entity(kind: .companion(pet.id), resource: resource, referenceHeight: GardenCatalog.companionHeight(for: pet.id),
                                    feet: feet, shadowWidth: iso.tileW * 0.5, turned: false, depth: ground.depth, iso: iso) else { continue }
            result.append(made)
        }
        if let guest = visitor, let made = visitorEntity(guest, iso: iso) { result.append(made) }
        // la profondità è quella del mondo: le cose di un'isola più avanti stanno davanti a quelle di un'isola dietro
        let here = garden.shownIsland
        let base = GardenWorld.corner(of: here, size: iso.size).map { $0.col + $0.row } ?? 0
        for index in result.indices {
            result[index].depth += base
            result[index].island = here
        }
        for entry in worldIslands() where entry.open && entry.id != here { result += staticEntities(on: entry.id, iso: entry.iso) }
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
        let pets = companionsHere()
        let hereIDs = Set(pets.map { $0.element.id })
        for (index, pet) in pets {
            if carry == .companion(pet.id) { continue }
            let home = garden.companionTile(pet.id, index: index)
            var walker = walkers[pet.id] ?? Walker(from: home, to: home, progress: 1, rest: 1 + Double.random(in: 0...3))
            if !GardenLayout.isWalkable(walker.from, size: size, occupied: occupied) || !GardenLayout.isWalkable(walker.to, size: size, occupied: occupied) {
                // Gli hanno messo un oggetto sotto i piedi (o l'isola è cambiata): torna a casa.
                walker = Walker(from: home, to: home, progress: 1, rest: 1)
            }
            // l'angolo si è sciolto mentre ci andava o ci stava: smette
            if let errand = walker.errand, garden.formedCorners[errand.affinity.corner] == nil { walker.errand = nil }
            if let activity = walker.activity, garden.formedCorners[activity.affinity.corner] == nil { walker.activity = nil; walker.idle = 0 }
            walker.idle += dt
            let taken = Set(walkers.filter { $0.key != pet.id && hereIDs.contains($0.key) }.flatMap { [$0.value.from, $0.value.to] })
            if walker.progress < 1 {
                walker.progress = min(1, walker.progress + dt / 1.3)
                moving = true
            } else {
                walker.from = walker.to
                if var activity = walker.activity {
                    // fa la posa: i fotogrammi cambiano, quindi si ridisegna
                    activity.remaining -= dt
                    moving = true
                    if activity.remaining <= 0 {
                        walker.activity = nil
                        walker.idle = 0
                        walker.rest = 1.2
                    } else {
                        walker.activity = activity
                    }
                } else if var errand = walker.errand {
                    walker.rest -= dt
                    if walker.rest <= 0 {
                        if errand.route.isEmpty {
                            walker.errand = nil
                            walker.activity = Activity(affinity: errand.affinity, remaining: Double.random(in: errand.affinity.pose.duration))
                        } else {
                            let next = errand.route.removeFirst()
                            if GardenLayout.isWalkable(next, size: size, occupied: occupied) && !taken.contains(next) {
                                walker.to = next
                                walker.progress = 0
                                walker.errand = errand
                                moving = true
                            } else {
                                walker.errand = nil      // la strada si è chiusa: lascia perdere
                            }
                        }
                    }
                } else {
                    walker.rest -= dt
                    if walker.rest <= 0 {
                        if let errand = startErrand(for: pet.id, walker: walker, size: size, occupied: occupied, taken: taken) {
                            walker.errand = errand
                            walker.rest = 0
                        } else {
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
                }
            }
            walkers[pet.id] = walker
        }
        return moving
    }

    /// Se un compagno ha un angolo che gli piace e c'è (e nessun altro ci sta andando), ogni tanto ci va: la strada più corta fino a una tessera accanto
    /// a una cosa dell'angolo.
    private func startErrand(for petID: String, walker: Walker, size: Int, occupied: Set<GardenTile>, taken: Set<GardenTile>) -> Errand? {
        guard walker.idle > 25, Double.random(in: 0..<1) < 0.4 else { return nil }
        var busy = Set<String>()
        for (otherID, other) in walkers where otherID != petID {
            if let corner = other.errand?.affinity.corner ?? other.activity?.affinity.corner { busy.insert(corner) }
        }
        let options = GardenCompanions.affinities.filter { $0.pet == petID && garden.formedCorners[$0.corner] != nil && !busy.contains($0.corner) }
        guard let affinity = options.randomElement(), let ids = garden.formedCorners[affinity.corner],
              let placement = garden.placements.first(where: { ids.contains($0.id) && $0.item == affinity.item }),
              let item = GardenCatalog.item(withID: placement.item) else { return nil }
        let footprint = GardenLayout.tiles(of: item.footprint.applying(turned: placement.turned), at: placement.tile)
        var best: [GardenTile]?
        for tile in GardenCompanions.standingTiles(around: footprint, size: size) where GardenLayout.isWalkable(tile, size: size, occupied: occupied) && !taken.contains(tile) {
            guard let route = GardenCompanions.route(from: walker.from, to: tile, size: size, occupied: occupied) else { continue }
            if best == nil || route.count < best?.count ?? Int.max { best = route }
        }
        guard let route = best else { return nil }
        return Errand(route: route, affinity: affinity)
    }

    private func startWalking() {
        walkTimer?.invalidate()
        lastWalkTick = Date()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self, let window = self.window, window.isVisible, window.occlusionState.contains(.visible) else { return }
            let elapsed = min(Date().timeIntervalSince(self.lastWalkTick), 0.2)
            self.lastWalkTick = Date()
            let building = self.advanceCeremony()
            let walking = self.advanceWalkers(by: elapsed) || self.advanceVisitor(by: elapsed) || building
            // di tanto in tanto si guarda se la luce è cambiata (sta calando la sera): altrimenti si ridisegna solo se qualcosa si muove
            self.skyTicks += 1
            var changed = false
            if self.skyTicks % 30 == 0 {
                let light = self.skyState()
                if light != self.lastSky { changed = true }
                self.lastSky = light
            }
            // a 30 al secondo se si cammina, a 15 se si muove solo l'aria (vento, fumo, neve): basta, e costa la metà
            self.frameTick += 1
            if walking || changed || !self.celebrations.isEmpty || (self.frameTick % 2 == 0 && self.skyIsAnimated()) { self.needsDisplay = true }
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
            let others = companionsHere().filter { $0.element.id != petID }.map { garden.companionTile($0.element.id, index: $0.offset) }
            let valid = GardenLayout.isWalkable(tile, size: iso.size, occupied: garden.occupiedTiles()) && !others.contains(tile)
            return CarryTarget(origin: tile, tiles: [tile], valid: valid)
        case .placed(let id):
            guard let placement = garden.placement(withID: id), let item = GardenCatalog.item(withID: placement.item) else { return nil }
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

    /// Le copie ancora da mettere che stanno sull'isola mostrata (le universali e quelle del suo animale), nell'ordine dell'album.
    private func trayItems() -> [(item: GardenItem, count: Int)] {
        garden.tray()
    }

    /// La fascia si vede solo aperta (toglierne una dall'isola è un'altra cosa: `removeZoneRect`).
    private var trayVisible: Bool { trayOpen && !trayItems().isEmpty }

    /// Trascinando una copia dell'isola, in basso a sinistra compare dove lasciarla per toglierla (fuori dall'isola, che sta più in alto).
    private var removeZoneRect: NSRect { NSRect(x: 16, y: sceneH - 64, width: 236, height: 46) }

    private var isCarryingPlaced: Bool {
        if case .placed? = carry, carryMoved { return true }
        return false
    }

    /// Un compagno non lascia la sua isola: se è lui quello che si trascina, passando sopra un'altra isola questa non diventa quella viva.
    private var isCarryingCompanion: Bool {
        if case .companion? = carry { return true }
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
        if Int(bitPattern: data) == 3 {
            return "Tocca per vedere tutte le isole, e di nuovo per tornare a questa. Si ingrandisce e ci si sposta da un'isola all'altra anche con lo zoom e trascinando."
        }
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
        let iso = self.iso
        let target = carryTarget()
        currentTint = GardenTint(multiplier: sky.light.multiplier)
        currentSeason = sky.season
        drawStaticScene(iso, season: sky.season, light: sky.light)
        drawArrivalCeremony()
        drawChimneySmoke(season: sky.season, iso: iso)
        drawHighlight(target, iso: iso)
        let laid = entities()
        for entity in laid {
            drawEntity(entity, alpha: entity.alpha)
            if let spot = entity.water { drawWater(entity, spot: spot, light: sky.light) }
        }
        drawGhost(target, iso: iso)
        drawVisitorHint(laid)
        drawCornerEffects(laid, season: sky.season, light: sky.light, iso: iso)
        drawWeather(sky.season, light: sky.light)
        drawLampGlows(laid, iso: iso, light: sky.light)
        drawCottageWindows(light: sky.light, season: sky.season, iso: iso)
        drawLandmarkLights(light: sky.light)
        drawFireflies(season: sky.season, light: sky.light)
        if let bubble, let owner = laid.first(where: { $0.kind == .companion(bubble.petID) }) {
            drawBubble(bubble.text, above: owner.rect)
        }
        drawIslandLabels()
        drawHUD()
        drawIslandCaption()
        if trayVisible { drawTray() } else if showsTrayPill { drawTrayPill() }
        drawZoomControls()
        drawCelebration(laid, iso: iso)
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
    /// L'ora che si vede: quella dell'orologio, o quella messa a mano con `gardenHour` (per provare la sera senza aspettare).
    private func shownHour() -> Double {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "gardenHour") != nil { return defaults.double(forKey: "gardenHour") }
        return GardenSky.hour(of: now(), calendar: calendar)
    }

    private func skyState() -> SkyState {
        let defaults = UserDefaults.standard
        let date = now()
        let hour = shownHour()
        let season = GardenSky.shownSeason(date: date, calendar: calendar, defaults: defaults)
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

    private static func palette(_ season: Season) -> Palette {
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

    /// Prepara in anticipo quello che serve al primo disegno del giardino e dell'album (le immagini del terreno e degli oggetti, già decodificate, e gli
    /// sfondi già finiti): si chiama all'avvio, fuori dal thread principale, così quando si apre la finestra non c'è da aspettare.
    static func warmUp() {
        _ = decalImages
        _ = hillImage(Season.of(Date()))
        if Season.of(Date()) == .winter {
            _ = snowImages; _ = snowPathImages; _ = snowEdgeImages; _ = darkSnowEdgeImages
        } else {
            _ = grassImages; _ = pathImages; _ = edgeImages; _ = darkEdgeImages
        }
        for item in GardenCatalog.items { _ = GardenSprites.sprite(item.resource) }
        for pet in Pet.all { _ = GardenSprites.sprite(pet.iconResource) }
        let season = Season.of(Date())
        // le colline tinte (una per isola e quella al buio delle isole chiuse), le case e i pezzi dei ponti: senza, il primo disegno li prepara tutti insieme
        _ = darkHillImage(season)
        for island in GardenIslands.all {
            _ = moodHillImage(season, island: island)
            _ = GardenSprites.sprite("giardino_casa_" + island)
        }
        for direction in ["colonna", "riga"] {
            for variant in 1...2 { _ = GardenSprites.sprite("giardino_ponte_\(direction)_\(variant)") }
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        _ = MeadowBackdrop.world(size: sceneSize, blur: 2, season: season)
        _ = MeadowBackdrop.rendered(size: AlbumView.size, scale: scale, blur: 0, veil: nil, season: season)
    }

    /// L'ora del cielo e degli effetti, in secondi (un banco di prova la può fissare).
    var effectsClock: () -> Double = { CACurrentMediaTime() }

    /// Petali, foglie o neve che cadono, a seconda della stagione.
    private func drawWeather(_ season: Season, light: GardenLight) {
        guard let kind = GardenSky.particleKind(season), !reduceMotion else { return }
        let time = effectsClock()
        let leafColors = [Self.color(214, 120, 50), Self.color(190, 84, 44), Self.color(226, 168, 60), Self.color(150, 104, 52)]
        for index in 0..<GardenSky.particleCount(kind) {
            let p = GardenSky.particle(kind: kind, index: index, time: time, width: Double(sceneW), height: Double(sceneH))
            let size = CGFloat(p.size)
            var color: NSColor
            switch kind {
            case .petal: color = p.tone < 0.5 ? Self.color(255, 196, 214, p.alpha) : Self.color(255, 238, 242, p.alpha)
            case .leaf: color = leafColors[min(Int(p.tone * Double(leafColors.count)), leafColors.count - 1)].withAlphaComponent(CGFloat(p.alpha))
            case .snow: color = NSColor.white.withAlphaComponent(CGFloat(p.alpha) * 0.9)
            }
            // la luce del momento (sono sopra la scena, che è già tinta)
            let m = light.multiplier
            if let rgb = color.usingColorSpace(.deviceRGB) {
                color = NSColor(calibratedRed: rgb.redComponent * CGFloat(m.red / 255), green: rgb.greenComponent * CGFloat(m.green / 255),
                                blue: rgb.blueComponent * CGFloat(m.blue / 255), alpha: rgb.alphaComponent)
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

    /// La luce del momento: la scena si moltiplica per un colore (bianco di giorno, azzurro scuro di notte) su tutta `area`.
    private func applyLight(_ light: GardenLight, in area: NSRect) {
        guard light.tintStrength > 0.001 else { return }
        let m = light.multiplier
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setBlendMode(.multiply)
        NSColor(calibratedRed: CGFloat(m.red / 255), green: CGFloat(m.green / 255), blue: CGFloat(m.blue / 255), alpha: 1).setFill()
        area.fill(using: .multiply)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Di sera i bordi della finestra si scuriscono.
    private func nightVeil(_ light: GardenLight) {
        guard light.tintStrength > 0.001, light.darkness > 0.1 else { return }
        NSGradient(colors: [NSColor(calibratedRed: 0.55, green: 0.58, blue: 0.80, alpha: 0), NSColor(calibratedRed: 0.28, green: 0.30, blue: 0.55, alpha: CGFloat(min(light.darkness * 1.3, 0.7)))])?
            .draw(in: sceneRect, relativeCenterPosition: .zero)
    }

    /// I lampioni accesi: una luce calda in cima e una pozza sul prato.
    private func drawLampGlows(_ laid: [Entity], iso: Iso, light: GardenLight) {
        let strength = CGFloat(light.lamp)
        guard strength > 0.01 else { return }
        let lamps = Set(GardenIslands.all.flatMap { garden.placements(on: $0) }.filter { $0.item == "lampione" }.map { $0.id })
        // il lampione dell'angolo di lettura fa più luce, e più calda
        let reading = Set(garden.formedCorners["lettura"] ?? [])
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setBlendMode(.plusLighter)
        let warm = Self.color(255, 196, 104)
        for entity in laid {
            guard case .placed(let id) = entity.kind, lamps.contains(id) else { continue }
            let boost: CGFloat = reading.contains(id) ? 1.45 : 1
            let top = NSPoint(x: entity.rect.midX, y: entity.rect.minY + entity.rect.height * 0.10)
            NSGradient(colors: [warm.withAlphaComponent(0.48 * strength * min(boost, 1.2)), warm.withAlphaComponent(0.14 * strength * min(boost, 1.2)), warm.withAlphaComponent(0)])?
                .draw(fromCenter: top, radius: 0, toCenter: top, radius: iso.tileW * 1.25 * boost, options: [])
            // la pozza di luce sul prato, schiacciata come l'isola
            NSGraphicsContext.saveGraphicsState()
            let squash = NSAffineTransform()
            squash.translateX(by: entity.feet.x, yBy: entity.feet.y)
            squash.scaleX(by: 1, yBy: 0.5)
            squash.concat()
            NSGradient(colors: [warm.withAlphaComponent(0.34 * strength), warm.withAlphaComponent(0)])?
                .draw(fromCenter: .zero, radius: 0, toCenter: .zero, radius: iso.tileW * 1.5 * boost, options: [])
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
    private var reduceMotion: Bool { motionReduced() }
    /// «Riduci movimento» del sistema; i banchi di prova lo cambiano per vedere i due modi.
    var motionReduced: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Disegna una pianta piegata dal vento: a strisce orizzontali, ognuna spostata di lato un po' di più della sottostante, così la base
    /// sta ferma e la cima oscilla.
    private func drawSwaying(_ entity: Entity, rect: NSRect, alpha: CGFloat) {
        let iso = self.iso
        let time = effectsClock()
        let wind = GardenSky.wind(skyState().season)
        let amplitude = CGFloat(entity.sway * wind) * 2.6 * iso.tileW / 94
        let scale = backingScale
        let pixelWidth = max(1, Int((rect.width * scale).rounded())), pixelHeight = max(1, Int((rect.height * scale).rounded()))
        let strips = GardenSprites.strips(entity.sprite, resource: entity.resource, pixelWidth: pixelWidth, pixelHeight: pixelHeight, count: 12, tint: currentTint)
        for strip in strips {
            let middle = (Double(strip.firstRow) + Double(strip.image.height) / 2) / Double(pixelHeight)
            let dx = CGFloat(GardenSky.sway(time: time, col: entity.tile.col, row: entity.tile.row, seed: entity.seed, height: 1 - middle)) * amplitude
            let target = NSRect(x: rect.minX + dx, y: rect.minY + CGFloat(strip.firstRow) / scale, width: rect.width, height: CGFloat(strip.image.height) / scale)
            GardenBlit.draw(strip.image, in: target, alpha: alpha)
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

    /// Un punto del paesaggio (come sta con la vista a zoom 1 e senza spostamenti) dove cade adesso, con la telecamera di ora: il paesaggio si sposta e si ingrandisce
    /// attorno al centro della scena insieme all'isola e alla collina.
    private func cameraPoint(_ p: NSPoint) -> NSPoint {
        NSPoint(x: sceneW / 2 + (p.x - sceneW / 2) * zoom + pan.x, y: sceneH / 2 + (p.y - sceneH / 2) * zoom + pan.y)
    }

    /// Il fumo che esce dal camino del casale (sullo sfondo, dietro l'isola): sbuffi chiari che salgono e si piegano col vento.
    private func drawChimneySmoke(season: Season, iso: Iso) {
        let amount = GardenSky.smokeAmount(season)
        let chimney = MeadowBackdrop.chimney(season)
        guard amount > 0.01, let fixed = backdropPoint(u: chimney.u, v: chimney.v, season: season) else { return }
        let mouth = cameraPoint(fixed)
        // il fumo sta dietro l'isola: non si disegna sopra di lei
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let clip = NSBezierPath(rect: sceneRect.insetBy(dx: -20, dy: -20))
        for entry in worldIslands() { clip.append(islandOutline(entry.iso)) }
        clip.windingRule = .evenOdd
        clip.addClip()
        let time = reduceMotion ? 3 : effectsClock()
        let wind = GardenSky.wind(season)
        // sul bianco della neve il fumo chiaro non si vedrebbe: un po' più grigio
        let color = season == .winter ? Self.color(204, 204, 214) : Self.color(226, 222, 224)
        for index in 0..<GardenSky.smokeCount {
            let puff = GardenSky.smoke(index: index, time: time, wind: wind)
            let a = min(CGFloat(puff.alpha * amount) * 1.5, 0.8)
            guard a > 0.01 else { continue }
            let k = MeadowBackdrop.houseScale(season) * zoom * Self.backdropScale
            let c = NSPoint(x: mouth.x + CGFloat(puff.dx) * k, y: mouth.y + CGFloat(puff.dy) * k)
            NSGradient(colors: [color.withAlphaComponent(a), color.withAlphaComponent(a * 0.55), color.withAlphaComponent(0)])?
                .draw(fromCenter: c, radius: 0, toCenter: c, radius: CGFloat(puff.radius) * 1.7 * k, options: [])
        }
    }

    /// Di sera le finestre del casale si accendono (non sopra l'isola, che sta davanti).
    private func drawCottageWindows(light: GardenLight, season: Season, iso: Iso) {
        let strength = CGFloat(light.lamp)
        guard strength > 0.02 else { return }
        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(rect: sceneRect.insetBy(dx: -20, dy: -20))
        for entry in worldIslands() { clip.append(islandOutline(entry.iso)) }
        clip.windingRule = .evenOdd
        clip.addClip()
        NSGraphicsContext.current?.cgContext.setBlendMode(.plusLighter)
        let warm = Self.color(255, 208, 120)
        for window in MeadowBackdrop.windows(season) {
            guard let fixed = backdropPoint(u: window.u, v: window.v, season: season) else { continue }
            let c = cameraPoint(fixed)
            NSGradient(colors: [warm.withAlphaComponent(0.8 * strength), warm.withAlphaComponent(0.25 * strength), warm.withAlphaComponent(0)])?
                .draw(fromCenter: c, radius: 0, toCenter: c, radius: 20 * MeadowBackdrop.houseScale(season) * zoom * Self.backdropScale * 0.55, options: [])
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Il contorno dell'isola con i suoi lati di terra.
    private func islandOutline(_ iso: Iso) -> NSBezierPath {
        let n = Double(iso.size)
        let top = iso.point(col: 0, row: 0), right = iso.point(col: n, row: 0), front = iso.point(col: n, row: n), left = iso.point(col: 0, row: n)
        let t = iso.edge
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

    private static func diamond(_ tile: GardenTile, iso: Iso, inset: CGFloat = 0) -> NSBezierPath {
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
            GardenSprites.loadImage("giardino_tessera_erba_\(index)")
        }
        return images.count == GardenTerrain.grassCount ? images : nil
    }()

    /// Le otto tessere del sentiero.
    private static var pathImages: [NSImage]? = {
        let images = (1...GardenTerrain.pathCount).compactMap { index in
            GardenSprites.loadImage("giardino_tessera_sentiero_\(index)")
        }
        return images.count == GardenTerrain.pathCount ? images : nil
    }()

    /// La collina sotto l'isola (`collina_<stagione>.png`, da `tools/prepara_collina.py`); senza, il giardino si disegna come prima, con la striscia di terra e l'ombra.
    private static let hillNames: [Season: String] = [.spring: "primavera", .summer: "estate", .autumn: "autunno", .winter: "inverno"]
    static let hasHill = Bundle.main.url(forResource: "giardino_collina_autunno", withExtension: "png") != nil
    private static let hillLock = NSLock()
    private static var hillCache: [Season: NSImage] = [:]
    private static func hillImage(_ season: Season) -> NSImage? {
        hillLock.lock()
        defer { hillLock.unlock() }
        if let known = hillCache[season] { return known }
        guard let name = hillNames[season], let loaded = GardenSprites.loadImage("giardino_collina_\(name)"),
              let decoded = Self.decoded(loaded) else { return nil }
        hillCache[season] = decoded
        return decoded
    }

    /// Il carattere di ogni isola: una tinta leggera sul terreno e sulla collina, perché si riconoscano da lontano (Pianty fresca e verde, Porcellino calda di paglia,
    /// Ciccio fredda di cielo, Gattino di pietra e di lilla). D'inverno, sotto la neve, è più leggera.
    private static func islandWash(_ island: String, season: Season) -> NSColor? {
        let k: CGFloat = season == .winter ? 0.55 : 1
        switch island {
        case "pianty": return color(96, 200, 84, 0.16 * k)
        case "porcellino": return color(238, 150, 96, 0.24 * k)
        case "ciccio": return color(70, 170, 214, 0.22 * k)
        case "gattino": return color(112, 132, 204, 0.26 * k)
        default: return nil
        }
    }

    /// La collina di una stagione con sopra un colore (solo dove l'immagine c'è: i bordi trasparenti restano), già pronta: quella scura delle isole chiuse e quelle delle isole aperte.
    private static var tintedHillCache: [String: NSImage] = [:]
    private static func tintedHillImage(_ season: Season, key: String, color: CGColor) -> NSImage? {
        guard let base = hillImage(season) else { return nil }
        hillLock.lock()
        defer { hillLock.unlock() }
        let cacheKey = "\(season.rawValue)|\(key)"
        if let known = tintedHillCache[cacheKey] { return known }
        guard let source = base.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: source.width, height: source.height, bitsPerComponent: 8, bytesPerRow: 0, space: GardenDisplay.colorSpace(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        let box = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        context.draw(source, in: box)
        context.setBlendMode(.sourceAtop)
        context.setFillColor(color)
        context.fill(box)
        guard let made = context.makeImage() else { return nil }
        let image = NSImage(cgImage: made, size: NSSize(width: source.width, height: source.height))
        tintedHillCache[cacheKey] = image
        return image
    }

    private static func darkHillImage(_ season: Season) -> NSImage? {
        tintedHillImage(season, key: "buio", color: CGColor(red: 0.04, green: 0.06, blue: 0.14, alpha: 0.62))
    }

    private static func moodHillImage(_ season: Season, island: String) -> NSImage? {
        guard let wash = islandWash(island, season: season) else { return nil }
        return tintedHillImage(season, key: island, color: wash.cgColor)
    }

    /// L'immagine già decodificata, in un bitmap nello spazio dei colori dello schermo. Un'`NSImage` letta da un file PNG lo decodifica ad ogni disegno
    /// (era un terzo del tempo di ogni fotogramma mentre ci si sposta), e un bitmap già pronto si copia soltanto.
    private static func decoded(_ image: NSImage) -> NSImage? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: source.width, height: source.height, bitsPerComponent: 8, bytesPerRow: 0, space: GardenDisplay.colorSpace(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard let made = context.makeImage() else { return nil }
        return NSImage(cgImage: made, size: NSSize(width: source.width, height: source.height))
    }

    /// D'inverno: le dodici tessere con la neve e le otto del sentiero innevato (da `tools/cutout_tessere.py`); se ne manca una, la neve si disegna a mano.
    private static var snowImages: [NSImage]? = {
        let images = (1...GardenTerrain.grassCount).compactMap { index in
            GardenSprites.loadImage("giardino_tessera_neve_\(index)")
        }
        return images.count == GardenTerrain.grassCount ? images : nil
    }()

    private static var snowPathImages: [NSImage]? = {
        let images = (1...GardenTerrain.pathCount).compactMap { index in
            GardenSprites.loadImage("giardino_tessera_sentiero_neve_\(index)")
        }
        return images.count == GardenTerrain.pathCount ? images : nil
    }()

    /// Le tre strisce del bordo di terra (assets/giardino/bordo_<n>.png, da `tools/cutout_bordo.py`): 24 pixel d'erba sopra la linea e 110 di terra sotto.
    private static let edgeLip: CGFloat = 24, edgeBody: CGFloat = 110, edgeFade: CGFloat = 30
    private static func loadEdges(_ name: String) -> [NSImage]? {
        let images = (1...GardenTerrain.edgeCount).compactMap { index in
            GardenSprites.loadImage("\(name)_\(index)")
        }
        return images.count == GardenTerrain.edgeCount ? images : nil
    }

    /// Le stesse più scure, per il lato destro (quello all'ombra).
    private static func darkened(_ images: [NSImage]?) -> [NSImage]? {
        images?.map { source in
            NSImage(size: source.size, flipped: false) { box in
                source.draw(in: box)
                NSColor(calibratedWhite: 0, alpha: 0.24).set()
                box.fill(using: .sourceAtop)
                return true
            }
        }
    }

    private static var edgeImages: [NSImage]? = loadEdges("giardino_bordo")
    private static var darkEdgeImages: [NSImage]? = darkened(edgeImages)
    /// D'inverno: la neve sul bordo, i ghiaccioli, la terra fredda (stessa misura: 24 pixel sopra la linea e 110 sotto).
    private static var snowEdgeImages: [NSImage]? = loadEdges("giardino_bordo_neve")
    private static var darkSnowEdgeImages: [NSImage]? = darkened(snowEdgeImages)

    /// Mette il bordo di terra su un lato dell'isola, da `from` a `to` (la linea sale o scende di mezzo punto per ogni punto di larghezza): strisce di
    /// terra ripetute e sovrapposte (le estremità svaniscono), ognuna diversa dalla precedente e specchiata una volta ogni due; la linea dove comincia la terra sta sul bordo delle tessere.
    private static func drawEdgeStrip(from: NSPoint, to: NSPoint, face: Int, images: [NSImage], iso: Iso) {
        let scale = iso.edge / Self.edgeBody
        let lip = Self.edgeLip * scale
        let length = to.x - from.x
        let slope = (to.y - from.y) / length
        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath()
        clip.move(to: NSPoint(x: from.x, y: from.y - lip - 2)); clip.line(to: NSPoint(x: to.x, y: to.y - lip - 2))
        clip.line(to: NSPoint(x: to.x, y: to.y + iso.edge + 4)); clip.line(to: NSPoint(x: from.x, y: from.y + iso.edge + 4)); clip.close()
        clip.addClip()
        let shear = NSAffineTransform(transform: AffineTransform(m11: 1, m12: slope, m21: 0, m22: 1, tX: from.x, tY: from.y))
        shear.concat()
        var x: CGFloat = 0
        var index = 0
        let sequence = GardenTerrain.edgeSequence(face: face, count: 12)
        while x < length, index < sequence.count {
            let image = images[sequence[index]]
            let width = image.size.width * scale, height = image.size.height * scale
            let rect = NSRect(x: x, y: -lip, width: width, height: height)
            NSGraphicsContext.saveGraphicsState()
            if index % 2 == 1 {
                let flip = NSAffineTransform()
                flip.translateX(by: rect.midX, yBy: 0)
                flip.scaleX(by: -1, yBy: 1)
                flip.translateX(by: -rect.midX, yBy: 0)
                flip.concat()
            }
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            NSGraphicsContext.restoreGraphicsState()
            x += width - Self.edgeFade * scale
            index += 1
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// I ventiquattro dettagli da spargere (ciuffi, fiori, sassi, foglie, petali, neve).
    private static var decalImages: [NSImage]? = {
        let images = (1...GardenTerrain.decalCount).compactMap { index in
            GardenSprites.loadImage("giardino_dettaglio_\(index)")
        }
        return images.count == GardenTerrain.decalCount ? images : nil
    }()

    /// La disposizione delle tessere d'erba (o di neve) per ogni grandezza dell'isola, calcolata una volta: la chiave è la grandezza e se è inverno.
    /// I terreni si dipingono anche fuori dal thread principale (`prepareGrounds`): l'elenco ha il suo lucchetto.
    private static var grassGrids: [String: [Int]] = [:]
    private static let grassLock = NSLock()

    private static func grassGrid(size: Int, season: Season, tag: String) -> [Int] {
        grassLock.lock()
        defer { grassLock.unlock() }
        let key = "\(size)|\(season == .winter)|\(tag)"
        if let known = grassGrids[key] { return known }
        let grid = GardenTerrain.grassGrid(size: size, weights: GardenTerrain.grassWeights(season: season), tag: tag)
        grassGrids[key] = grid
        return grid
    }

    /// Disegna il terreno (ombra, lati, tessere); `carrying`: la griglia si vede di più mentre si trascina.
    private static func paintIslandGround(_ iso: Iso, season: Season, carrying: Bool, onHill: Bool? = nil, island: String = GardenIslands.fallbackHome) {
        let pal = Self.palette(season)
        let winter = season == .winter
        let tag = GardenIslands.terrainTag(island)
        let grassGrid = Self.grassGrid(size: iso.size, season: season, tag: tag)
        let pathTiles = GardenPaths.tiles(island: island, size: iso.size)
        let pathIndex = Dictionary(uniqueKeysWithValues: pathTiles.enumerated().map { ($1, $0) })
        let pathVariants = GardenTerrain.pathVariants(count: pathTiles.count, weights: GardenTerrain.pathWeights(season: season), tag: tag)
        let grassSet = winter ? Self.snowImages : Self.grassImages
        let pathSet = winter ? Self.snowPathImages : Self.pathImages
        let edgeSet = winter ? Self.snowEdgeImages : Self.edgeImages
        let darkEdgeSet = winter ? Self.darkSnowEdgeImages : Self.darkEdgeImages
        // con la collina il terreno finisce sul pendio: niente ombra a ellisse, niente lati di terra né strisce
        let onHill = onHill ?? Self.hasHill
        let n = Double(iso.size)
        let thickness = iso.edge
        // l'ombra sul prato, sotto l'isola
        let front = iso.point(col: n, row: n)
        let shadow = NSRect(x: iso.origin.x - iso.tileW * CGFloat(n) * 0.46, y: front.y - iso.tileH * 0.5, width: iso.tileW * CGFloat(n) * 0.92, height: iso.tileH * 1.6)
        if !onHill {
            (winter ? NSColor(calibratedRed: 0.16, green: 0.22, blue: 0.32, alpha: 0.16) : NSColor(calibratedRed: 0.16, green: 0.22, blue: 0.10, alpha: 0.16)).setFill()
            NSBezierPath(ovalIn: shadow).fill()
        }
        // i lati (a mano, se non ci sono le strisce disegnate; quelle si mettono dopo le tessere)
        let left = iso.point(col: 0, row: n), right = iso.point(col: n, row: 0)
        if edgeSet == nil && !onHill {
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
        }
        // le tessere
        for row in 0..<iso.size {
            for col in 0..<iso.size {
                let tile = GardenTile(col: col, row: row)
                let seed = GardenDrops.hash("\(col),\(row)")
                let variation = CGFloat(Int(seed % 11)) - 5
                let isPath = pathIndex[tile] != nil
                let base = isPath ? ((col + row) % 2 == 0 ? pal.pathA : pal.pathB) : ((col + row) % 2 == 0 ? pal.grassA : pal.grassB)
                let path = diamond(tile, iso: iso)
                // l'erba (o la neve) disegnata; se manca, a mano
                var grass: NSImage?
                if isPath, let index = pathIndex[tile] { grass = pathSet?[pathVariants[index]] }
                else if !isPath { grass = grassSet?[grassGrid[row * iso.size + col]] }
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
                    // il sentiero un po' più scuro del prato (con le tinte delle isole le sue pietre chiare si perdevano): d'inverno meno, sulla neve
                    if isPath {
                        NSGraphicsContext.saveGraphicsState()
                        NSGraphicsContext.current?.cgContext.setBlendMode(.multiply)
                        (winter ? Self.color(226, 228, 238) : Self.color(204, 188, 164)).setFill()
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
        // i lati di terra disegnati, sopra le tessere (i fili d'erba che sporgono coprono un po' il bordo)
        if !onHill, let edges = edgeSet, let dark = darkEdgeSet {
            drawEdgeStrip(from: left, to: front, face: 0, images: edges, iso: iso)
            drawEdgeStrip(from: front, to: right, face: 1, images: dark, iso: iso)
        }
        // i dettagli sparsi sul terreno (dal fondo al davanti)
        if let decals = Self.decalImages {
            var placed: [(depth: Double, tile: GardenTile, decal: GardenTerrain.Decal)] = []
            for row in 0..<iso.size {
                for col in 0..<iso.size {
                    let tile = GardenTile(col: col, row: row)
                    for decal in GardenTerrain.decals(col: col, row: row, season: season, onPath: pathIndex[tile] != nil, tag: tag) {
                        placed.append((Double(col + row) + decal.u + decal.v, tile, decal))
                    }
                }
            }
            placed.sort { $0.depth < $1.depth }
            for entry in placed {
                let image = decals[entry.decal.image]
                let point = iso.point(col: Double(entry.tile.col) + entry.decal.u, row: Double(entry.tile.row) + entry.decal.v)
                let width = CGFloat(entry.decal.size) * iso.tileW
                let height = width * image.size.height / image.size.width
                let rect = NSRect(x: point.x - width / 2, y: point.y - height * CGFloat(entry.decal.anchor), width: width, height: height)
                NSGraphicsContext.saveGraphicsState()
                if entry.decal.flipped {
                    let flip = NSAffineTransform()
                    flip.translateX(by: rect.midX, yBy: 0)
                    flip.scaleX(by: -1, yBy: 1)
                    flip.translateX(by: -rect.midX, yBy: 0)
                    flip.concat()
                }
                image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }

    private struct GroundCache {
        var key: String
        var image: CGImage
        var box: NSSize
        /// Dove sta, dentro l'immagine, il vertice in alto dell'isola.
        var origin: NSPoint
    }

    /// I terreni già dipinti, uno per isola, grandezza, tessera, stagione e schermo. Non dipendono da niente del giardino né dalla vista, quindi sono di tutti: li può
    /// dipingere in anticipo anche `prepareGrounds`, fuori dal thread principale. Un solo thread alla volta dipinge (chi aspetta trova il lavoro fatto).
    private static var groundStore: [String: GroundCache] = [:]
    private static let groundLock = NSLock()

    /// La scena fissa (paesaggio, collina, terreno, luce) già pronta, ma **più grande della finestra**: per spostarsi basta mostrarne un pezzo diverso (una copia), senza
    /// ridisegnare niente; si rifà solo quando ci si avvicina al bordo, cambia qualcosa (l'isola, la stagione, la luce, la griglia) o, dopo uno zoom, quando il gesto finisce.
    private struct SceneCache {
        var id: Int
        var key: String
        var image: CGImage
        /// La telecamera com'era quando si è preparata.
        var zoom: CGFloat
        var pan: NSPoint
        /// Quanto è più grande della finestra, da ogni lato.
        var margin: NSSize
    }
    private var sceneCache: SceneCache?
    /// Gli angoli scuri del paesaggio e la notte: stanno fermi sulla finestra (non si spostano col mondo), quindi vanno a parte.
    private var overlayCache: (key: String, image: CGImage)?
    /// Se la vista sta ferma (due disegni di seguito uguali), la finestra intera già composta (scena e angoli scuri), da copiare: costa meno che sovrapporre ogni volta.
    private var stillCache: (key: String, image: CGImage)?
    private var lastPlacement = ""
    private var sceneCounter = 0
    private var settleTimer: Timer?
    private static let sceneMargin = NSSize(width: 300, height: 180)

    private func newContext(width: CGFloat, height: CGFloat, scale: CGFloat, space: CGColorSpace) -> CGContext? {
        CGContext(data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    }

    /// Dove cade adesso la scena preparata (la vista può essere cambiata, di `pan` e di `zoom`, da quando si è preparata), se è ancora identica (solo spostata) e se copre
    /// tutta la finestra.
    private func placement(of cache: SceneCache) -> (rect: NSRect, exact: Bool, covers: Bool) {
        let ratio = zoom / cache.zoom
        let center = NSPoint(x: sceneW / 2, y: sceneH / 2)
        let width = (sceneW + 2 * cache.margin.width) * ratio, height = (sceneH + 2 * cache.margin.height) * ratio
        var origin = NSPoint(x: center.x + (-cache.margin.width - center.x) * ratio + pan.x - cache.pan.x * ratio,
                             y: center.y + (-cache.margin.height - center.y) * ratio + pan.y - cache.pan.y * ratio)
        let exact = abs(ratio - 1) < 0.0005
        if exact {
            // a pixel interi: la copia resta nitida
            let scale = backingScale
            origin = NSPoint(x: (origin.x * scale).rounded() / scale, y: (origin.y * scale).rounded() / scale)
        }
        let rect = NSRect(origin: origin, size: NSSize(width: width, height: height))
        let covers = rect.minX <= 0.5 && rect.minY <= 0.5 && rect.maxX >= sceneW - 0.5 && rect.maxY >= sceneH - 0.5
        return (rect, exact, covers)
    }

    /// Dopo uno zoom la scena si rifà nitida: quando il gesto è finito (nessun cambio per un attimo).
    private func scheduleSettle() {
        settleTimer?.invalidate()
        settleTimer = Timer.scheduledTimer(withTimeInterval: 0.14, repeats: false) { [weak self] _ in
            self?.sceneCache = nil
            self?.needsDisplay = true
        }
    }

    /// Il paesaggio, la collina, il terreno e la luce, in un'immagine grande quanto la finestra più i margini, con la vista di adesso.
    private func renderScene(_ iso: Iso, season: Season, light: GardenLight, key: String, space: CGColorSpace) -> SceneCache? {
        let scale = backingScale
        let margin = Self.sceneMargin
        let width = sceneW + 2 * margin.width, height = sceneH + 2 * margin.height
        guard let cg = newContext(width: width, height: height, scale: scale, space: space) else { return nil }
        cg.scaleBy(x: scale, y: -scale)
        cg.translateBy(x: 0, y: -height)
        cg.translateBy(x: margin.width, y: margin.height)           // da qui le coordinate sono quelle della finestra, e la scena si estende oltre
        let area = NSRect(x: -margin.width, y: -margin.height, width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        NSGraphicsContext.current?.imageInterpolation = .high
        drawBackdrop(fill: area, season: season)
        let islands = worldIslands()
        for entry in islands { drawHill(entry.iso, season: season, visible: area, dark: !entry.open, island: entry.id) }       // tutte le colline prima: le isole le coprono
        for entry in islands {
            drawIslandGround(entry.iso, season: season, island: entry.id)
            if !entry.open {
                NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.14, alpha: 0.66).setFill()
                islandOutline(entry.iso).fill()
            }
        }
        for entry in islands { drawLandmark(island: entry.id, iso: entry.iso, open: entry.open) }       // le case, dopo i terreni (il tetto esce sopra l'isola)
        drawBridges(islands)
        applyLight(light, in: area)
        NSGraphicsContext.restoreGraphicsState()
        guard let image = cg.makeImage() else { return nil }
        sceneCounter += 1
        return SceneCache(id: sceneCounter, key: key, image: image, zoom: zoom, pan: pan, margin: margin)
    }

    /// Gli angoli scuri del paesaggio e il buio della notte (a parte: stanno fermi sulla finestra), già pronti per stagione e luce.
    private func overlayKey(season: Season, light: GardenLight, space: CGColorSpace) -> String {
        "\(season.rawValue)|\(Int(light.darkness * 40))|\(backingScale)|\(GardenDisplay.name(space))"
    }

    private func drawOverlay(season: Season, light: GardenLight, space: CGColorSpace) {
        let scale = backingScale
        let key = overlayKey(season: season, light: light, space: space)
        if overlayCache?.key != key {
            overlayCache = nil
            if let cg = newContext(width: sceneW, height: sceneH, scale: scale, space: space) {
                cg.scaleBy(x: scale, y: -scale)
                cg.translateBy(x: 0, y: -sceneH)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
                MeadowBackdrop.drawVignette(in: sceneRect, season: season)
                nightVeil(light)
                NSGraphicsContext.restoreGraphicsState()
                if let image = cg.makeImage() { overlayCache = (key, image) }
            }
        }
        if let overlay = overlayCache?.image {
            GardenBlit.draw(overlay, in: sceneRect)
        } else {
            MeadowBackdrop.drawVignette(in: sceneRect, season: season)
            nightVeil(light)
        }
    }

    private func drawStaticScene(_ iso: Iso, season: Season, light: GardenLight) {
        let scale = backingScale
        let space = GardenDisplay.colorSpace(window)
        let carrying = carry != nil && carryMoved
        let tint = GardenTint(multiplier: light.multiplier)
        let key = "\(worldSignature())|\(season.rawValue)|\(carrying)|\(scale)|\(GardenDisplay.name(space))|" + "\(tint.red),\(tint.green),\(tint.blue),\(Int(light.darkness * 40))"
        if let cache = sceneCache, cache.key == key {
            let now = placement(of: cache)
            if now.covers {
                if now.exact {
                    // la vista sta ferma (lo stesso disegno due volte di seguito): la finestra già composta, una copia sola
                    let still = "\(cache.id)|\(Int(now.rect.minX * backingScale)),\(Int(now.rect.minY * backingScale))|" + overlayKey(season: season, light: light, space: space)
                    if still == lastPlacement {
                        if stillCache?.key != still, let cg = newContext(width: sceneW, height: sceneH, scale: scale, space: space) {
                            cg.scaleBy(x: scale, y: -scale)
                            cg.translateBy(x: 0, y: -sceneH)
                            NSGraphicsContext.saveGraphicsState()
                            NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
                            GardenBlit.draw(cache.image, in: now.rect, copy: true)
                            drawOverlay(season: season, light: light, space: space)
                            NSGraphicsContext.restoreGraphicsState()
                            if let image = cg.makeImage() { stillCache = (still, image) }
                        }
                        if let composed = stillCache, composed.key == still {
                            GardenBlit.draw(composed.image, in: sceneRect, copy: true)
                            return
                        }
                    }
                    lastPlacement = still
                } else {
                    lastPlacement = ""
                }
                // identica e solo spostata: una copia; con lo zoom in corso: la stessa scena ingrandita (meno nitida), e si rifà appena il gesto finisce
                GardenBlit.draw(cache.image, in: now.rect, copy: true, quality: now.exact ? .none : .low)
                if !now.exact { scheduleSettle() }
                drawOverlay(season: season, light: light, space: space)
                return
            }
        }
        settleTimer?.invalidate()
        lastPlacement = ""
        sceneCache = renderScene(iso, season: season, light: light, key: key, space: space)
        if let cache = sceneCache {
            GardenBlit.draw(cache.image, in: placement(of: cache).rect, copy: true)
        } else {
            drawBackdrop(fill: sceneRect, season: season)
            drawHill(iso, season: season, visible: sceneRect)
            drawIslandGround(iso, season: season, island: garden.shownIsland)
            applyLight(light, in: sceneRect)
        }
        drawOverlay(season: season, light: light, space: space)
    }

    /// La collina sotto l'isola: l'ombra e la nebbia sul prato, e l'immagine d'erba con il buco a rombo dove stanno le tessere (l'isola ne copre il bordo,
    /// quindi fra le tessere e il pendio non c'è nessun distacco). Si disegna direttamente nella scena già pronta: la scena è un'immagine sola, e l'immagine
    /// della collina (tanto più grande dell'isola) in una cache a parte, ingrandendo, peserebbe troppo.
    private func drawHill(_ iso: Iso, season: Season, visible: NSRect, dark: Bool = false, island: String = "") {
        guard let image = dark ? (Self.darkHillImage(season) ?? Self.hillImage(season)) : (Self.moodHillImage(season, island: island) ?? Self.hillImage(season)) else { return }
        let n = Double(iso.size)
        let left = iso.point(col: 0, row: n), right = iso.point(col: n, row: 0)
        let frame = GardenHill.frame(islandLeft: (Double(left.x), Double(left.y)), islandRight: (Double(right.x), Double(right.y)))
        let rect = NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
        guard rect.intersects(visible) else { return }
        let k = CGFloat(frame.scale) / 1.385          // le misure di nebbia e ombra sono state provate con la collina a questa scala
        // l'ombra morbida sul prato, sotto la base
        let baseY = rect.maxY
        NSGraphicsContext.saveGraphicsState()
        let shadowTone = season == .winter ? Self.color(88, 100, 128) : Self.color(60, 52, 30)
        let squash = NSAffineTransform()
        squash.translateX(by: rect.midX, yBy: baseY - 26 * k)
        squash.scaleX(by: 1, yBy: 0.16)
        squash.concat()
        NSGradient(colors: [shadowTone.withAlphaComponent(0.30), shadowTone.withAlphaComponent(0.16), shadowTone.withAlphaComponent(0)])?
            .draw(fromCenter: .zero, radius: 0, toCenter: .zero, radius: rect.width * 0.46, options: [])
        NSGraphicsContext.restoreGraphicsState()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.low])
        // la nebbia alla base (la collina si perde nel lago)
        let mist = season == .winter ? Self.color(232, 238, 248) : Self.color(240, 236, 224)
        for (fx, fy, width, height, alpha) in [(0.26, -26.0, 150.0, 18.0, 0.34), (0.50, -8.0, 220.0, 24.0, 0.40), (0.74, -26.0, 150.0, 18.0, 0.34)] {
            NSGraphicsContext.saveGraphicsState()
            let t = NSAffineTransform()
            t.translateX(by: rect.minX + CGFloat(fx) * rect.width, yBy: baseY + CGFloat(fy) * k)
            t.scaleX(by: 1, yBy: CGFloat(height / width))
            t.concat()
            NSGradient(colors: [mist.withAlphaComponent(CGFloat(alpha)), mist.withAlphaComponent(CGFloat(alpha) * 0.5), mist.withAlphaComponent(0)])?
                .draw(fromCenter: .zero, radius: 0, toCenter: .zero, radius: CGFloat(width) * k * 1.3, options: [])
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// La tinta con cui si disegnano oggetti e compagni in questo momento (la luce è già dentro lo sfondo e il terreno).
    private var currentTint = GardenTint.none
    /// La stagione del disegno in corso (l'ombra sotto le cose è verde sul prato e azzurra sulla neve).
    private var currentSeason = Season.spring

    /// Il terreno, da un disegno già pronto (solo il rettangolo che lo contiene) finché non cambia niente tranne la posizione: spostarsi non lo rifà,
    /// lo sposta soltanto. Si rifà con l'isola, lo zoom, la stagione o la griglia che si accende. Disegnare le tessere ad ogni fotogramma costerebbe
    /// molto di più che copiare un'immagine.
    private func drawIslandGround(_ iso: Iso, season: Season, island: String) {
        let carrying = carry != nil && carryMoved
        if let cached = Self.ground(iso, island: island, season: season, carrying: carrying, scale: backingScale, space: GardenDisplay.colorSpace(window)) {
            let target = NSRect(x: iso.origin.x - cached.origin.x, y: iso.origin.y - cached.origin.y, width: cached.box.width, height: cached.box.height)
            GardenBlit.draw(cached.image, in: target)
        } else {
            Self.paintIslandGround(iso, season: season, carrying: carrying, island: island)
        }
    }

    /// Il terreno dipinto per questa isola, grandezza, tessera, stagione e schermo (lo dipinge, se manca).
    private static func ground(_ iso: Iso, island: String, season: Season, carrying: Bool, scale: CGFloat, space: CGColorSpace) -> GroundCache? {
        groundLock.lock()
        defer { groundLock.unlock() }
        let key = "\(island)|\(iso.size)|\(Int(iso.tileW * 100))|\(season.rawValue)|\(carrying)|\(scale)|\(GardenDisplay.name(space))"
        if let known = groundStore[key] { return known }
        let n = CGFloat(iso.size)
        let margin: CGFloat = 40
        let top = iso.tileW * 0.6 + 20
        let box = NSSize(width: n * iso.tileW + 2 * margin, height: n * iso.tileH + iso.edge + top + margin)
        let origin = NSPoint(x: box.width / 2, y: top)
        guard let cg = CGContext(data: nil, width: Int(box.width * scale), height: Int(box.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                 space: space,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        cg.scaleBy(x: scale, y: -scale)
        cg.translateBy(x: 0, y: -box.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        NSGraphicsContext.current?.imageInterpolation = .high
        paintIslandGround(Iso(size: iso.size, tileW: iso.tileW, origin: origin), season: season, carrying: carrying, island: island)
        // la tinta dell'isola, solo dove il terreno c'è
        if let wash = islandWash(island, season: season) {
            cg.setBlendMode(.sourceAtop)
            cg.setFillColor(wash.cgColor)
            cg.fill(CGRect(origin: .zero, size: box))
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let image = cg.makeImage() else { return nil }
        if groundStore.count >= 8 { groundStore.removeAll() }
        let made = GroundCache(key: key, image: image, box: box, origin: origin)
        groundStore[key] = made
        return made
    }

    /// I terreni di tutte le isole com'è la prima vista del giardino, dipinti in anticipo: quel disegno era la metà del tempo del primo ingresso. Si chiama nel
    /// thread principale (legge il giardino, che non è fatto per gli altri thread); il lavoro lo fa uno sfondo.
    static func prepareGrounds(garden: Garden) {
        let sizes = GardenIslands.all.map { (island: $0, size: garden.islandSize(of: $0)) }
        let tileW = baseTileW * islandZoom(size: garden.islandSize(of: garden.shownIsland))
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let space = GardenDisplay.colorSpace()
        let season = Season.of(Date())
        DispatchQueue.global(qos: .utility).async {
            for entry in sizes {
                _ = ground(Iso(size: entry.size, tileW: tileW, origin: .zero), island: entry.island, season: season, carrying: false, scale: scale, space: space)
            }
        }
    }

    /// Dove cadrebbe quello che si trascina: tessere verdi se ci sta, rosse se no.
    private func drawHighlight(_ highlight: CarryTarget?, iso: Iso) {
        guard let highlight else { return }
        let good = highlight.valid
        for tile in highlight.tiles where GardenIsland.contains(tile, size: iso.size) {
            let path = Self.diamond(tile, iso: iso, inset: 2)
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
            (currentSeason == .winter ? NSColor(calibratedRed: 0.30, green: 0.38, blue: 0.52, alpha: 0.22 * alpha)
                                      : NSColor(calibratedRed: 0.24, green: 0.32, blue: 0.20, alpha: 0.28 * alpha)).setFill()
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
        } else if let scaled = GardenSprites.scaled(entity.sprite, resource: entity.resource, pixelWidth: max(1, Int((rect.width * backingScale).rounded())),
                                                    pixelHeight: max(1, Int((rect.height * backingScale).rounded())), tint: currentTint) {
            GardenBlit.draw(scaled, in: rect, alpha: alpha)
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

    private func drawHint(_ string: String, y: CGFloat? = nil) {
        let width: CGFloat = 520
        let rect = NSRect(x: (sceneW - width) / 2, y: y ?? sceneH - 50 - (trayVisible ? Self.trayHeight : 0), width: width, height: 34)
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

    private func flash(_ string: String, seconds: TimeInterval = 4) {
        message = string
        messageTimer?.invalidate()
        messageTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
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
        if captionRect.contains(p) {
            toggleWorldView()
            return
        }
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
        touchIsland(at: p)
        guard sceneRect.contains(p), let found = entity(at: p) else {
            // sullo sfondo: due tocchi ingrandiscono (o, già ingrandita, rimettono tutta l'isola), trascinando ci si sposta
            if event.clickCount == 2 {
                if !isFitted() && zoom > islandCamera(garden.shownIsland).zoom * 1.05 { resetCamera() } else { zoom(by: 1.8, at: p) }
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
        case .visitor:
            // un ospite non si sposta: si saluta
            greetVisitor()
            needsDisplay = true
            return
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
            if !isCarryingCompanion, let id = islandUnder(p), id != garden.shownIsland, isIslandOpen(id) { focus(id) }
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
                    garden.move(id, to: target.origin, turned: carryTurned, on: garden.shownIsland)
                } else if sceneRect.contains(p) {
                    flash(wrongIslandLine(for: garden.placement(withID: id)?.item) ?? "Lì non ci sta: serve una tessera libera, fuori dal sentiero.")
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
                if let line = wrongIslandLine(for: id) {
                    flash(line)
                } else if garden.placeSomewhere(id) == nil {
                    flash("Non c'è più posto sull'isola: togli qualcosa, o completa una doppia pagina dell'album per allargarla.")
                }
            } else if let target, target.valid {
                garden.place(id, at: target.origin, turned: carryTurned)
            } else if sceneRect.contains(p), !overTray {
                flash(wrongIslandLine(for: id) ?? "Lì non ci sta: serve una tessera libera, fuori dal sentiero.")
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

// MARK: - Gli angoli: le stelline dello sblocco e quello che succede quando si formano

extension GardenView {
    /// I colori degli effetti stanno sopra la scena, che è già tinta dalla luce: si tingono come i petali.
    private func lit(_ color: NSColor, _ light: GardenLight) -> NSColor {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return color }
        let m = light.multiplier
        return NSColor(calibratedRed: rgb.redComponent * CGFloat(m.red / 255), green: rgb.greenComponent * CGFloat(m.green / 255),
                       blue: rgb.blueComponent * CGFloat(m.blue / 255), alpha: rgb.alphaComponent)
    }

    /// Una lettera o un simbolo (la «z» del sonno, un cuore, una nota) che si disegna centrato su un punto e girato di `angle`.
    private func drawGlyph(_ glyph: String, at point: NSPoint, size: CGFloat, color: NSColor, angle: CGFloat = 0) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: .heavy), .foregroundColor: color]
        let extent = (glyph as NSString).size(withAttributes: attributes)
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: point.x, yBy: point.y)
        transform.rotate(byRadians: angle)
        transform.concat()
        (glyph as NSString).draw(at: NSPoint(x: -extent.width / 2, y: -extent.height / 2), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Quello che gli angoli formati fanno nel giardino: vapore dal tavolino, gocce dall'annaffiatoio, «z» sulla casa del gatto, cuori su quella del
    /// porcellino, note sulla casa degli uccelli, farfalle sul prato fiorito, lucciole e nebbia nel bosco, coriandoli alla festa, petali di rosa e luce
    /// rosata sotto l'arco. Niente di tutto questo si vede con «Riduci movimento» (la luce più forte del lampione di lettura sì).
    private func drawCornerEffects(_ laid: [Entity], season: Season, light: GardenLight, iso: Iso) {
        guard !reduceMotion, !garden.formedCorners.isEmpty else { return }
        let time = effectsClock()
        var itemOf: [UUID: String] = [:]
        for placement in garden.placements { itemOf[placement.id] = placement.item }
        /// La copia di `item` che fa parte dell'angolo `corner`, se c'è.
        func member(_ corner: String, _ item: String) -> Entity? {
            guard let ids = garden.formedCorners[corner] else { return nil }
            for entity in laid {
                if case .placed(let id) = entity.kind, ids.contains(id), itemOf[id] == item { return entity }
            }
            return nil
        }
        /// Dove stanno, in media, i piedi delle cose di un angolo.
        func center(_ corner: String) -> NSPoint? {
            guard let ids = garden.formedCorners[corner] else { return nil }
            var feet: [NSPoint] = []
            for entity in laid {
                if case .placed(let id) = entity.kind, ids.contains(id) { feet.append(entity.feet) }
            }
            guard !feet.isEmpty else { return nil }
            let count = CGFloat(feet.count)
            return NSPoint(x: feet.reduce(0) { $0 + $1.x } / count, y: feet.reduce(0) { $0 + $1.y } / count)
        }
        let tileW = iso.tileW, tileH = iso.tileH
        let white = lit(NSColor.white, light)
        let steamColor = lit(Self.color(188, 196, 214), light)

        // il tè: un filo di vapore dal tavolino
        if let table = member("te", "tavolino") {
            let origin = NSPoint(x: table.rect.midX - table.rect.width * 0.06, y: table.rect.minY + table.rect.height * 0.30)
            let k = tileW / 185
            for index in 0..<4 {
                let puff = GardenSky.smoke(index: index * 2, time: time, wind: 0.15)
                let alpha = CGFloat(puff.alpha) * 0.9
                guard alpha > 0.01 else { continue }
                let c = NSPoint(x: origin.x + CGFloat(puff.dx) * k, y: origin.y + CGFloat(puff.dy) * k)
                NSGradient(colors: [steamColor.withAlphaComponent(min(alpha * 1.5, 0.85)), steamColor.withAlphaComponent(alpha * 0.7), steamColor.withAlphaComponent(0)])?
                    .draw(fromCenter: c, radius: 0, toCenter: c, radius: CGFloat(puff.radius) * 2.1 * k, options: [])
            }
        }
        // l'orto: le gocce dell'annaffiatoio
        if let can = member("orto", "annaffiatoio") {
            let origin = NSPoint(x: can.rect.minX + can.rect.width * 0.12, y: can.rect.minY + can.rect.height * 0.42)
            let drop = lit(Self.color(150, 200, 238), light)
            for index in 0..<3 {
                let d = GardenSky.drift(index: index, time: time, period: 1.1)
                drop.withAlphaComponent(CGFloat(d.alpha) * 0.9).setFill()
                let c = NSPoint(x: origin.x + CGFloat(d.x) * tileW * 0.05, y: origin.y + CGFloat(d.progress) * tileH * 1.1)
                NSBezierPath(ovalIn: NSRect(x: c.x - 1.6, y: c.y - 2.8, width: 3.2, height: 5.6)).fill()
            }
        }
        // il gatto dorme, il porcellino è contento, gli uccelli cantano: una «z», un cuore, una nota che salgono dalla loro casa
        let risers: [(corner: String, item: String, glyph: String, color: NSColor, period: Double)] = [
            ("gatto", "casetta-gatto", "z", Self.color(110, 130, 190), 3.2),
            ("porcellino", "casetta-porcellino", "♥", Self.color(238, 118, 150), 3.6),
            ("uccelli", "casetta-uccelli", "♪", Self.color(96, 150, 205), 3.0),
        ]
        for riser in risers {
            guard let house = member(riser.corner, riser.item) else { continue }
            let origin = NSPoint(x: house.rect.midX + house.rect.width * 0.06, y: house.rect.minY + house.rect.height * 0.30)
            for index in 0..<2 {
                let d = GardenSky.drift(index: index + 3, time: time, period: riser.period)
                let c = NSPoint(x: origin.x + CGFloat(d.x) * tileW * 0.12, y: origin.y - CGFloat(d.progress) * tileH * 1.0)
                drawGlyph(riser.glyph, at: c, size: 11 + CGFloat(d.progress) * 6, color: lit(riser.color, light).withAlphaComponent(CGFloat(d.alpha) * 0.9),
                          angle: CGFloat(sin(d.spin)) * 0.25)
            }
        }
        // il prato fiorito: le farfalle (non d'inverno)
        if season != .winter, let middle = center("prato-fiorito") {
            let colors = [Self.color(240, 150, 60), Self.color(120, 170, 232), Self.color(240, 140, 186)]
            for index in 0..<3 {
                let b = GardenSky.butterfly(index: index, time: time)
                let c = NSPoint(x: middle.x + CGFloat(b.x) * tileW * 0.95, y: middle.y - tileH * 1.1 + CGFloat(b.y) * tileH * 0.9)
                let wing = tileW * 0.06
                let spread = 0.25 + CGFloat(b.flap) * 0.75
                lit(colors[index], light).setFill()
                NSBezierPath(ovalIn: NSRect(x: c.x - wing * 1.9 * spread, y: c.y - wing, width: wing * 1.9 * spread, height: wing * 1.6)).fill()
                NSBezierPath(ovalIn: NSRect(x: c.x, y: c.y - wing, width: wing * 1.9 * spread, height: wing * 1.6)).fill()
                lit(Self.color(70, 52, 44), light).setFill()
                NSBezierPath(ovalIn: NSRect(x: c.x - 0.7, y: c.y - wing * 0.9, width: 1.4, height: wing * 1.9)).fill()
            }
        }
        // il bosco: la nebbia di giorno, le lucciole la sera (non d'inverno)
        if let middle = center("bosco") {
            if light.lamp < 0.5 {
                let drift = CGFloat(sin(time * 0.12)) * tileW * 0.3
                for layer in 0..<2 {
                    let c = NSPoint(x: middle.x + drift * (layer == 0 ? 1 : -0.7), y: middle.y - tileH * (0.25 + CGFloat(layer) * 0.3))
                    let alpha = (0.17 + 0.05 * CGFloat(sin(time * 0.3 + Double(layer)))) * (1 - CGFloat(light.lamp) * 2)
                    NSGraphicsContext.saveGraphicsState()
                    let squash = NSAffineTransform()
                    squash.translateX(by: c.x, yBy: c.y)
                    squash.scaleX(by: 1, yBy: 0.38)
                    squash.concat()
                    NSGradient(colors: [white.withAlphaComponent(alpha), white.withAlphaComponent(0)])?
                        .draw(fromCenter: .zero, radius: 0, toCenter: .zero, radius: tileW * 1.4, options: [])
                    NSGraphicsContext.restoreGraphicsState()
                }
            }
            let evening = CGFloat(GardenSky.smoothstep(light.darkness, from: 0.2, to: 0.45))
            if season != .winter, evening > 0.01 {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.cgContext.setBlendMode(.plusLighter)
                let glowColor = Self.color(255, 238, 140), core = Self.color(255, 252, 210)
                for index in 0..<6 {
                    let f = GardenSky.cornerFirefly(index: index, time: time)
                    let a = CGFloat(f.glow) * evening
                    guard a > 0.02 else { continue }
                    let c = NSPoint(x: middle.x + CGFloat(f.x) * tileW * 1.0, y: middle.y - tileH * 0.9 + CGFloat(f.y) * tileH * 1.1)
                    NSGradient(colors: [glowColor.withAlphaComponent(0.85 * a), glowColor.withAlphaComponent(0)])?
                        .draw(fromCenter: c, radius: 0, toCenter: c, radius: 10, options: [])
                    core.withAlphaComponent(min(1, a * 1.3)).setFill()
                    NSBezierPath(ovalIn: NSRect(x: c.x - 1.4, y: c.y - 1.4, width: 2.8, height: 2.8)).fill()
                }
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        // la festa: i coriandoli che cadono dalle bandierine
        if let flags = member("festa", "bandierine") {
            let colors = [Self.color(240, 128, 160), Self.color(250, 205, 80), Self.color(110, 170, 235), Self.color(130, 200, 140), Self.color(242, 160, 80), Self.color(170, 130, 220)]
            let origin = NSPoint(x: flags.rect.midX, y: flags.rect.minY + flags.rect.height * 0.22)
            for index in 0..<6 {
                let d = GardenSky.drift(index: index + 10, time: time, period: 3)
                let c = NSPoint(x: origin.x + CGFloat(d.x) * flags.rect.width * 0.45, y: origin.y + CGFloat(d.progress) * tileH * 1.7)
                NSGraphicsContext.saveGraphicsState()
                let turn = NSAffineTransform()
                turn.translateX(by: c.x, yBy: c.y)
                turn.rotate(byRadians: CGFloat(d.spin))
                turn.concat()
                lit(colors[index], light).withAlphaComponent(CGFloat(d.alpha)).setFill()
                NSBezierPath(rect: NSRect(x: -2, y: -3.2, width: 4, height: 6.4)).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        // l'arco delle rose: i petali che cadono e, di sera, una luce rosata
        if let arch = member("rose", "arco-rose") {
            let origin = NSPoint(x: arch.rect.midX, y: arch.rect.minY + arch.rect.height * 0.20)
            for index in 0..<5 {
                let d = GardenSky.drift(index: index + 20, time: time, period: 4.2)
                let c = NSPoint(x: origin.x + CGFloat(d.x) * arch.rect.width * 0.32, y: origin.y + CGFloat(d.progress) * arch.rect.height * 0.8)
                NSGraphicsContext.saveGraphicsState()
                let turn = NSAffineTransform()
                turn.translateX(by: c.x, yBy: c.y)
                turn.rotate(byRadians: CGFloat(d.spin))
                turn.concat()
                lit(Self.color(246, 150, 178), light).withAlphaComponent(CGFloat(d.alpha) * 0.95).setFill()
                NSBezierPath(ovalIn: NSRect(x: -3.2, y: -2.1, width: 6.4, height: 4.2)).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            let glow = CGFloat(light.lamp)
            if glow > 0.02 {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.cgContext.setBlendMode(.plusLighter)
                let c = NSPoint(x: arch.rect.midX, y: arch.rect.minY + arch.rect.height * 0.45)
                let pink = Self.color(255, 150, 186)
                NSGradient(colors: [pink.withAlphaComponent(0.26 * glow), pink.withAlphaComponent(0)])?
                    .draw(fromCenter: c, radius: 0, toCenter: c, radius: tileW * 0.95, options: [])
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }

    /// Una stella a cinque punte centrata su `center`, con una punta in alto girata di `angle`.
    private func starPath(center: NSPoint, outer: CGFloat, angle: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        for point in 0..<10 {
            let radius = point % 2 == 0 ? outer : outer * 0.45
            let a = angle - .pi / 2 + CGFloat(point) * .pi / 5
            let p = NSPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius)
            if point == 0 { path.move(to: p) } else { path.line(to: p) }
        }
        path.close()
        return path
    }

    /// Lo sblocco di un angolo: le stelline escono dal centro e in alto compare «Hai sbloccato «L'angolo del tè»». Uno alla volta, se ce ne sono più d'uno.
    /// Con «Riduci movimento» le stelline stanno ferme attorno all'angolo e compaiono e svaniscono piano.
    private func drawCelebration(_ laid: [Entity], iso: Iso) {
        guard let current = celebrations.first else { return }
        let now = effectsClock()
        if current.start == nil { celebrations[0].start = now }
        let elapsed = now - (current.start ?? now)
        if elapsed >= Self.celebrationLength {
            celebrations.removeFirst()
            return
        }
        let enter = min(max(elapsed / 0.35, 0), 1), leave = min(max((Self.celebrationLength - elapsed) / 0.6, 0), 1)
        let envelope = CGFloat(min(enter, leave))

        // dove stanno le cose dell'angolo
        let members = Set(current.members)
        var xs: [CGFloat] = [], ys: [CGFloat] = []
        for entity in laid {
            if case .placed(let id) = entity.kind, members.contains(id) {
                xs.append(entity.rect.midX)
                ys.append(entity.rect.midY)
            } else if case .visitor(let species) = entity.kind, species == current.visitor {
                xs.append(entity.rect.midX)
                ys.append(entity.rect.midY)
            }
        }
        let middle: NSPoint
        if xs.isEmpty {
            middle = iso.point(col: Double(garden.islandSize) / 2, row: Double(garden.islandSize) / 2)
        } else {
            middle = NSPoint(x: xs.reduce(0, +) / CGFloat(xs.count), y: ys.reduce(0, +) / CGFloat(ys.count))
        }

        // le stelline
        let burstLength = 2.8
        let progress = reduceMotion ? 0.55 : min(elapsed / burstLength, 1)
        let gold = Self.color(255, 208, 70), edge = Self.color(226, 140, 28), pale = Self.color(255, 240, 170)
        if !reduceMotion, progress < 1 {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.setBlendMode(.plusLighter)
            let pulse = CGFloat(sin(progress * .pi))
            NSGradient(colors: [pale.withAlphaComponent(0.55 * pulse), pale.withAlphaComponent(0)])?
                .draw(fromCenter: middle, radius: 0, toCenter: middle, radius: iso.tileW * 1.1, options: [])
            NSGraphicsContext.restoreGraphicsState()
        }
        for index in 0..<GardenSky.burstStarCount {
            let star = GardenSky.burstStar(index: index, progress: progress)
            let alpha = CGFloat(star.alpha) * (reduceMotion ? envelope : 1)
            guard alpha > 0.01 else { continue }
            let path = starPath(center: NSPoint(x: middle.x + CGFloat(star.dx), y: middle.y + CGFloat(star.dy)), outer: CGFloat(star.size), angle: CGFloat(star.angle))
            (index % 3 == 0 ? pale : gold).withAlphaComponent(alpha).setFill()
            path.fill()
            edge.withAlphaComponent(alpha * 0.9).setStroke()
            path.lineWidth = 0.9
            path.stroke()
        }

        // la scritta, nello spazio libero in alto (fra «Menu» e le pillole dell'album e della serie)
        let caption = current.caption, title = current.title
        let titleWidth = ceil((title as NSString).size(withAttributes: [.font: numberFont]).width)
        let captionWidth = ceil((caption as NSString).size(withAttributes: [.font: smallFont]).width)
        let iconWidth: CGFloat = 22
        let width = 16 + iconWidth + 8 + max(titleWidth, captionWidth) + 20
        let hud = hudLayout()
        let freeRight = (hud.streak?.minX ?? hud.album.minX) - 12
        let centerX = (150 + freeRight) / 2
        let rect = NSRect(x: centerX - width / 2, y: 10 + (1 - enter) * -14, width: width, height: 50)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.18 * envelope)
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()
        drawChip(rect, fill: NSColor(calibratedRed: 1, green: 0.985, blue: 0.9, alpha: 0.97 * envelope), stroke: edge.withAlphaComponent(0.85 * envelope))
        NSGraphicsContext.restoreGraphicsState()
        if let icon = tinted("star.fill", size: 17, color: edge) {
            // l'icona si fa col colore pieno e poi si sfuma: colorata con un colore trasparente lascerebbe vedere il nero del simbolo
            icon.draw(in: NSRect(x: rect.minX + 16, y: rect.midY - icon.size.height / 2, width: icon.size.width, height: icon.size.height),
                      from: .zero, operation: .sourceOver, fraction: envelope, respectFlipped: true, hints: nil)
        }
        text(caption, in: NSRect(x: rect.minX + 16 + iconWidth + 8, y: rect.minY + 7, width: max(titleWidth, captionWidth) + 4, height: 15),
             font: smallFont, color: Paper.inkLight.withAlphaComponent(envelope))
        text(title, in: NSRect(x: rect.minX + 16 + iconWidth + 8, y: rect.minY + 21, width: max(titleWidth, captionWidth) + 6, height: 24),
             font: numberFont, color: Paper.ink.withAlphaComponent(envelope))
    }
}

// MARK: - Gli ospiti

extension GardenView {
    /// Riparte da capo con gli ospiti (si chiama quando si riapre la finestra): in questa fascia della giornata viene di nuovo lo stesso.
    func resetVisitors() {
        visitor = nil
        visitedSlots = []
        visitorClock = 0
        visitorCheck = 0
    }

    /// Fa avanzare l'ospite (se c'è) e, se non c'è, ogni tanto guarda se in questa fascia della giornata ne viene uno. Ritorna se qualcosa si muove.
    func advanceVisitor(by dt: TimeInterval) -> Bool {
        visitorClock += dt
        guard var guest = visitor else {
            visitorCheck += dt
            guard visitorClock > 3, visitorCheck > 1 else { return false }
            visitorCheck = 0
            tryArrival()
            return visitor != nil
        }
        // la cosa che l'ha attirato è stata tolta, o gli hanno messo qualcosa sotto i piedi: se ne va
        let occupied = garden.occupiedTiles()
        if guest.phase != .leaving, !garden.placements.contains(where: { $0.id == guest.attraction.placement.id }) || occupied.contains(guest.path[guest.index])
            || occupied.contains(guest.path[guest.next]) {
            guest.phase = .leaving
        }
        if guest.phase != .leaving { guest.fade = min(1, guest.fade + dt / 0.6) }
        var moving = guest.fade < 1
        if guest.next != guest.index {
            // cammina: un passo ogni secondo
            guest.progress += dt / 1.0
            moving = true
            if guest.progress >= 1 {
                guest.index = guest.next
                guest.progress = 1
            }
        } else {
            switch guest.phase {
            case .arriving:
                if reduceMotion {
                    // senza movimento compare già lì
                    guest.index = guest.path.count - 1
                    guest.next = guest.index
                    guest.phase = .staying
                    guest.remaining = Double.random(in: 70...130)
                } else if guest.index < guest.path.count - 1 {
                    guest.next = guest.index + 1
                    guest.progress = 0
                    guest.facingRight = facing(from: guest.path[guest.index], to: guest.path[guest.next], keeping: guest.facingRight)
                    moving = true
                } else {
                    guest.phase = .staying
                    guest.remaining = Double.random(in: 70...130)
                }
            case .staying:
                guest.remaining -= dt
                // salutato, si trattiene ancora un po' e poi va
                if guest.greeted { guest.remaining = min(guest.remaining, 25) }
                if guest.remaining <= 0 { guest.phase = .leaving }
            case .leaving:
                if guest.index > 0, !reduceMotion, !occupied.contains(guest.path[guest.index - 1]) {
                    guest.next = guest.index - 1
                    guest.progress = 0
                    guest.facingRight = facing(from: guest.path[guest.index], to: guest.path[guest.next], keeping: guest.facingRight)
                } else {
                    // arrivato all'ingresso (o non può camminare): sfuma e sparisce
                    guest.fade -= dt / 0.6
                    moving = true
                    if guest.fade <= 0 {
                        visitor = nil
                        return true
                    }
                }
            }
        }
        visitor = guest
        return moving
    }

    /// Verso dove guarda camminando da una tessera all'altra (i disegni guardano a destra): a sinistra se sullo schermo va a sinistra.
    private func facing(from: GardenTile, to: GardenTile, keeping current: Bool) -> Bool {
        let dx = (to.col - from.col) - (to.row - from.row)
        return dx == 0 ? current : dx > 0
    }

    /// In questa fascia della giornata viene qualcuno? Se sì, si sceglie dove si ferma e da dove entra.
    private func tryArrival() {
        let slot = GardenDaySlot.of(hour: shownHour())
        let day = ToDoDay.string(for: now(), calendar: calendar)
        let key = "\(day)-\(slot.rawValue)"
        guard !visitedSlots.contains(key) else { return }
        visitedSlots.insert(key)
        guard let attraction = GardenVisitors.arrival(day: day, slot: slot, placements: garden.placements, formedCorners: garden.formedCorners,
                                                      season: skyState().season),
              let item = GardenCatalog.item(withID: attraction.placement.item) else { return }
        let size = garden.islandSize
        let occupied = garden.occupiedTiles()
        let busy = Set(walkers.values.flatMap { [$0.from, $0.to] })
        let footprint = GardenLayout.tiles(of: item.footprint.applying(turned: attraction.placement.turned), at: attraction.placement.tile)
        let stands = GardenCompanions.standingTiles(around: footprint, size: size).filter {
            GardenLayout.isWalkable($0, size: size, occupied: occupied) && !busy.contains($0)
        }
        guard !stands.isEmpty else { return }
        let start = Int(GardenDrops.mixedHash("ospite-posto-\(key)") % UInt32(stands.count))
        for offset in 0..<stands.count {
            guard let path = GardenVisitors.entryRoute(to: stands[(start + offset) % stands.count], size: size, occupied: occupied) else { continue }
            visitor = Visitor(attraction: attraction, path: path, index: 0, next: 0, progress: 1, phase: .arriving, remaining: 0, greeted: false, fade: 0, facingRight: true)
            return
        }
    }

    /// L'ospite a schermo: dove sta in questo momento (cammina da una tessera all'altra, con un saltello come i compagni).
    private func visitorEntity(_ guest: Visitor, iso: Iso) -> Entity? {
        let here = guest.path[guest.index], there = guest.path[guest.next]
        let from = iso.center(of: here), to = iso.center(of: there)
        let t = CGFloat(guest.progress * guest.progress * (3 - 2 * guest.progress))
        let walking = guest.next != guest.index && guest.progress < 1
        let hop = walking ? CGFloat(sin(guest.progress * .pi)) * iso.tileH * 0.14 : 0
        let ground = NSPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t - hop)
        let cols = Double(here.col) + (Double(there.col) - Double(here.col)) * Double(t)
        let rows = Double(here.row) + (Double(there.row) - Double(here.row)) * Double(t)
        let feet = NSPoint(x: ground.x, y: ground.y + iso.tileH * Self.feetOffset)
        let species = guest.attraction.visitor
        guard var made = entity(kind: .visitor(species.id), resource: species.resource, referenceHeight: species.height, feet: feet,
                                shadowWidth: iso.tileW * 0.34, turned: !guest.facingRight, depth: cols + rows + 1, iso: iso) else { return nil }
        made.alpha = CGFloat(guest.fade)
        return made
    }

    /// Un tocco sull'ospite: lo saluti. La prima volta di una specie entra nel diario e lascia un regalo (stelline e una riga); le altre ti saluta e basta.
    func greetVisitor() {
        guard var guest = visitor else { return }
        let species = guest.attraction.visitor
        guard !guest.greeted else {
            flash("\(species.name) ti saluta.")
            return
        }
        guest.greeted = true
        visitor = guest
        let reason = GardenVisitors.reasonText(item: guest.attraction.item, corner: guest.attraction.corner)
        let welcome = garden.welcomeGuest(species.id, day: ToDoDay.string(for: now(), calendar: calendar), reason: reason)
        guard welcome.isFirst else {
            flash("\(species.name) ti saluta.")
            return
        }
        celebrations.append(Celebration(caption: "Nuovo ospite", title: species.name, members: [], visitor: species.id, start: nil))
        if let name = welcome.gift.flatMap({ GardenCatalog.item(withID: $0.item)?.name }) {
            flash("\(species.name) è \(species.came) a trovarti! Ti ha lasciato: \(name).")
        } else {
            flash("\(species.name) è \(species.came) a trovarti!")
        }
    }

    /// Finché non l'hai salutato, sopra l'ospite c'è una stellina che pulsa piano: un tocco e ti dice chi è.
    private func drawVisitorHint(_ laid: [Entity]) {
        guard let guest = visitor, !guest.greeted, guest.phase == .staying else { return }
        guard let entity = laid.first(where: { $0.kind == .visitor(guest.attraction.visitor.id) }) else { return }
        let pulse = reduceMotion ? 0.5 : 0.5 + 0.5 * CGFloat(sin(effectsClock() * 3))
        let center = NSPoint(x: entity.rect.midX, y: entity.rect.minY - 9 - 2 * pulse)
        let path = starPath(center: center, outer: 5 + 2 * pulse, angle: 0)
        Self.color(255, 208, 70).withAlphaComponent(0.75 + 0.25 * pulse).setFill()
        path.fill()
        Self.color(226, 140, 28).setStroke()
        path.lineWidth = 0.9
        path.stroke()
    }
}

// MARK: - Il mondo

extension GardenView {
    // MARK: Lo sfondo

    /// Il paesaggio dipinto è uno solo e copre tutto il mondo: più grande della finestra, centrato su di essa a zoom 1 e senza spostamenti (il resto, attorno, è lo stesso
    /// disegno specchiato e sfocato).
    static let backdropScale: CGFloat = 1.9

    private var backdropBounds: NSRect {
        NSRect(x: sceneW * (1 - Self.backdropScale) / 2, y: sceneH * (1 - Self.backdropScale) / 2, width: sceneW * Self.backdropScale, height: sceneH * Self.backdropScale)
    }

    private func drawBackdrop(fill: NSRect, season: Season) {
        MeadowBackdrop.drawWorld(scene: backdropBounds, fill: fill, zoom: zoom, pan: pan, blur: 2 * Self.backdropScale, veil: Self.palette(season).veil, season: season)
    }

    /// Un punto del disegno del paesaggio (`u` e `v` da 0 a 1 dall'angolo in alto a sinistra) com'è a zoom 1 e senza spostamenti: serve a mettere il fumo e le luci del casale.
    private func backdropPoint(u: Double, v: Double, season: Season) -> NSPoint? {
        MeadowBackdrop.scenePoint(u: u, v: v, in: backdropBounds.size, season: season).map { NSPoint(x: $0.x + backdropBounds.minX, y: $0.y + backdropBounds.minY) }
    }

    // MARK: La telecamera

    /// Dove cade, a zoom 1 e senza spostamenti, l'angolo (0, 0) del mondo (la cella di Pianty), e quanto è larga una tessera: lì l'isola grande al massimo sta tutta nella finestra.
    private var worldBase: (tileW: CGFloat, origin: NSPoint) {
        (Self.baseTileW, NSPoint(x: sceneW / 2, y: Iso.sceneTop))
    }

    /// La larghezza di una tessera a zoom 1.
    private static var baseTileW: CGFloat { Iso.fit(size: GardenIsland.maxSize, scene: sceneSize) }

    /// Lo zoom che mostra tutta un'isola di questa grandezza.
    private static func islandZoom(size: Int) -> CGFloat {
        min(max(CGFloat(GardenIsland.maxSize) / CGFloat(max(size, 1)), zoomRange.lowerBound), zoomRange.upperBound)
    }

    /// Il mondo con la telecamera `zoom` e `pan` (ingrandito attorno al centro della scena, come il paesaggio): la tessera e dove sta il suo angolo (0, 0).
    private func worldView(zoom: CGFloat, pan: NSPoint) -> (tileW: CGFloat, origin: NSPoint) {
        let base = worldBase
        let center = NSPoint(x: sceneW / 2, y: sceneH / 2)
        return (base.tileW * zoom, NSPoint(x: center.x + (base.origin.x - center.x) * zoom + pan.x, y: center.y + (base.origin.y - center.y) * zoom + pan.y))
    }

    /// L'isola `id` com'è alla vista data (di norma quella di adesso): grande com'è, nel suo posto del mondo.
    private func isoOf(_ id: String, zoom: CGFloat? = nil, pan: NSPoint? = nil) -> Iso? {
        let size = garden.islandSize(of: id)
        guard let corner = GardenWorld.corner(of: id, size: size) else { return nil }
        let view = worldView(zoom: zoom ?? self.zoom, pan: pan ?? self.pan)
        return Iso(size: size, tileW: view.tileW, origin: NSPoint(x: view.origin.x + CGFloat(corner.col - corner.row) * view.tileW / 2,
                                                                   y: view.origin.y + CGFloat(corner.col + corner.row) * view.tileW / 4))
    }

    /// Le quattro isole alla vista di adesso, dal fondo (in alto) al davanti, e se sono aperte (il compagno è sbloccato) o chiuse (al buio).
    private func worldIslands() -> [(id: String, iso: Iso, open: Bool)] {
        GardenIslands.all.compactMap { id in isoOf(id).map { (id: id, iso: $0, open: isIslandOpen(id)) } }
            .sorted { (GardenWorld.slot(of: $0.id).map { $0.col + $0.row } ?? 0) < (GardenWorld.slot(of: $1.id).map { $0.col + $0.row } ?? 0) }
    }

    /// Cosa fa rifare la scena preparata, oltre alla stagione e alla luce: la grandezza delle isole e quali sono aperte.
    private func worldSignature() -> String {
        GardenIslands.all.map { "\($0):\(garden.islandSize(of: $0))\(isIslandOpen($0) ? "a" : "c")" }.joined(separator: ",")
            + "|" + shownBridges().map(\.id).joined(separator: ",")
    }

    /// L'isola è aperta se il suo compagno è sbloccato; le altre sono al buio.
    private func isIslandOpen(_ id: String) -> Bool { profile.isCompanionUnlocked(id) }

    private func petName(_ island: String) -> String { Pet.all.first { $0.id == island }?.name ?? island }

    private func totalFocuses() -> Int {
        CompanionRewards.focuses(totalSeconds: log.sessions.reduce(0) { $0 + $1.seconds })
    }

    /// La vista che mostra tutta un'isola, a misura della finestra: lo zoom per cui la sua tessera è quella di sempre, e lo spostamento che mette il suo vertice in alto al solito posto.
    private func islandCamera(_ id: String) -> (zoom: CGFloat, pan: NSPoint) {
        let size = max(garden.islandSize(of: id), 1)
        let zoom = Self.islandZoom(size: size)
        let corner = GardenWorld.corner(of: id, size: size) ?? (col: 0, row: 0)
        let view = worldView(zoom: zoom, pan: .zero)
        let want = NSPoint(x: sceneW / 2, y: Iso.sceneTop)
        return (zoom, NSPoint(x: want.x - view.origin.x - CGFloat(corner.col - corner.row) * view.tileW / 2,
                              y: want.y - view.origin.y - CGFloat(corner.col + corner.row) * view.tileW / 4))
    }

    /// La vista che mostra tutte e quattro le isole (con le colline).
    private func worldCamera() -> (zoom: CGFloat, pan: NSPoint) {
        let base = worldBase
        let extent = CGFloat(GardenWorld.extent)
        let island = CGFloat(GardenIsland.maxSize) * base.tileW
        let sideHill = max((CGFloat(GardenHill.widthRatio) - 1) / 2, 0) * island
        // la scatola che le contiene, a zoom 1, rispetto all'angolo (0, 0): a sinistra e a destra gli angoli delle isole laterali, in alto le cose alte della prima,
        // in basso la collina dell'ultima (la linea dei suoi angoli sinistro e destro più quanto scende)
        let left = -extent * base.tileW / 2 - sideHill, right = extent * base.tileW / 2 + sideHill
        let top = -base.tileW * 1.6
        let bottom = CGFloat(2 * GardenWorld.cell + GardenIsland.maxSize) * base.tileW / 4 + CGFloat(GardenHill.belowRatio) * island
        let zoom = min(max(min((sceneW - 40) / (right - left), (sceneH - 120) / (bottom - top)), Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        let center = NSPoint(x: sceneW / 2, y: sceneH / 2)
        let box = NSPoint(x: base.origin.x + (left + right) / 2, y: base.origin.y + (top + bottom) / 2)
        let want = NSPoint(x: sceneW / 2, y: sceneH / 2 + 14)
        return (zoom, NSPoint(x: want.x - center.x - (box.x - center.x) * zoom, y: want.y - center.y - (box.y - center.y) * zoom))
    }

    /// Se la vista è quella che mostra tutta l'isola mostrata (nel qual caso il pulsante «tutta l'isola» non serve).
    private func isFitted() -> Bool {
        let camera = islandCamera(garden.shownIsland)
        return abs(zoom - camera.zoom) < 0.002 && abs(pan.x - camera.pan.x) < 0.5 && abs(pan.y - camera.pan.y) < 0.5
    }

    /// Il centro della finestra resta sempre nel mondo (o a una tessera dal bordo): non si può perderlo di vista.
    private func clampCamera() {
        let view = worldView(zoom: zoom, pan: pan)
        let world = Iso(size: GardenWorld.extent, tileW: view.tileW, origin: view.origin)
        let n = Double(GardenWorld.extent)
        let center = NSPoint(x: sceneW / 2, y: sceneH / 2)
        let g = world.grid(at: center)
        let col = min(max(g.col, -1), n + 1), row = min(max(g.row, -1), n + 1)
        guard col != g.col || row != g.row else { return }
        let inside = world.point(col: col, row: row)
        pan = NSPoint(x: pan.x + center.x - inside.x, y: pan.y + center.y - inside.y)
    }

    /// Dal vicino al lontano: se si sta vedendo tutta l'isola mostrata si rimpicciolisce a tutte e quattro, altrimenti si torna all'isola.
    func toggleWorldView() {
        cancelCarry()
        let all = worldCamera()
        if abs(zoom - all.zoom) < 0.02 && abs(pan.x - all.pan.x) < 3 && abs(pan.y - all.pan.y) < 3 {
            resetCamera()
        } else {
            zoom = all.zoom
            pan = all.pan
            cameraMoved()
        }
    }

    // MARK: L'isola viva

    /// L'isola «mostrata» (quella viva: ci camminano i compagni, ci si trascinano gli oggetti) è la più vicina al centro della finestra; cambia solo se un'altra è
    /// chiaramente più vicina, così sul confine non ballano.
    private func updateFocus() {
        guard carry == nil else { return }
        let view = worldView(zoom: zoom, pan: pan)
        let world = Iso(size: GardenWorld.extent, tileW: view.tileW, origin: view.origin)
        let g = world.grid(at: NSPoint(x: sceneW / 2, y: sceneH / 2))
        func distance(_ id: String) -> Double? {
            let size = garden.islandSize(of: id)
            guard let corner = GardenWorld.corner(of: id, size: size) else { return nil }
            let dc = max(corner.col - g.col, 0, g.col - (corner.col + Double(size))), dr = max(corner.row - g.row, 0, g.row - (corner.row + Double(size)))
            return (dc * dc + dr * dr).squareRoot()
        }
        let current = distance(garden.shownIsland) ?? .infinity
        let best = GardenIslands.all.filter { isIslandOpen($0) }.compactMap { id in distance(id).map { (id: id, distance: $0) } }.min { $0.distance < $1.distance }
        if let best, best.id != garden.shownIsland, best.distance + 0.75 < current { focus(best.id) }
    }

    /// Porta in primo piano un'isola aperta: da ora è lei quella viva (la vista non si muove). Il visitatore se ne va, i compagni dell'altra restano dove sono.
    private func focus(_ id: String) {
        guard id != garden.shownIsland, isIslandOpen(id) else { return }
        garden.showIsland(id)
        bubble = nil
        resetVisitors()
        trayScroll = 0
        needsDisplay = true
    }

    /// L'isola che sta sotto un punto della scena (dentro i suoi bordi), se c'è.
    private func islandUnder(_ p: NSPoint) -> String? {
        for entry in worldIslands().reversed() {
            let g = entry.iso.grid(at: p)
            if g.col >= -0.2, g.row >= -0.2, g.col < Double(entry.iso.size) + 0.2, g.row < Double(entry.iso.size) + 0.2 { return entry.id }
        }
        return nil
    }

    /// Un tocco su un'altra isola (o su una sua cosa) la porta in primo piano; su una chiusa dice cosa manca.
    private func touchIsland(at p: NSPoint) {
        guard carry == nil else { return }
        if let found = entity(at: p), !found.island.isEmpty, found.island != garden.shownIsland {
            focus(found.island)
            return
        }
        guard let id = islandUnder(p), id != garden.shownIsland else { return }
        if isIslandOpen(id) {
            focus(id)
        } else {
            let need = CompanionRewards.need(for: id, first: profile.firstCompanion, all: Pet.all.map(\.id))
            flash("L'isola di \(petName(id)) è chiusa: si sblocca a \(need) focus pieni di studio (ne hai \(min(totalFocuses(), need))).")
        }
    }

    // MARK: Ponti e cose sulle altre isole

    /// I ponti costruiti che si disegnano nella scena: quelli che la cerimonia sta costruendo (o rifacendo) compaiono pezzo per pezzo, a parte (`drawArrivalCeremony`).
    private func shownBridges() -> [GardenBridge] {
        let building = Set(ceremony?.bridges.map(\.id) ?? [])
        return GardenWorld.bridges.filter { garden.isBuilt($0) && !building.contains($0.id) }
    }

    /// I ponti costruiti fra le isole aperte vicine.
    private func drawBridges(_ islands: [(id: String, iso: Iso, open: Bool)]) {
        for bridge in shownBridges() {
            for piece in bridgePieces(bridge, islands: islands) {
                drawBridgePiece(alongColumns: bridge.alongColumns, variant: piece.variant, at: piece.point, tileW: piece.tileW)
            }
        }
    }

    /// Dove stanno i pezzi di un ponte alla vista di adesso (niente se una delle due isole è chiusa).
    private func bridgePieces(_ bridge: GardenBridge, islands: [(id: String, iso: Iso, open: Bool)]) -> [(point: NSPoint, variant: Int, tileW: CGFloat)] {
        guard let first = islands.first(where: { $0.id == bridge.first }), let second = islands.first(where: { $0.id == bridge.second }),
              first.open, second.open,
              let span = GardenWorld.span(of: bridge, firstSize: first.iso.size, secondSize: second.iso.size) else { return [] }
        let view = worldView(zoom: zoom, pan: pan)
        let world = Iso(size: GardenWorld.extent, tileW: view.tileW, origin: view.origin)
        return GardenWorld.pieceCenters(from: span.from, to: span.to).enumerated().map { index, center in
            (bridge.alongColumns ? world.point(col: center, row: span.across) : world.point(col: span.across, row: center), index % 2 + 1, world.tileW)
        }
    }

    /// Un pezzo di ponte, con il centro della sua striscia (lunga due tessere, larga una) su `center`. Il disegno è più alto che largo rispetto alla griglia
    /// (122×75 pixel per due tessere): si scala a parte in larghezza e in altezza, così i paletti di un pezzo coincidono con quelli del successivo.
    /// Nella scena la luce si dà dopo, su tutto; un pezzo che compare da solo (`alpha`, `lift` = quanto è ancora in alto) prende la tinta della luce come le cose.
    private func drawBridgePiece(alongColumns: Bool, variant: Int, at center: NSPoint, tileW: CGFloat, alpha: CGFloat = 1, lift: CGFloat = 0, tint: GardenTint = .none) {
        let resource = "giardino_ponte_\(alongColumns ? "colonna" : "riga")_\(variant)"
        guard let sprite = GardenSprites.sprite(resource) else { return }
        let sx = tileW / 122, sy = tileW / 150
        let width = sprite.source.width * sx, height = sprite.source.height * sy
        // il centro della striscia nel disegno (dall'alto a sinistra): 119,5 e 127; nello specchiato, da destra
        let anchorX = (alongColumns ? 119.5 : sprite.image.size.width - 119.5) - sprite.source.minX
        let anchorY = 127 - (sprite.image.size.height - sprite.source.maxY)
        let rect = NSRect(x: center.x - anchorX * sx, y: center.y - anchorY * sy - lift, width: width, height: height)
        guard let scaled = GardenSprites.scaled(sprite, resource: resource, pixelWidth: max(1, Int((width * backingScale).rounded())),
                                                pixelHeight: max(1, Int((height * backingScale).rounded())), tint: tint) else { return }
        GardenBlit.draw(scaled, in: rect, alpha: alpha)
    }

    // MARK: La costruzione del ponte

    /// Quanti pezzi ha un ponte (dipende dalla grandezza delle due isole).
    private func pieceCount(of bridge: GardenBridge) -> Int {
        guard let span = GardenWorld.span(of: bridge, firstSize: garden.islandSize(of: bridge.first), secondSize: garden.islandSize(of: bridge.second)) else { return 0 }
        return GardenWorld.pieceCenters(from: span.from, to: span.to).count
    }

    /// La vista che inquadra le isole dette (come `worldCamera` fa con tutte e quattro).
    private func camera(framing islands: [String]) -> (zoom: CGFloat, pan: NSPoint) {
        let base = worldBase
        var left = CGFloat.infinity, right = -CGFloat.infinity, top = CGFloat.infinity, bottom = -CGFloat.infinity
        for id in islands {
            let size = garden.islandSize(of: id)
            guard let corner = GardenWorld.corner(of: id, size: size) else { continue }
            for (dc, dr) in [(0, 0), (size, 0), (0, size), (size, size)] {
                let col = corner.col + Double(dc), row = corner.row + Double(dr)
                let x = CGFloat(col - row) * base.tileW / 2, y = CGFloat(col + row) * base.tileW / 4
                left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
            }
        }
        guard left < right else { return islandCamera(garden.shownIsland) }
        top -= base.tileW * 1.6          // le cose alte, la casa
        bottom += base.tileW * 0.6       // il bordo di terra
        let zoom = min(max(min((sceneW - 90) / (right - left), (sceneH - 170) / (bottom - top)), Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        let center = NSPoint(x: sceneW / 2, y: sceneH / 2)
        let box = NSPoint(x: base.origin.x + (left + right) / 2, y: base.origin.y + (top + bottom) / 2)
        let want = NSPoint(x: sceneW / 2, y: sceneH / 2 + 14)
        return (zoom, NSPoint(x: want.x - center.x - (box.x - center.x) * zoom, y: want.y - center.y - (box.y - center.y) * zoom))
    }

    /// Alla prima entrata nel giardino dopo uno sblocco (`allowed` è falso durante un focus): se c'è un compagno da accogliere o ci sono ponti da costruire, la telecamera inquadra
    /// le isole, i pezzi dei ponti compaiono uno dopo l'altro (i ponti in fila) e poi si salva tutto, con il regalo di benvenuto (uno per compagno appena sbloccato, anche
    /// senza ponte). Con «Riduci movimento» compare tutto insieme. Le chiavi nascoste `replayBridges` e `replayWelcome` (vedi `Garden.replayBridgesKey`) rifanno la cerimonia di
    /// un'isola già costruita: la prima senza toccare niente, la seconda con il regalo vero. Le chiavi non si consumano durante un focus.
    func beginArrivalCeremony(allowed: Bool) {
        ceremony = nil          // la finestra si era chiusa a metà: si riparte da capo
        guard allowed, profile.introSeen else { return }
        let open = Set(GardenIslands.all.filter { isIslandOpen($0) })
        garden.settleBridges(open: open)
        var bridges = garden.pendingBridges(open: open)
        var welcomed = garden.pendingWelcomes(open: open)
        var rehearsalIsland: String?
        let defaults = UserDefaults.standard
        let replayBridges = defaults.string(forKey: Garden.replayBridgesKey), replayWelcome = defaults.string(forKey: Garden.replayWelcomeKey)
        defaults.removeObject(forKey: Garden.replayBridgesKey)
        defaults.removeObject(forKey: Garden.replayWelcomeKey)
        func touching(_ island: String) -> [GardenBridge] {
            GardenWorld.bridges.filter { $0.touches(island) && open.contains($0.first) && open.contains($0.second) }
        }
        if let wanted = replayWelcome, open.contains(wanted) {
            bridges = touching(wanted)
            welcomed = [wanted]
        } else if let wanted = replayBridges, open.contains(wanted), !touching(wanted).isEmpty {
            bridges = touching(wanted)
            welcomed = []
            rehearsalIsland = wanted
        }
        guard !bridges.isEmpty || !welcomed.isEmpty else { return }
        let involved = Array(Set(bridges.flatMap { [$0.first, $0.second] } + welcomed))
        let target = involved.count == 1 ? islandCamera(involved[0]) : camera(framing: involved)
        let done = ArrivalCeremony(bridges: bridges, welcomed: welcomed, from: (zoom, pan), to: target, start: effectsClock(),
                                   pieces: bridges.reduce(0) { $0 + pieceCount(of: $1) }, rehearsalIsland: rehearsalIsland)
        if reduceMotion {
            zoom = target.zoom
            pan = target.pan
            clampCamera()
            finishArrival(done)
        } else {
            ceremony = done
        }
        needsDisplay = true
    }

    /// Quanto dura la costruzione: la telecamera, un pezzo dopo l'altro (l'ultimo ha il tempo di comparire) e un attimo di pausa.
    private func ceremonyLength(_ current: ArrivalCeremony) -> Double {
        Self.ceremonyGlide + Double(max(current.pieces - 1, 0)) * Self.ceremonyPieceGap + Self.ceremonyPieceFade + Self.ceremonyHold
    }

    /// Un passo della costruzione (a ogni fotogramma): la telecamera scivola, e alla fine i ponti si salvano. Dice se qualcosa si muove. (Non è privato perché i
    /// banchi di prova lo fanno girare a mano, con un orologio finto, invece di aspettare il timer.)
    func advanceCeremony() -> Bool {
        guard let current = ceremony else { return false }
        let elapsed = effectsClock() - current.start
        if current.gliding {
            let t = min(max(elapsed / Self.ceremonyGlide, 0), 1)
            let eased = CGFloat(t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2)
            zoom = current.from.zoom + (current.to.zoom - current.from.zoom) * eased
            pan = NSPoint(x: current.from.pan.x + (current.to.pan.x - current.from.pan.x) * eased, y: current.from.pan.y + (current.to.pan.y - current.from.pan.y) * eased)
            clampCamera()
            if t >= 1 { ceremony?.gliding = false }
        }
        if elapsed >= ceremonyLength(current) { finishArrival(current) }
        return true
    }

    // MARK: - Per i banchi di prova (non sono privati perché i banchi li usano per far finta di prendere le cose con il mouse)

    /// Dove sta nella vista la tessera `col`, `row` di un'isola (il punto dove poggiano i piedi di una cosa messa lì), con la telecamera com'è.
    func feetPoint(island: String, col: Int, row: Int, cols: Int = 1, rows: Int = 1) -> NSPoint? {
        guard let iso = isoOf(island) else { return nil }
        let ground = iso.point(col: Double(col) + Double(cols) / 2, row: Double(row) + Double(rows) / 2)
        return NSPoint(x: ground.x, y: ground.y + iso.tileH * Self.feetOffset)
    }

    /// La riga che si vede adesso in basso (quella che sparisce da sola).
    var shownMessage: String? { message }

    /// Se la cosa che si sta trascinando cadrebbe in un posto valido (nil se non se ne trascina nessuna).
    var carryVerdict: Bool? { carryTarget()?.valid }

    /// I pezzi che stanno comparendo: ognuno scende al suo posto e si fa vedere piano.
    private func drawArrivalCeremony() {
        guard let current = ceremony else { return }
        let elapsed = effectsClock() - current.start
        let islands = worldIslands()
        var index = 0
        for bridge in current.bridges {
            for piece in bridgePieces(bridge, islands: islands) {
                let appear = (elapsed - Self.ceremonyGlide - Double(index) * Self.ceremonyPieceGap) / Self.ceremonyPieceFade
                index += 1
                guard appear > 0 else { continue }
                let shown = CGFloat(min(appear, 1))
                drawBridgePiece(alongColumns: bridge.alongColumns, variant: piece.variant, at: piece.point, tileW: piece.tileW, alpha: shown,
                                lift: (1 - shown) * (1 - shown) * piece.tileW * 0.5, tint: currentTint)
            }
        }
    }

    /// L'arrivo è finito: i ponti si salvano costruiti e le isole accolte (con il regalo), la nuova isola diventa quella viva e una scritta con le stelline sul regalo lo dice.
    /// Una prova a vuoto non salva né regala niente.
    private func finishArrival(_ done: ArrivalCeremony) {
        ceremony = nil
        var welcomes: [GardenBridgeWelcome] = []
        if done.rehearsalIsland == nil { welcomes = garden.buildBridges(done.bridges, welcoming: done.welcomed) }
        if let island = done.welcomed.first ?? done.rehearsalIsland { focus(island) }
        for welcome in welcomes {
            // con un ponte che arriva a quell'isola è «Nuovo ponte», senza è «Nuova isola»
            let kind = done.bridges.contains { $0.touches(welcome.island) } ? "Nuovo ponte" : "Nuova isola"
            celebrations.append(Celebration(caption: "\(kind): un regalo per \(petName(welcome.island))", title: GardenCatalog.item(withID: welcome.item)?.name ?? welcome.item,
                                            members: welcome.placement.map { [$0] } ?? [], visitor: nil, start: nil))
        }
        if let island = done.rehearsalIsland {
            celebrations.append(Celebration(caption: "Prova: ponti rifatti, niente salvato", title: "Isola di \(petName(island))", members: [], visitor: nil, start: nil))
        } else if welcomes.isEmpty, let bridge = done.bridges.first {
            celebrations.append(Celebration(caption: "Nuovo ponte", title: "\(petName(bridge.first)) e \(petName(bridge.second))", members: [], visitor: nil, start: nil))
        }
        needsDisplay = true
    }

    /// Gli oggetti e il compagno di un'isola che non è quella viva: fermi, con la profondità del mondo.
    private func staticEntities(on id: String, iso: Iso) -> [Entity] {
        guard let corner = GardenWorld.corner(of: id, size: iso.size) else { return [] }
        let base = corner.col + corner.row
        let visible = sceneRect.insetBy(dx: -80, dy: -140)
        var result: [Entity] = []
        for placement in garden.placements(on: id) {
            guard let item = GardenCatalog.item(withID: placement.item) else { continue }
            if carryMoved, carry == .placed(placement.id) { continue }
            let footprint = item.footprint.applying(turned: placement.turned)
            let ground = iso.point(col: Double(placement.col) + Double(footprint.cols) / 2, row: Double(placement.row) + Double(footprint.rows) / 2)
            guard visible.contains(ground) else { continue }
            let feet = NSPoint(x: ground.x, y: ground.y + iso.tileH * Self.feetOffset)
            let front = Double(placement.col + footprint.cols - 1 + placement.row + footprint.rows - 1)
            let shadowWidth = item.castsShadow ? min(iso.tileW * 0.62 * CGFloat(max(footprint.cols, footprint.rows)), iso.tileW * 1.3) : nil
            if var made = entity(kind: .placed(placement.id), resource: item.resource, referenceHeight: item.height, feet: feet, shadowWidth: shadowWidth,
                                 turned: placement.turned, depth: base + front + 0.5, iso: iso) {
                made.island = id
                made.tile = placement.tile
                result.append(made)
            }
        }
        if let index = Pet.all.firstIndex(where: { $0.id == id }) {
            let pet = Pet.all[index]
            let ground = companionGround(pet.id, home: garden.companionTile(pet.id, index: index), iso: iso)
            if visible.contains(ground.point) {
                let feet = NSPoint(x: ground.point.x, y: ground.point.y + iso.tileH * Self.feetOffset)
                if var made = entity(kind: .companion(pet.id), resource: pet.iconResource, referenceHeight: GardenCatalog.companionHeight(for: pet.id), feet: feet,
                                     shadowWidth: iso.tileW * 0.5, turned: false, depth: base + ground.depth, iso: iso) {
                    made.island = id
                    result.append(made)
                }
            }
        }
        return result
    }

    // MARK: Le case

    /// Dove cade il disegno della casa di un'isola: il suo zoccolo (un rombo) sulle 3×3 tessere dell'angolo in alto. Il disegno è un po' più alto che largo rispetto alla griglia:
    /// si scala a parte in larghezza e in altezza, come i ponti. Nil se l'isola non ha ancora la casa.
    private func landmarkPlacement(island: String, iso: Iso) -> (origin: NSPoint, scaleX: CGFloat, scaleY: CGFloat, sprite: GardenSprite, resource: String, art: GardenLandmarks.Art)? {
        guard let art = GardenLandmarks.art[island], GardenLandmarks.built.contains(island) else { return nil }
        let resource = "giardino_casa_" + island
        guard let sprite = GardenSprites.sprite(resource) else { return nil }
        let center = iso.point(col: Double(GardenLandmarks.side) / 2, row: Double(GardenLandmarks.side) / 2)
        let sx = iso.tileW * CGFloat(GardenLandmarks.side) / 2 / CGFloat(art.halfWidth)
        let sy = iso.tileW * CGFloat(GardenLandmarks.side) / 4 / CGFloat(art.halfHeight)
        // l'angolo in alto a sinistra del disegno ritagliato, nella scena
        return (NSPoint(x: center.x - CGFloat(art.centerX) * sx, y: center.y - CGFloat(art.centerY) * sy), sx, sy, sprite, resource, art)
    }

    /// La casa di un'isola, nella scena preparata; su un'isola chiusa è al buio.
    private func drawLandmark(island: String, iso: Iso, open: Bool) {
        guard let house = landmarkPlacement(island: island, iso: iso) else { return }
        let imageHeight = house.sprite.image.size.height
        let rect = NSRect(x: house.origin.x + house.sprite.source.minX * house.scaleX, y: house.origin.y + (imageHeight - house.sprite.source.maxY) * house.scaleY,
                          width: house.sprite.source.width * house.scaleX, height: house.sprite.source.height * house.scaleY)
        guard rect.intersects(sceneRect.insetBy(dx: -300, dy: -180)) else { return }
        let tint = open ? GardenTint.none : GardenTint(red: 92, green: 98, blue: 130)
        guard let scaled = GardenSprites.scaled(house.sprite, resource: house.resource, pixelWidth: max(1, Int((rect.width * backingScale).rounded())),
                                                pixelHeight: max(1, Int((rect.height * backingScale).rounded())), tint: tint) else { return }
        GardenBlit.draw(scaled, in: rect)
    }

    /// Di sera le finestre delle case si accendono (come quelle del casale): una luce calda sui vetri.
    private func drawLandmarkLights(light: GardenLight) {
        let strength = CGFloat(light.lamp)
        guard strength > 0.02 else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setBlendMode(.plusLighter)
        let warm = Self.color(255, 208, 120)
        for entry in worldIslands() where entry.open {
            guard let house = landmarkPlacement(island: entry.id, iso: entry.iso) else { continue }
            let size = house.sprite.image.size
            for lamp in house.art.lights {
                let c = NSPoint(x: house.origin.x + CGFloat(lamp.u) * size.width * house.scaleX, y: house.origin.y + CGFloat(lamp.v) * size.height * house.scaleY)
                guard sceneRect.insetBy(dx: -80, dy: -80).contains(c) else { continue }
                let radius = CGFloat(lamp.size) * entry.iso.tileW * 0.55
                NSGradient(colors: [warm.withAlphaComponent(0.55 * strength), warm.withAlphaComponent(0.18 * strength), warm.withAlphaComponent(0)])?
                    .draw(fromCenter: c, radius: 0, toCenter: c, radius: radius, options: [])
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: I nomi e il lucchetto

    /// La targhetta in alto a sinistra: su quale isola si è; tocca per vedere tutte le isole.
    private var captionRect: NSRect {
        let caption = "Isola di \(petName(garden.shownIsland))"
        let width = ceil((caption as NSString).size(withAttributes: [.font: smallFont]).width) + 40
        return NSRect(x: 16, y: 50, width: width, height: 26)
    }

    private func drawIslandCaption() {
        let box = captionRect
        drawChip(box, fill: NSColor(calibratedRed: 1, green: 0.99, blue: 0.94, alpha: 0.92), stroke: Paper.paperEdge)
        if let icon = tinted("map", size: 11, color: Paper.inkLight) {
            icon.draw(in: NSRect(x: box.minX + 12, y: box.midY - icon.size.height / 2, width: icon.size.width, height: icon.size.height))
        }
        text("Isola di \(petName(garden.shownIsland))", in: NSRect(x: box.minX + 30, y: box.minY + 5, width: box.width - 36, height: 16), font: smallFont, color: Paper.ink)
    }

    /// Il cartellino di un'isola, sotto il suo angolo davanti: il nome e, se è chiusa, quanto manca a sbloccarla.
    private func islandLabel(_ id: String, iso: Iso, open: Bool) -> (rect: NSRect, subtitle: String?) {
        var subtitle: String?
        if !open {
            let need = CompanionRewards.need(for: id, first: profile.firstCompanion, all: Pet.all.map(\.id))
            subtitle = "si sblocca a \(need) focus"
        }
        let n = Double(iso.size)
        let front = iso.point(col: n, row: n)
        let nameWidth = ceil((petName(id) as NSString).size(withAttributes: [.font: Paper.markerFont(17)]).width)
        let subtitleWidth = subtitle.map { ceil(($0 as NSString).size(withAttributes: [.font: smallFont]).width) } ?? 0
        let width = max(nameWidth, subtitleWidth) + 30
        let height: CGFloat = subtitle == nil ? 28 : 46
        return (NSRect(x: front.x - width / 2, y: front.y + iso.edge + 6, width: width, height: height), subtitle)
    }

    /// I lucchetti sulle isole chiuse, e (rimpicciolendo) i nomi di tutte: sono sullo schermo, non nel mondo, quindi non crescono con lo zoom.
    private func drawIslandLabels() {
        let showNames = zoom < 0.8
        for entry in worldIslands() {
            let label = islandLabel(entry.id, iso: entry.iso, open: entry.open)
            let n = Double(entry.iso.size)
            let center = entry.iso.point(col: n / 2, row: n / 2)
            guard sceneRect.insetBy(dx: -200, dy: -200).contains(center) else { continue }
            if !entry.open {
                if let lock = tinted("lock.fill", size: min(max(entry.iso.tileW * 0.55, 16), 34), color: NSColor(calibratedWhite: 1, alpha: 0.88)) {
                    lock.draw(in: NSRect(x: center.x - lock.size.width / 2, y: center.y - lock.size.height / 2, width: lock.size.width, height: lock.size.height))
                }
            }
            guard showNames || !entry.open else { continue }
            guard entry.open || entry.iso.tileW > 18 else { continue }
            let open = entry.open
            drawChip(label.rect, fill: open ? NSColor(calibratedRed: 1, green: 0.99, blue: 0.94, alpha: 0.95) : NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.30, alpha: 0.90),
                     stroke: entry.id == garden.shownIsland ? Paper.accent : (open ? Paper.paperEdge : NSColor(calibratedRed: 0.45, green: 0.48, blue: 0.60, alpha: 1)))
            text(petName(entry.id), in: NSRect(x: label.rect.minX, y: label.rect.minY + (label.subtitle == nil ? 3 : 4), width: label.rect.width, height: 24), font: Paper.markerFont(17),
                 color: open ? Paper.ink : NSColor(calibratedWhite: 0.92, alpha: 1), alignment: .center)
            if let subtitle = label.subtitle {
                text(subtitle, in: NSRect(x: label.rect.minX, y: label.rect.minY + 26, width: label.rect.width, height: 16), font: smallFont,
                     color: NSColor(calibratedWhite: 0.78, alpha: 1), alignment: .center)
            }
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

    /// `canCelebrate`: falso durante un focus (la cerimonia d'arrivo aspetta la prossima entrata).
    func show(canCelebrate: Bool = true) {
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
        view?.resetVisitors()
        view?.reload()
        view?.announceGifts(gifts.count)
        view?.announceRules()
        view?.beginArrivalCeremony(allowed: canCelebrate)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
