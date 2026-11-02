import Foundation

// Il giardino, per il confronto con Windows (windows/test/giardino-contratto.test.ts): quello che la versione per Mac ricava da dati inventati e sempre
// uguali (identificativi, tessere, ore, giorni), scritto in tests/fixtures/attesi/_giardino.json. Nessun numero casuale: tutto viene da hash e contatori.

/// Un identificativo fisso per il numero `n` (come li scrive Swift: in maiuscolo).
func fixedUUID(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }

func tileJSON(_ t: GardenTile) -> [Int] { [t.col, t.row] }

/// Un valore facoltativo: nil diventa null.
func opt<T>(_ x: T?) -> Any { x.map { $0 as Any } ?? NSNull() }

private func placementsJSON(_ list: [GardenPlacement]) -> [[String: Any]] {
    list.map { ["oggetto": $0.item, "isola": $0.island, "col": $0.col, "row": $0.row, "girata": $0.turned] as [String: Any] }
}

/// Il nome dell'immagine senza il prefisso del bundle del Mac (`giardino_`).
private func bare(_ resource: String) -> String { String(resource.dropFirst("giardino_".count)) }

private func catalogJSON() -> [String: Any] {
    let items = GardenCatalog.items.map { item -> [String: Any] in
        [
            "id": item.id, "numero": GardenCatalog.number(of: item.id)!, "nome": item.name, "articolo": item.nameWithArticle,
            "rarita": item.rarity.title, "isola": v(item.island), "dotazione": item.isStarter, "altezza": item.height,
            "lati": item.sides, "immagine": bare(item.gardenResource), "acceso": v(item.litResource.map(bare)), "oscilla": item.swayStrength,
            "luce": opt(item.glow.map { ["r": $0.red, "g": $0.green, "b": $0.blue, "raggio": $0.radius, "alto": $0.top, "forza": $0.strength, "vibra": $0.flickers] as [String: Any] }),
            "regola": item.islandRule(ownerName: "Gattino"), "isolaSbagliata": item.wrongIslandLine(ownerName: "Gattino"),
            "ombra": item.castsShadow, "sulLato": item.axial, "pendenza": item.slope, "siUnisce": item.joins,
            "ingombro": [item.footprint.cols, item.footprint.rows],
        ]
    }
    let spreads = GardenAlbum.spreads().map { spread -> [String: Any] in
        ["sinistra": spread.left.items.map { $0.id }, "destra": opt(spread.right.map { $0.items.map { $0.id } }), "pagina": spread.left.index, "pagine": spread.left.count]
    }
    let found = Set(GardenCatalog.items.prefix(16).map { $0.id })
    return [
        "oggetti": items, "doppiePagine": spreads,
        "doppieComplete": [0, 6, 16, 30, 47].map { n in GardenAlbum.completedSpreads(isFound: { id in GardenCatalog.items.prefix(n).contains { $0.id == id } }) },
        "doppieSedici": GardenAlbum.completedSpreads(isFound: { found.contains($0) }),
        "altezzeCompagni": ["pianty", "porcellino", "ciccio", "gattino", "riccio", "tartaruga", "nessuno"].map { GardenCatalog.companionHeight(for: $0) },
        "benvenuti": GardenIslands.all.map { island in v(GardenCatalog.welcomeGift(forIsland: island, has: { $0 == "annaffiatoio" || $0 == "cesto-carote" })) },
        "universali": GardenCatalog.universalItems.count,
    ]
}

private func dropsJSON() -> [String: Any] {
    let texts = ["", "a", "FocusFriends", "posto-REGALO-1", "àèìòù", "00000000-0000-4000-8000-000000000001", "terra-gattino/3,4,0"]
    let streams: [[Double]] = [0, 1, 42, 4_294_967_295].map { seed in
        var s = GardenDrops.Stream(seed: UInt32(seed))
        return (0..<6).map { _ in s.next() }
    }
    // Una lunga fila di focus inventati: ogni tanto lungo, ogni tanto con la serie, con l'elenco delle isole aperte che cresce.
    var state = GardenDropState.starting()
    var credits: [[String: Any]] = []
    for i in 0..<420 {
        let open = Set(GardenIslands.all.prefix(1 + min(i / 90, 4)))
        let pool = GardenCatalog.items.filter { item in item.island.map { open.contains($0) } ?? true }
        let seconds = 1200 + (i * 37 % 3000)
        let streak = (i * 7) % 20
        let somethingBefore = GardenDrops.hasSomethingToFind(state: state, pool: pool)
        let drop = GardenDrops.credit(sessionID: fixedUUID(i).uuidString, streakDays: streak, seconds: seconds, state: &state, pool: pool)
        let gift: GardenGift = drop.map { .found($0) } ?? (somethingBefore ? .progress : .complete)
        let left = GardenDrops.minutesToNextGift(state: state, pool: pool)
        credits.append(["oggetto": v(drop?.item), "rarita": v(drop?.rarity.title), "riserva": state.studyBank, "mancano": opt(left),
                        "strada": opt(GardenDrops.giftProgress(state: state, pool: pool).map(r)), "riga": GardenDrops.line(for: gift, minutesLeft: left),
                        "rigaMenu": GardenDrops.nextGiftLine(minutesLeft: left), "dalRaro": state.sinceRare, "dalLeggendario": state.sinceLegendary])
    }
    var lines: [String] = []
    for minutes in [nil, 0, 1, 35] as [Int?] {
        lines.append(GardenDrops.line(for: .progress, minutesLeft: minutes))
        lines.append(GardenDrops.line(for: .notEligible, minutesLeft: minutes))
        lines.append(GardenDrops.line(for: .complete, minutesLeft: minutes))
        for rarity in GardenRarity.allCases { lines.append(GardenDrops.line(for: .found(GardenDrop(item: "lampione", rarity: rarity)), minutesLeft: minutes)) }
        lines.append(GardenDrops.line(for: .found(GardenDrop(item: "sconosciuto", rarity: .common)), minutesLeft: minutes))
        lines.append(GardenDrops.nextGiftLine(minutesLeft: minutes))
    }
    let chances = [(0, 0), (3, 2700), (7, 1200), (14, 3000), (30, 2699)].map { c -> [Double] in
        let x = GardenDrops.chances(streakDays: c.0, seconds: c.1)
        return [r(x.rare), r(x.legendary)]
    }
    return [
        "hash": texts.map { Int(GardenDrops.hash($0)) }, "hashMescolato": texts.map { Int(GardenDrops.mixedHash($0)) },
        "flussi": streams.map { $0.map { ($0 * 1e9).rounded() } },
        "costi": [0, 3, 4, 10, 47].map { GardenDrops.giftCostSeconds(found: $0) },
        "probabilita": chances, "regali": credits, "righe": lines,
    ]
}

private func gardenGridJSON() -> [String: Any] {
    var paths: [String: Any] = [:]
    for island in GardenIslands.all + ["nessuna"] {
        var bySize: [String: Any] = [:]
        for size in 8...10 {
            let empty = Set<GardenTile>()
            bySize[String(size)] = [
                "sentiero": GardenPaths.tiles(island: island, size: size).map(tileJSON),
                "approdi": GardenPaths.landings(island: island, size: size).map { ["lato": "\($0.face)", "tessera": tileJSON($0.tile)] as [String: Any] },
                "liberi1": GardenLayout.freeOrigins(for: GardenFootprint(cols: 1, rows: 1), size: size, occupied: empty, island: island).count,
                "liberi2": GardenLayout.freeOrigins(for: GardenFootprint(cols: 2, rows: 1), size: size, occupied: empty, island: island).map(tileJSON),
                "vicino": GardenLayout.nearestOrigin(to: GardenTile(col: 5, row: 5), footprint: GardenFootprint(cols: 1, rows: 2), size: size, occupied: [GardenTile(col: 5, row: 5)], island: island).map(tileJSON).map { $0 as Any } ?? NSNull(),
            ] as [String: Any]
        }
        paths[island] = ["grandezze": bySize, "compagni": (0..<5).map { tileJSON(GardenLayout.defaultCompanionTile(index: $0, island: island)) },
                         "casa": GardenLandmarks.tiles(island: island).count]
    }
    let legacy = (0..<8).map { i in tileJSON(GardenLayout.tile(fromLegacy: GardenSpot(x: Double(i) * 0.15, y: 0.5 + Double(i) * 0.07), size: 8 + i % 3)) }
    let linked: Set<GardenTile> = [GardenTile(col: 2, row: 2), GardenTile(col: 3, row: 2), GardenTile(col: 2, row: 3), GardenTile(col: 4, row: 4), GardenTile(col: 2, row: 1), GardenTile(col: 1, row: 2)]
    var arms: [Int] = []
    for col in 0...5 { for row in 0...5 { for turned in [false, true] { arms.append(GardenLinks.arms(at: GardenTile(col: col, row: row), among: linked, turned: turned).rawValue) } } }
    let occupied: Set<GardenTile> = [GardenTile(col: 4, row: 4), GardenTile(col: 4, row: 5), GardenTile(col: 5, row: 4)]
    return [
        "sentieri": paths, "vecchioSentiero": GardenIsland.pathTiles(size: 10).map(tileJSON),
        "compagniSenzaIsola": (0..<4).map { tileJSON(GardenLayout.defaultCompanionTile(index: $0)) },
        "daPrato": legacy, "bracci": arms,
        "camminabile": opt(GardenLayout.nearestWalkable(to: GardenTile(col: 4, row: 4), size: 8, occupied: occupied).map(tileJSON)),
        "vecchiCanPlace": (0..<10).map { GardenLayout.canPlace(GardenFootprint(cols: 1, rows: 1), at: GardenTile(col: $0, row: 3 + $0 % 3), size: 10, occupied: []) },
        "grandezzaIsola": (-1...4).map { GardenIsland.size(completedSpreads: $0) },
    ]
}

private func terrainJSON() -> [String: Any] {
    var islands: [String: Any] = [:]
    for island in GardenIslands.all {
        let tag = GardenIslands.terrainTag(island)
        var seasons: [String: Any] = [:]
        for season in Season.allCases {
            let decals = (0..<10).flatMap { col in (0..<3).map { row in GardenTerrain.decals(col: col, row: row, season: season, onPath: (col + row) % 4 == 0, tag: tag) } }
            seasons[season.rawValue] = [
                "erba": GardenTerrain.grassGrid(size: 10, weights: GardenTerrain.grassWeights(season: season), tag: tag),
                "sentiero": GardenTerrain.pathVariants(count: 30, weights: GardenTerrain.pathWeights(season: season), tag: tag),
                "dettagli": decals.map { list in list.map { ["immagine": $0.image, "gruppo": "\($0.group)", "u": r($0.u), "v": r($0.v), "misura": r($0.size), "specchio": $0.flipped, "ancora": $0.anchor] as [String: Any] } },
            ] as [String: Any]
        }
        islands[island] = seasons
    }
    let hill = GardenHill.frame(islandLeft: (x: 120, y: 400), islandRight: (x: 920, y: 404))
    return [
        "isole": islands, "erba8": GardenTerrain.grassGrid(size: 8), "bordi": [0, 1].map { GardenTerrain.edgeSequence(face: $0, count: 14) },
        "collina": [r(hill.x), r(hill.y), r(hill.width), r(hill.height), r(hill.scale)],
        "collinaRapporti": [r(GardenHill.widthRatio), r(GardenHill.belowRatio), r(GardenHill.heightRatio)],
    ]
}

private func worldJSON() -> [String: Any] {
    let opens: [Set<String>] = [["pianty"], ["pianty", "porcellino"], ["pianty", "gattino"], ["gattino", "riccio"], Set(GardenIslands.all)]
    return [
        "estensione": GardenWorld.extent, "portata": [GardenWorld.reach.left, GardenWorld.reach.right, GardenWorld.reach.depth],
        "ponti": GardenWorld.bridges.map { bridge -> [String: Any] in
            let small = GardenWorld.span(of: bridge, firstSize: 8, secondSize: 8)!, big = GardenWorld.span(of: bridge, firstSize: 10, secondSize: 10)!
            return ["id": bridge.id, "colonne": bridge.alongColumns, "piccolo": [small.from, small.to, small.across], "grande": [big.from, big.to, big.across],
                    "pezzi": GardenWorld.pieceCenters(from: small.from, to: small.to)]
        },
        "angoli": GardenIslands.all.map { id in GardenWorld.corner(of: id, size: 8).map { [$0.col, $0.row] } ?? [] },
        "daCostruire": opens.map { open in GardenWorld.pending(open: open, built: ["pianty-porcellino"]).map(\.id) },
        "nuovi": opens.map { open in GardenWorld.newcomers(open: open, welcomed: ["porcellino"], home: "pianty") },
        "pezziCorti": [GardenWorld.pieceCenters(from: 3, to: 3), GardenWorld.pieceCenters(from: 10, to: 14.5)],
    ]
}

private func skyJSON() -> [String: Any] {
    var light: [String: Any] = [:]
    for season in Season.allCases {
        light[season.rawValue] = stride(from: -1.0, through: 25.0, by: 0.25).map { hour -> [Double] in
            let l = GardenSky.light(hour: hour, season: season)
            return [r(l.darkness), r(l.tint.red), r(l.tint.green), r(l.tint.blue), r(l.tintStrength), r(l.lamp), r(l.multiplier.blue),
                    r(GardenSky.fireflyAmount(season: season, light: l))]
        }
    }
    let times = [0, 13.7, 250.3, 5000.9]
    var particles: [String: Any] = [:]
    for kind in [GardenParticleKind.petal, .leaf, .snow] {
        particles["\(kind)"] = ["quante": GardenSky.particleCount(kind), "dove": (0..<6).flatMap { index in times.map { time -> [Double] in
            let p = GardenSky.particle(kind: kind, index: index, time: time, width: 900, height: 600)
            return [r(p.x), r(p.y), r(p.size), r(p.angle), r(p.alpha), r(p.tone)]
        } }] as [String: Any]
    }
    let months = (1...12).map { month in Season.of(cal.date(from: DateComponents(year: 2026, month: month, day: 15, hour: 12))!, calendar: cal).rawValue }
    return [
        "luce": light, "particelle": particles, "stagioni": months,
        "albe": Season.allCases.map { [GardenSky.sunrise($0), GardenSky.sunset($0), GardenSky.wind($0), GardenSky.smokeAmount($0)] },
        "cade": Season.allCases.map { GardenSky.particleKind($0).map { "\($0)" } ?? "niente" },
        "lucciole": (0..<4).flatMap { i in times.map { t in let f = GardenSky.firefly(index: i, time: t, width: 900, height: 600); return [r(f.x), r(f.y), r(f.glow)] } },
        "vento": (0..<6).flatMap { i in times.map { t in r(GardenSky.sway(time: t, col: i, row: 9 - i, seed: Double(i) / 7, height: Double(i) / 5)) } },
        "luccichii": (0..<3).flatMap { i in times.map { t in let s = GardenSky.sparkle(index: i, time: t); return [r(s.x), r(s.y), r(s.glow)] } },
        "cerchi": times.map { t in let p = GardenSky.ripple(time: t, seed: 0.3); return [r(p.x), r(p.y), r(p.phase), r(p.alpha)] },
        "fumo": (0..<9).flatMap { i in times.map { t in let s = GardenSky.smoke(index: i, time: t, wind: 0.8); return [r(s.dx), r(s.dy), r(s.radius), r(s.alpha)] } },
        "cadute": (0..<5).flatMap { i in times.map { t in let d = GardenSky.drift(index: i, time: t, period: 4.5); return [r(d.progress), r(d.x), r(d.spin), r(d.alpha)] } },
        "farfalle": (0..<3).flatMap { i in times.map { t in let b = GardenSky.butterfly(index: i, time: t); return [r(b.x), r(b.y), r(b.flap)] } },
        "luccioleAngolo": (0..<3).flatMap { i in times.map { t in let f = GardenSky.cornerFirefly(index: i, time: t); return [r(f.x), r(f.y), r(f.glow)] } },
        "stelline": (0..<18).flatMap { i in [0, 0.1, 0.5, 0.9, 1].map { p in let s = GardenSky.burstStar(index: i, progress: p); return [r(s.dx), r(s.dy), r(s.size), r(s.angle), r(s.alpha)] } },
    ]
}

/// Un elenco di copie inventate: gli id sono fissi (`fixedUUID`), le tessere e gli oggetti scelti per formare (o quasi) degli angoli.
private func samplePlacements() -> [GardenPlacement] {
    let spec: [(String, Int, Int, Bool)] = [
        ("tavolino", 1, 1, false), ("sdraio", 3, 1, false), ("panchina", 6, 6, false), ("lampione", 8, 8, false), ("lampione", 7, 6, false),
        ("aiuola", 4, 4, false), ("annaffiatoio", 4, 6, false), ("margherite", 0, 6, false), ("tulipani", 1, 7, false), ("lavanda", 2, 6, false),
        ("papaveri", 0, 8, false), ("margherite", 1, 8, false), ("amaca", 6, 1, true), ("tiragraffi", 7, 3, false), ("funghi", 9, 9, false),
        ("felci", 9, 7, false), ("mughetti", 8, 9, false), ("picnic", 5, 8, false), ("bandierine", 4, 9, false), ("cesto-carote", 3, 8, false),
        ("bagnetto", 2, 2, false), ("girasole", 2, 0, false), ("tana-foglie", 0, 3, false), ("mucchio-foglie", 1, 4, false), ("tronco-cavo", 0, 5, false),
    ]
    return spec.enumerated().map { GardenPlacement(id: fixedUUID(100 + $0.offset), item: $0.element.0, tile: GardenTile(col: $0.element.1, row: $0.element.2), turned: $0.element.3) }
}

private func cornersJSON() -> [String: Any] {
    let all = samplePlacements()
    var sets: [[String: Any]] = []
    for count in [0, 2, 5, 9, 12, 16, 20, 25] {
        let list = Array(all.prefix(count))
        let formed = GardenCorners.formed(by: list)
        sets.append(Dictionary(uniqueKeysWithValues: formed.map { key, ids in (key, ids.map { id in list.firstIndex { $0.id == id }! }) }))
    }
    let distances = (0..<all.count).map { a in (0..<all.count).map { b in min(GardenCorners.distance(all[a], all[b]), 99) } }
    return ["formati": sets, "distanze": distances, "nomi": GardenCorners.all.map { $0.name }]
}

private func companionsJSON() -> [String: Any] {
    let occupied: Set<GardenTile> = [GardenTile(col: 2, row: 0), GardenTile(col: 2, row: 1), GardenTile(col: 2, row: 2), GardenTile(col: 2, row: 3), GardenTile(col: 4, row: 4), GardenTile(col: 5, row: 4)]
    let routes = [(GardenTile(col: 0, row: 0), GardenTile(col: 4, row: 0)), (GardenTile(col: 0, row: 0), GardenTile(col: 0, row: 0)), (GardenTile(col: 1, row: 1), GardenTile(col: 7, row: 7)),
                  (GardenTile(col: 0, row: 0), GardenTile(col: 2, row: 2)), (GardenTile(col: 6, row: 6), GardenTile(col: 0, row: 7))]
    return [
        "pose": ["pianty", "porcellino", "ciccio", "gattino", "riccio", "tartaruga"].flatMap { pet in GardenPose.allCases.map { pose in
            ["frame": GardenCompanions.frames(pet: pet, pose: pose), "immagini": [0, 0.4, 1.3, 7.9].map { v(GardenCompanions.resource(pet: pet, pose: pose, time: $0)) }] as [String: Any]
        } },
        "intorno": [[GardenTile(col: 0, row: 0)], [GardenTile(col: 3, row: 3), GardenTile(col: 4, row: 3)], [GardenTile(col: 7, row: 7)]].map { GardenCompanions.standingTiles(around: $0, size: 8).map(tileJSON) },
        "strade": routes.map { opt(GardenCompanions.route(from: $0.0, to: $0.1, size: 8, occupied: occupied).map { $0.map(tileJSON) }) },
        "stradaCorta": opt(GardenCompanions.route(from: GardenTile(col: 0, row: 0), to: GardenTile(col: 7, row: 7), size: 8, occupied: [], limit: 5).map { $0.map(tileJSON) }),
        "affinita": GardenCompanions.affinities.map { "\($0.pet)/\($0.corner)/\($0.item)/\($0.pose.rawValue)" },
    ]
}

private func visitorsJSON() -> [String: Any] {
    let all = samplePlacements()
    let formed = GardenCorners.formed(by: all)
    var arrivals: [Any] = []
    var day = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!
    for _ in 0..<40 {
        let text = dayFormatter.string(from: day)
        let season = Season.of(day, calendar: cal)
        for slot in GardenDaySlot.allCases {
            let found = GardenVisitors.arrival(day: text, slot: slot, placements: all, formedCorners: formed, season: season)
            arrivals.append(opt(found.map { ["ospite": $0.visitor.id, "copia": all.firstIndex(of: $0.placement)!, "oggetto": $0.item, "angolo": v($0.corner),
                                             "motivo": GardenVisitors.reasonText(item: $0.item, corner: $0.corner)] as [String: Any] }))
        }
        day = cal.date(byAdding: .day, value: 9, to: day)!
    }
    let occupied = GardenLayout.occupiedTiles(all)
    return [
        "arrivi": arrivals,
        "fasce": stride(from: 0.0, through: 24.0, by: 0.5).map { GardenDaySlot.of(hour: $0).rawValue },
        "ingressi": [GardenTile(col: 5, row: 5), GardenTile(col: 0, row: 0), GardenTile(col: 9, row: 2)].map { opt(GardenVisitors.entryRoute(to: $0, size: 10, occupied: occupied).map { $0.map(tileJSON) }) },
        "venuti": GardenVisitors.all.map { "\($0.name)/\($0.came)/\($0.isRare)/\($0.resource)" },
    ]
}

// ---- un giardino che cambia passo per passo (Garden.swift), in una cartella temporanea

private func gardenStateJSON(_ g: Garden) -> [String: Any] {
    var islands: [String: Any] = [:]
    for island in GardenIslands.all {
        islands[island] = ["copie": placementsJSON(g.placements(on: island)), "grandezza": g.islandSize(of: island),
                           "cassetta": g.tray(on: island).map { $0.id }, "angoli": g.formedCorners(on: island).keys.sorted()]
    }
    return [
        "trovati": g.drops.found.keys.sorted(), "riserva": g.drops.studyBank, "dalRaro": g.drops.sinceRare, "dalLeggendario": g.drops.sinceLegendary,
        "nuove": g.unseen.sorted(), "casa": v(g.home), "isole": islands, "angoli": g.corners, "ponti": g.bridges, "accolti": g.welcomed,
        "mancano": opt(g.minutesToNextGift), "strada": opt(g.nextGiftProgress.map(r)),
        "compagni": g.companionTiles.mapValues(tileJSON), "ospiti": g.guests.mapValues { ["primo": $0.first, "visite": $0.visits, "motivo": $0.reason] as [String: Any] },
    ]
}

/// Il file come l'ha scritto il giardino, con gli id delle copie sostituiti dal loro posto nell'elenco (sono casuali).
private func savedFileJSON(_ directory: URL) -> Any {
    guard let data = try? Data(contentsOf: directory.appendingPathComponent("giardino.json")),
          var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return NSNull() }
    if var list = object["placements"] as? [[String: Any]] {
        for index in list.indices { list[index]["id"] = "copia-\(index)" }
        object["placements"] = list
    }
    return object
}

func gardenStepsJSON() throws -> [String: Any] {
    let directory = fm.temporaryDirectory.appendingPathComponent("ff-attesi-passi-\(UUID().uuidString)")
    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: directory) }
    var open: Set<String> = ["gattino"]
    let g = Garden(directory: directory)
    g.isIslandOpen = { open.contains($0) }
    var steps: [[String: Any]] = []
    func step(_ name: String, _ extra: [String: Any] = [:]) {
        var state = gardenStateJSON(g)
        state["passo"] = name
        for (key, value) in extra { state[key] = value }
        steps.append(state)
    }
    step("nuovo")
    g.adoptHome("gattino")
    g.settleBridges(open: open)
    step("casa")
    func session(_ n: Int, seconds: Int, completed: Bool = true) -> StudySession {
        StudySession(id: fixedUUID(n), start: now.addingTimeInterval(Double(n) * 3600), seconds: seconds, plannedMinutes: 50, completed: completed, subject: nil)
    }
    var gifts: [String] = []
    for n in 0..<60 {
        if n == 25 { open.insert("porcellino") }
        if n == 40 { open.insert("ciccio") }
        let gift = g.rollGift(for: session(1000 + n, seconds: n % 9 == 4 ? 600 : 1500 + n * 40, completed: n % 11 != 7), streakDays: n % 15)
        switch gift {
        case .notEligible: gifts.append("non conta")
        case .progress: gifts.append("riserva")
        case .complete: gifts.append("completo")
        case .found(let drop): gifts.append(drop.item + "/" + drop.rarity.title)
        }
        if n == 24 || n == 59 { step("regali-\(n)") }
    }
    _ = g.rollGift(for: session(1059, seconds: 3000), streakDays: 3)
    step("stesso focus", ["regali": gifts])
    let welcomes = g.buildBridges(g.pendingBridges(open: open), welcoming: g.pendingWelcomes(open: open))
    step("ponti", ["benvenuti": welcomes.map { [$0.island, $0.item, $0.placement != nil ? "messa" : "cassetta"] }])
    g.showIsland("gattino")
    var placed: [Any] = []
    for (id, col, row) in [("tavolino", 6, 7), ("sdraio", 7, 7), ("lampione", 0, 0), ("casetta-gatto", 9, 9), ("cesto-carote", 8, 8), ("panchina", 6, 9)] {
        placed.append(opt(g.place(id, at: GardenTile(col: col, row: row)).map { [$0.col, $0.row] }))
    }
    let somewhere = (0..<4).map { _ in opt(g.placeSomewhere("margherite").map { tileJSON($0.tile) }) }
    let first = g.placements(on: "gattino").first!
    let moved = [g.move(first.id, to: GardenTile(col: 9, row: 0)), g.move(first.id, to: GardenTile(col: 0, row: 0)), g.rotate(first.id),
                 g.move(first.id, to: GardenTile(col: 3, row: 9), turned: true, on: "porcellino")]
    let corners = g.takeNewCorners()
    g.remove(g.placements(on: "gattino").last!.id)
    g.setCompanionTile("gattino", to: GardenTile(col: 4, row: 4))
    g.setCompanionTile("pianty", to: GardenTile(col: 40, row: 4))
    let guests = [g.welcomeGuest("pettirosso", day: "2026-10-26", reason: "Bagnetto uccelli"), g.welcomeGuest("pettirosso", day: "2026-10-27", reason: "x"),
                  g.welcomeGuest("volpe", day: "2026-10-28", reason: "L'angolo del tè")]
    step("mosse", ["messe": placed, "aCaso": somewhere, "spostate": moved, "angoliNuovi": corners,
                   "ospiti": guests.map { [$0.isFirst, $0.gift?.item ?? "niente"] as [Any] },
                   "compagnoPianty": tileJSON(g.companionTile("pianty", index: 0)), "compagnoRiccio": tileJSON(g.companionTile("riccio", index: 4)),
                   "canPlace": [g.canPlace("casetta-gatto", at: GardenTile(col: 5, row: 8), on: "porcellino"), g.canPlace("amaca", at: GardenTile(col: 8, row: 8), turned: true)],
                   "copie": g.count(of: "margherite"), "file": savedFileJSON(directory)])
    let again = Garden(directory: directory)
    again.isIslandOpen = { open.contains($0) }
    var reread = gardenStateJSON(again)
    reread["passo"] = "riletto"
    steps.append(reread)
    g.reset()
    step("cancellato", ["fileDopoReset": fm.fileExists(atPath: directory.appendingPathComponent("giardino.json").path)])
    return ["passi": steps]
}

/// Tutto il giardino che non dipende da una cartella di dati.
func gardenSyntheticJSON() throws -> [String: Any] {
    [
        "catalogo": catalogJSON(), "regali": dropsJSON(), "griglia": gardenGridJSON(), "terreno": terrainJSON(), "mondo": worldJSON(),
        "cielo": skyJSON(), "angoli": cornersJSON(), "compagni": companionsJSON(), "ospiti": visitorsJSON(), "giardino": try gardenStepsJSON(),
    ]
}

/// Per una cartella di dati con `giardino.json`, dopo la lettura: decide la casa, applica le regole delle isole e calcola i ponti, come all'avvio dell'app.
func gardenAfterLaunchJSON(_ g: Garden, directory: URL) -> [String: Any] {
    let open: Set<String> = ["pianty", "porcellino", "gattino"]
    g.isIslandOpen = { open.contains($0) }
    g.adoptHome("gattino")
    g.settleRules()
    g.settleBridges(open: open)
    var state = gardenStateJSON(g)
    state["avvisoRegole"] = opt(g.takeRulesNotice().map { ["spostate": $0.moved, "tornate": $0.returned, "riga": $0.line] as [String: Any] })
    state["file"] = relativeFiles(in: directory)
    return state
}
