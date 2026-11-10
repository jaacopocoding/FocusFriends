// Rifà in TypeScript quello che tests/genera-attesi/giardino.swift ricava dal giardino con dati inventati e sempre uguali: il contratto
// (contratto.test.ts) lo confronta con tests/fixtures/attesi/_giardino.json, generato dalla versione per Mac.

import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Garden, rulesReportLine } from "../src/core/garden.ts";
import {
  albumSpreads, companionHeight, completedSpreads, GARDEN_ITEMS, gardenImage, islandRule, isStarter, itemNumber, litImage, nameWithArticle,
  RARITY_TITLES, rarityOf, sides, swayStrength, universalItems, welcomeGift, wrongIslandLine,
} from "../src/core/gardenCatalog.ts";
import { AFFINITIES, GARDEN_POSES, poseFrames, poseImage, route, standingTiles } from "../src/core/gardenCompanions.ts";
import { cornerDistance, formedCorners, GARDEN_CORNERS } from "../src/core/gardenCorners.ts";
import {
  chances, credit, DropStream, giftCostSeconds, giftLine, giftProgress, hash, hasSomethingToFind, minutesToNextGift, mixedHash, nextGiftLine,
  startingDropState,
} from "../src/core/gardenDrops.ts";
import type { GardenGift } from "../src/core/gardenDrops.ts";
import {
  BRIDGES, bridgeId, bridgePieceCenters, bridgeSpan, canPlaceFootprint, decals, DECAL_ANCHORS, defaultCompanionTile, edgeSequence, freeOrigins,
  grassGrid, grassWeightsFor, HILL_BELOW_RATIO, HILL_HEIGHT_RATIO, HILL_WIDTH_RATIO, hillFrame, islandCorner, islandSizeFor, ISLANDS, landmarkTiles,
  legacyPathTiles, linkArms, nearestOrigin, nearestWalkable, newcomers, occupiedTiles, pathLandings, pathTiles, pathVariants, pathWeightsFor,
  pendingBridges, terrainTag, tileFromLegacy, tileKey, WORLD_EXTENT, WORLD_REACH,
} from "../src/core/gardenGrid.ts";
import type { GardenPlacement, GardenTile } from "../src/core/gardenGrid.ts";
import {
  burstStar, butterfly, cornerFirefly, drift, firefly, fireflyAmount, lampAmount, lightAt, lightMultiplier, particle, particleCount, particleKind,
  ripple, SEASONS, seasonOf, smoke, smokeAmount, sparkle, sunrise, sunset, sway, wind,
} from "../src/core/gardenSky.ts";
import type { GardenParticleKind } from "../src/core/gardenSky.ts";
import { arrival, daySlotOf, entryRoute, GARDEN_VISITORS, isRareVisitor, reasonText, visitorCame, visitorImage } from "../src/core/gardenVisitors.ts";
import type { GardenDaySlot } from "../src/core/gardenVisitors.ts";
import { GARDEN_INTERACTIONS, interactionCandidates, interactionDuration, interactionImage, pickInteraction } from "../src/core/gardenInteractions.ts";
import type { StudySession } from "../src/core/log.ts";
import { DAY_MS, dayString } from "../src/core/time.ts";

/** Come `(x * 1000).rounded() / 1000` di Swift (a metà si allontana dallo zero). */
export const r = (x: number): number => { const y = x * 1000; return (y < 0 ? -Math.round(-y) : Math.round(y)) / 1000; };
const t = (tile: GardenTile): number[] => [tile.col, tile.row];
const tile = (col: number, row: number): GardenTile => ({ col, row });
export const fixedId = (n: number): string => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const rarity = (x: Parameters<typeof rarityOf>[0]) => RARITY_TITLES[rarityOf(x)];
const DAY_SLOTS: readonly GardenDaySlot[] = ["morning", "day", "evening", "night"];

function catalogJson(): Record<string, unknown> {
  const found = new Set(GARDEN_ITEMS.slice(0, 16).map((x) => x.id));
  return {
    oggetti: GARDEN_ITEMS.map((x) => ({
      id: x.id, numero: itemNumber(x.id), nome: x.name, articolo: nameWithArticle(x), rarita: rarity(x), isola: x.island, dotazione: isStarter(x),
      altezza: x.height, lati: sides(x), immagine: gardenImage(x), acceso: litImage(x), oscilla: swayStrength(x),
      luce: x.glow === null ? null : { r: x.glow.red, g: x.glow.green, b: x.glow.blue, raggio: x.glow.radius, alto: x.glow.top, forza: x.glow.strength, vibra: x.glow.flickers },
      regola: islandRule(x, "Gattino"), isolaSbagliata: wrongIslandLine(x, "Gattino"),
      ombra: x.castsShadow, sulLato: x.axial, pendenza: x.slope, siUnisce: x.joins, ingombro: [x.footprint.cols, x.footprint.rows],
    })),
    doppiePagine: albumSpreads().map((s) => ({ sinistra: s.left.items.map((x) => x.id), destra: s.right === null ? null : s.right.items.map((x) => x.id), pagina: s.left.index, pagine: s.left.count })),
    doppieComplete: [0, 6, 16, 30, 47].map((n) => completedSpreads((id) => GARDEN_ITEMS.slice(0, n).some((x) => x.id === id))),
    doppieSedici: completedSpreads((id) => found.has(id)),
    altezzeCompagni: ["pianty", "porcellino", "ciccio", "gattino", "riccio", "tartaruga", "nessuno"].map(companionHeight),
    benvenuti: ISLANDS.map((island) => welcomeGift(island, (id) => id === "annaffiatoio" || id === "cesto-carote")),
    universali: universalItems().length,
  };
}

function dropsJson(): Record<string, unknown> {
  const texts = ["", "a", "FocusFriends", "posto-REGALO-1", "àèìòù", "00000000-0000-4000-8000-000000000001", "terra-gattino/3,4,0"];
  const streams = [0, 1, 42, 4_294_967_295].map((seed) => { const s = new DropStream(seed); return Array.from({ length: 6 }, () => Math.round(s.next() * 1e9)); });
  const state = startingDropState();
  const credits = [];
  for (let i = 0; i < 420; i++) {
    const open = new Set(ISLANDS.slice(0, 1 + Math.min(Math.trunc(i / 90), 4)));
    const pool = GARDEN_ITEMS.filter((x) => x.island === null || open.has(x.island));
    const seconds = 1200 + (i * 37 % 3000), streak = (i * 7) % 20;
    const somethingBefore = hasSomethingToFind(state, pool);
    const drop = credit(fixedId(i), streak, seconds, state, pool);
    const gift: GardenGift = drop ? { kind: "found", drop } : somethingBefore ? { kind: "progress" } : { kind: "complete" };
    const left = minutesToNextGift(state, pool);
    const progress = giftProgress(state, pool);
    credits.push({
      oggetto: drop?.item ?? null, rarita: drop ? RARITY_TITLES[drop.rarity] : null, riserva: state.studyBank, mancano: left,
      strada: progress === null ? null : r(progress), riga: giftLine(gift, left), rigaMenu: nextGiftLine(left), dalRaro: state.sinceRare, dalLeggendario: state.sinceLegendary,
    });
  }
  const lines: string[] = [];
  for (const minutes of [null, 0, 1, 35]) {
    lines.push(giftLine({ kind: "progress" }, minutes), giftLine({ kind: "notEligible" }, minutes), giftLine({ kind: "complete" }, minutes));
    for (const rar of ["common", "rare", "legendary"] as const) lines.push(giftLine({ kind: "found", drop: { item: "lampione", rarity: rar } }, minutes));
    lines.push(giftLine({ kind: "found", drop: { item: "sconosciuto", rarity: "common" } }, minutes));
    lines.push(nextGiftLine(minutes));
  }
  return {
    hash: texts.map(hash), hashMescolato: texts.map(mixedHash), flussi: streams,
    costi: [0, 3, 4, 10, 47].map((n) => giftCostSeconds(n)),
    probabilita: [[0, 0], [3, 2700], [7, 1200], [14, 3000], [30, 2699]].map(([days, seconds]) => { const c = chances(days!, seconds!); return [r(c.rare), r(c.legendary)]; }),
    regali: credits, righe: lines,
  };
}

function gridJson(): Record<string, unknown> {
  const sentieri: Record<string, unknown> = {};
  for (const island of [...ISLANDS, "nessuna"]) {
    const bySize: Record<string, unknown> = {};
    for (let size = 8; size <= 10; size++) {
      const empty = new Set<string>();
      const near = nearestOrigin(tile(5, 5), { cols: 1, rows: 2 }, size, new Set([tileKey(tile(5, 5))]), island);
      bySize[String(size)] = {
        sentiero: pathTiles(island, size).map(t), approdi: pathLandings(island, size).map((l) => ({ lato: l.face, tessera: t(l.tile) })),
        liberi1: freeOrigins({ cols: 1, rows: 1 }, size, empty, island).length, liberi2: freeOrigins({ cols: 2, rows: 1 }, size, empty, island).map(t),
        vicino: near === null ? null : t(near),
      };
    }
    sentieri[island] = { grandezze: bySize, compagni: [0, 1, 2, 3, 4].map((i) => t(defaultCompanionTile(i, island))), casa: landmarkTiles(island).length };
  }
  const linked = new Set([tile(2, 2), tile(3, 2), tile(2, 3), tile(4, 4), tile(2, 1), tile(1, 2)].map(tileKey));
  const arms: number[] = [];
  for (let col = 0; col <= 5; col++) for (let row = 0; row <= 5; row++) for (const turned of [false, true]) arms.push(linkArms(tile(col, row), linked, turned));
  const occupied = new Set([tile(4, 4), tile(4, 5), tile(5, 4)].map(tileKey));
  const walk = nearestWalkable(tile(4, 4), 8, occupied);
  return {
    sentieri, vecchioSentiero: legacyPathTiles(10).map(t), compagniSenzaIsola: [0, 1, 2, 3].map((i) => t(defaultCompanionTile(i))),
    daPrato: Array.from({ length: 8 }, (_, i) => t(tileFromLegacy({ x: i * 0.15, y: 0.5 + i * 0.07 }, 8 + i % 3))), bracci: arms,
    camminabile: walk === null ? null : t(walk),
    vecchiCanPlace: Array.from({ length: 10 }, (_, i) => canPlaceFootprint({ cols: 1, rows: 1 }, tile(i, 3 + i % 3), 10, new Set())),
    grandezzaIsola: [-1, 0, 1, 2, 3, 4].map(islandSizeFor),
  };
}

function terrainJson(): Record<string, unknown> {
  const isole: Record<string, unknown> = {};
  for (const island of ISLANDS) {
    const tag = terrainTag(island);
    const seasons: Record<string, unknown> = {};
    for (const season of SEASONS) {
      const list = [];
      for (let col = 0; col < 10; col++) for (let row = 0; row < 3; row++) list.push(decals(col, row, season, (col + row) % 4 === 0, tag));
      seasons[season] = {
        erba: grassGrid(10, grassWeightsFor(season), tag), sentiero: pathVariants(30, pathWeightsFor(season), tag),
        dettagli: list.map((ds) => ds.map((d) => ({ immagine: d.image, gruppo: d.group, u: r(d.u), v: r(d.v), misura: r(d.size), specchio: d.flipped, ancora: DECAL_ANCHORS[d.group] }))),
      };
    }
    isole[island] = seasons;
  }
  const hill = hillFrame({ x: 120, y: 400 }, { x: 920, y: 404 });
  return {
    isole, erba8: grassGrid(8), bordi: [0, 1].map((face) => edgeSequence(face, 14)),
    collina: [r(hill.x), r(hill.y), r(hill.width), r(hill.height), r(hill.scale)],
    collinaRapporti: [r(HILL_WIDTH_RATIO), r(HILL_BELOW_RATIO), r(HILL_HEIGHT_RATIO)],
  };
}

function worldJson(): Record<string, unknown> {
  const opens = [["pianty"], ["pianty", "porcellino"], ["pianty", "gattino"], ["gattino", "riccio"], [...ISLANDS]].map((list) => new Set(list));
  return {
    estensione: WORLD_EXTENT, portata: [WORLD_REACH.left, WORLD_REACH.right, WORLD_REACH.depth],
    ponti: BRIDGES.map((b) => {
      const small = bridgeSpan(b, 8)!, big = bridgeSpan(b, 10)!;
      return { id: bridgeId(b), colonne: b.alongColumns, piccolo: [small.from, small.to, small.across], grande: [big.from, big.to, big.across], pezzi: bridgePieceCenters(small.from, small.to) };
    }),
    angoli: ISLANDS.map((id) => { const c = islandCorner(id); return c ? [c.col, c.row] : []; }),
    daCostruire: opens.map((open) => pendingBridges(open, new Set(["pianty-porcellino"])).map(bridgeId)),
    nuovi: opens.map((open) => newcomers(open, new Set(["porcellino"]), "pianty")),
    pezziCorti: [bridgePieceCenters(3, 3), bridgePieceCenters(10, 14.5)],
  };
}

function skyJson(): Record<string, unknown> {
  const luce: Record<string, unknown> = {};
  for (const season of SEASONS) {
    const list = [];
    for (let i = 0; i <= 104; i++) {
      const l = lightAt(-1 + i * 0.25, season);
      list.push([r(l.darkness), r(l.tint.red), r(l.tint.green), r(l.tint.blue), r(l.tintStrength), r(lampAmount(l)), r(lightMultiplier(l).blue), r(fireflyAmount(season, l))]);
    }
    luce[season] = list;
  }
  const times = [0, 13.7, 250.3, 5000.9];
  const particelle: Record<string, unknown> = {};
  for (const kind of ["petal", "leaf", "snow"] as GardenParticleKind[]) {
    const dove = [];
    for (let index = 0; index < 6; index++) for (const time of times) {
      const p = particle(kind, index, time, 900, 600);
      dove.push([r(p.x), r(p.y), r(p.size), r(p.angle), r(p.alpha), r(p.tone)]);
    }
    particelle[kind] = { quante: particleCount(kind), dove };
  }
  const each = <T>(count: number, f: (i: number, time: number) => T): T[] => Array.from({ length: count }, (_, i) => times.map((time) => f(i, time))).flat();
  return {
    luce, particelle, stagioni: Array.from({ length: 12 }, (_, m) => seasonOf(Date.UTC(2026, m, 15, 12))),
    albe: SEASONS.map((s) => [sunrise(s), sunset(s), wind(s), smokeAmount(s)]),
    cade: SEASONS.map((s) => particleKind(s) ?? "niente"),
    lucciole: each(4, (i, time) => { const f = firefly(i, time, 900, 600); return [r(f.x), r(f.y), r(f.glow)]; }),
    vento: each(6, (i, time) => r(sway(time, i, 9 - i, i / 7, i / 5))),
    luccichii: each(3, (i, time) => { const s = sparkle(i, time); return [r(s.x), r(s.y), r(s.glow)]; }),
    cerchi: times.map((time) => { const p = ripple(time, 0.3); return [r(p.x), r(p.y), r(p.phase), r(p.alpha)]; }),
    fumo: each(9, (i, time) => { const s = smoke(i, time, 0.8); return [r(s.dx), r(s.dy), r(s.radius), r(s.alpha)]; }),
    cadute: each(5, (i, time) => { const d = drift(i, time, 4.5); return [r(d.progress), r(d.x), r(d.spin), r(d.alpha)]; }),
    farfalle: each(3, (i, time) => { const b = butterfly(i, time); return [r(b.x), r(b.y), r(b.flap)]; }),
    luccioleAngolo: each(3, (i, time) => { const f = cornerFirefly(i, time); return [r(f.x), r(f.y), r(f.glow)]; }),
    stelline: Array.from({ length: 18 }, (_, i) => [0, 0.1, 0.5, 0.9, 1].map((p) => { const s = burstStar(i, p); return [r(s.dx), r(s.dy), r(s.size), r(s.angle), r(s.alpha)]; })).flat(),
  };
}

function samplePlacements(): GardenPlacement[] {
  const spec: Array<[string, number, number, boolean]> = [
    ["tavolino", 1, 1, false], ["sdraio", 3, 1, false], ["panchina", 6, 6, false], ["lampione", 8, 8, false], ["lampione", 7, 6, false],
    ["aiuola", 4, 4, false], ["annaffiatoio", 4, 6, false], ["margherite", 0, 6, false], ["tulipani", 1, 7, false], ["lavanda", 2, 6, false],
    ["papaveri", 0, 8, false], ["margherite", 1, 8, false], ["amaca", 6, 1, true], ["tiragraffi", 7, 3, false], ["funghi", 9, 9, false],
    ["felci", 9, 7, false], ["mughetti", 8, 9, false], ["picnic", 5, 8, false], ["bandierine", 4, 9, false], ["cesto-carote", 3, 8, false],
    ["bagnetto", 2, 2, false], ["girasole", 2, 0, false], ["tana-foglie", 0, 3, false], ["mucchio-foglie", 1, 4, false], ["tronco-cavo", 0, 5, false],
  ];
  return spec.map(([item, col, row, turned], index) => ({ id: fixedId(100 + index), item, island: "", col, row, turned }));
}

function cornersJson(): Record<string, unknown> {
  const all = samplePlacements();
  const formati = [0, 2, 5, 9, 12, 16, 20, 25].map((count) => {
    const list = all.slice(0, count);
    const result: Record<string, number[]> = {};
    for (const [key, ids] of formedCorners(list)) result[key] = ids.map((id) => list.findIndex((p) => p.id === id));
    return result;
  });
  return {
    formati, distanze: all.map((a) => all.map((b) => Math.min(cornerDistance(a, b), 99))), nomi: GARDEN_CORNERS.map((c) => c.name),
  };
}

function companionsJson(): Record<string, unknown> {
  const occupied = new Set([tile(2, 0), tile(2, 1), tile(2, 2), tile(2, 3), tile(4, 4), tile(5, 4)].map(tileKey));
  const routes: Array<[GardenTile, GardenTile]> = [[tile(0, 0), tile(4, 0)], [tile(0, 0), tile(0, 0)], [tile(1, 1), tile(7, 7)], [tile(0, 0), tile(2, 2)], [tile(6, 6), tile(0, 7)]];
  const short = route(tile(0, 0), tile(7, 7), 8, new Set(), 5);
  return {
    pose: ["pianty", "porcellino", "ciccio", "gattino", "riccio", "tartaruga"].flatMap((pet) => GARDEN_POSES.map((pose) => ({
      frame: poseFrames(pet, pose), immagini: [0, 0.4, 1.3, 7.9].map((time) => poseImage(pet, pose, time)?.replace("/", "_") ?? null),
    }))),
    intorno: [[tile(0, 0)], [tile(3, 3), tile(4, 3)], [tile(7, 7)]].map((fp) => standingTiles(fp, 8).map(t)),
    strade: routes.map(([from, to]) => route(from, to, 8, occupied)?.map(t) ?? null),
    stradaCorta: short === null ? null : short.map(t),
    affinita: AFFINITIES.map((a) => `${a.pet}/${a.corner}/${a.item}/${a.pose}`),
  };
}

/** I compagni che usano le cose: la tabella e quali sceglierebbero (come `interactionsJSON` nel generatore del Mac). */
function interactionsJson(): Record<string, unknown> {
  const tabella = GARDEN_INTERACTIONS.map((i) => ({
    compagno: i.pet, oggetto: i.item, effetto: i.effect, scala: i.scale, x: i.x, y: i.y, immagine: interactionImage(i).replace("/", "_"), durata: interactionDuration(i),
  }));
  const extra: Array<[string, number, number]> = [["cesto-cuscino", 8, 4], ["tunnel", 5, 6], ["casetta-uccelli", 3, 6]];
  const all = [...samplePlacements(), ...extra.map(([item, col, row], index) => ({ id: fixedId(300 + index), item, island: "", col, row, turned: false }))];
  const occupied = occupiedTiles(all);
  const scene = [];
  for (const pet of ["gattino", "porcellino", "ciccio", "riccio"]) {
    for (const from of [tile(5, 5), tile(0, 0), tile(9, 0), tile(3, 3)]) {
      for (const last of [null, fixedId(102)]) {
        const found = interactionCandidates(pet, all, from, 10, occupied, last);
        const index = (c: { placement: GardenPlacement }) => all.findIndex((p) => p.id === c.placement.id);
        scene.push({
          scelte: found.map((c) => [index(c), c.route.map(t)]),
          sorteggi: [0, 0.3, 0.6, 0.9, 0.999].map((v) => { const c = pickInteraction(found, v); return c === null ? null : index(c); }),
        });
      }
    }
  }
  return { tabella, scene };
}

function visitorsJson(): Record<string, unknown> {
  const all = samplePlacements();
  const formed = formedCorners(all);
  const arrivi = [];
  let day = Date.UTC(2026, 0, 1);
  for (let i = 0; i < 40; i++) {
    for (const slot of DAY_SLOTS) {
      const found = arrival(dayString(day), slot, all, formed, seasonOf(day));
      arrivi.push(found === null ? null : {
        ospite: found.visitor.id, copia: all.indexOf(found.placement), oggetto: found.item, angolo: found.corner, motivo: reasonText(found.item, found.corner),
      });
    }
    day += 9 * DAY_MS;
  }
  const occupied = occupiedTiles(all);
  return {
    arrivi, fasce: Array.from({ length: 49 }, (_, i) => daySlotOf(i * 0.5)),
    ingressi: [tile(5, 5), tile(0, 0), tile(9, 2)].map((goal) => entryRoute(goal, 10, occupied)?.map(t) ?? null),
    venuti: GARDEN_VISITORS.map((v) => `${v.name}/${visitorCame(v)}/${isRareVisitor(v)}/giardino_${visitorImage(v)}`),
  };
}

// ---- un giardino che cambia passo per passo

export function gardenStateJson(g: Garden): Record<string, unknown> {
  const isole: Record<string, unknown> = {};
  for (const island of ISLANDS) {
    isole[island] = {
      copie: g.placementsOn(island).map((p) => ({ oggetto: p.item, isola: p.island, col: p.col, row: p.row, girata: p.turned })),
      grandezza: g.islandSizeOf(island), cassetta: g.tray(island).map((x) => x.id), angoli: [...g.formedCornersOn(island).keys()].sort(),
    };
  }
  const progress = g.nextGiftProgress;
  return {
    trovati: Object.keys(g.drops.found).sort(), riserva: g.drops.studyBank, dalRaro: g.drops.sinceRare, dalLeggendario: g.drops.sinceLegendary,
    nuove: [...g.unseen].sort(), casa: g.home, isole, angoli: [...g.corners], ponti: [...g.bridges], accolti: [...g.welcomed],
    mancano: g.minutesToNextGift, strada: progress === null ? null : r(progress),
    compagni: Object.fromEntries([...g.companionTiles].map(([pet, x]) => [pet, t(x)])),
    ospiti: Object.fromEntries(Object.entries(g.guests).map(([id, x]) => [id, { primo: x.first, visite: x.visits, motivo: x.reason }])),
  };
}

function savedFileJson(directory: string): unknown {
  const path = join(directory, "giardino.json");
  if (!existsSync(path)) return null;
  const object = JSON.parse(readFileSync(path, "utf8")) as Record<string, unknown>;
  if (Array.isArray(object["placements"])) object["placements"] = (object["placements"] as Array<Record<string, unknown>>).map((p, index) => ({ ...p, id: `copia-${index}` }));
  return object;
}

function gardenStepsJson(): Record<string, unknown> {
  const directory = mkdtempSync(join(tmpdir(), "ff-giardino-passi-"));
  try {
    const open = new Set(["gattino"]);
    const g = new Garden(directory);
    g.isIslandOpen = (id) => open.has(id);
    const steps: Array<Record<string, unknown>> = [];
    const step = (name: string, extra: Record<string, unknown> = {}): void => { steps.push({ ...gardenStateJson(g), passo: name, ...extra }); };
    step("nuovo");
    g.adoptHome("gattino");
    g.settleBridges(open);
    step("casa");
    const session = (n: number, seconds: number, completed = true): StudySession => ({ id: fixedId(n), start: 0, seconds, plannedMinutes: 50, completed });
    const gifts: string[] = [];
    for (let n = 0; n < 60; n++) {
      if (n === 25) open.add("porcellino");
      if (n === 40) open.add("ciccio");
      const gift = g.rollGift(session(1000 + n, n % 9 === 4 ? 600 : 1500 + n * 40, n % 11 !== 7), n % 15);
      gifts.push(gift.kind === "notEligible" ? "non conta" : gift.kind === "progress" ? "riserva" : gift.kind === "complete" ? "completo" : `${gift.drop.item}/${RARITY_TITLES[gift.drop.rarity]}`);
      if (n === 24 || n === 59) step(`regali-${n}`);
    }
    g.rollGift(session(1059, 3000), 3);
    step("stesso focus", { regali: gifts });
    const welcomes = g.buildBridges(g.pendingBridges(open), g.pendingWelcomes(open));
    step("ponti", { benvenuti: welcomes.map((w) => [w.island, w.item, w.placement !== null ? "messa" : "cassetta"]) });
    g.showIsland("gattino");
    const placed = ([["tavolino", 6, 7], ["sdraio", 7, 7], ["lampione", 0, 0], ["casetta-gatto", 9, 9], ["cesto-carote", 8, 8], ["panchina", 6, 9]] as const)
      .map(([id, col, row]) => { const p = g.place(id, tile(col, row)); return p === null ? null : [p.col, p.row]; });
    const somewhere = [0, 1, 2, 3].map(() => { const p = g.placeSomewhere("margherite"); return p === null ? null : t(p); });
    const first = g.placementsOn("gattino")[0]!;
    const moved = [g.move(first.id, tile(9, 0)), g.move(first.id, tile(0, 0)), g.rotate(first.id), g.move(first.id, tile(3, 9), true, "porcellino")];
    const corners = g.takeNewCorners();
    const onGattino = g.placementsOn("gattino");
    g.remove(onGattino[onGattino.length - 1]!.id);
    g.setCompanionTile("gattino", tile(4, 4));
    g.setCompanionTile("pianty", tile(40, 4));
    const guests = [g.welcomeGuest("pettirosso", "2026-10-26", "Bagnetto uccelli"), g.welcomeGuest("pettirosso", "2026-10-27", "x"), g.welcomeGuest("volpe", "2026-10-28", "L'angolo del tè")];
    step("mosse", {
      messe: placed, aCaso: somewhere, spostate: moved, angoliNuovi: corners, ospiti: guests.map((x) => [x.isFirst, x.gift?.item ?? "niente"]),
      compagnoPianty: t(g.companionTile("pianty", 0)), compagnoRiccio: t(g.companionTile("riccio", 4)),
      canPlace: [g.canPlace("casetta-gatto", tile(5, 8), false, "porcellino"), g.canPlace("amaca", tile(8, 8), true)],
      copie: g.count("margherite"), file: savedFileJson(directory),
    });
    const again = new Garden(directory);
    again.isIslandOpen = (id) => open.has(id);
    steps.push({ ...gardenStateJson(again), passo: "riletto" });
    g.reset();
    step("cancellato", { fileDopoReset: existsSync(join(directory, "giardino.json")) });
    return { passi: steps };
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

/** Tutto il giardino che non dipende da una cartella di dati (`_giardino.json`), sezione per sezione. */
export function gardenSyntheticJson(): Record<string, unknown> {
  return {
    catalogo: catalogJson(), regali: dropsJson(), griglia: gridJson(), terreno: terrainJson(), mondo: worldJson(),
    cielo: skyJson(), angoli: cornersJson(), compagni: companionsJson(), interazioni: interactionsJson(), ospiti: visitorsJson(), giardino: gardenStepsJson(),
  };
}

/** Dopo la lettura di una cartella di dati: la casa, le regole delle isole e i ponti, come all'avvio dell'app. */
export function gardenAfterLaunchJson(g: Garden, files: () => string[]): Record<string, unknown> {
  const open = new Set(["pianty", "porcellino", "gattino"]);
  g.isIslandOpen = (id) => open.has(id);
  g.adoptHome("gattino");
  g.settleRules();
  g.settleBridges(open);
  const state = gardenStateJson(g);
  const notice = g.takeRulesNotice();
  state["avvisoRegole"] = notice === null ? null : { spostate: notice.moved, tornate: notice.returned, riga: rulesReportLine(notice) };
  state["file"] = files();
  return state;
}
