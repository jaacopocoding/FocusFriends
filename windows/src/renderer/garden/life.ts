// La vita sull'isola mostrata (GardenView.advanceWalkers e gli ospiti in GardenWindow.swift): il compagno passeggia da una tessera libera all'altra e,
// se c'è un angolo che gli piace, ogni tanto ci va e fa la sua posa (il gattino dorme, il porcellino mangia…); in certe fasce della giornata arriva un
// ospite, attirato da una cosa o da un angolo, cammina fino a lì, si ferma e se ne va. Qui ci sono solo gli stati; il disegno legge `life` in scene.ts.

import { applyTurn, itemWithId } from "../../core/gardenCatalog.ts";
import { AFFINITIES, POSE_DURATION, route, standingTiles } from "../../core/gardenCompanions.ts";
import type { GardenAffinity } from "../../core/gardenCompanions.ts";
import { formedCorners } from "../../core/gardenCorners.ts";
import { interactionCandidates, interactionDuration, interactionOf, pickInteraction } from "../../core/gardenInteractions.ts";
import type { InteractionCandidate } from "../../core/gardenInteractions.ts";
import { mixedHash } from "../../core/gardenDrops.ts";
import { footprintTiles, isWalkable, landmarkTiles, occupiedTiles, tileKey } from "../../core/gardenGrid.ts";
import type { GardenTile } from "../../core/gardenGrid.ts";
import { arrival, daySlotOf, entryRoute, visitorImage } from "../../core/gardenVisitors.ts";
import type { Attraction } from "../../core/gardenVisitors.ts";
import type { GardenData, GardenIslandData } from "../../shared/gardenApi.ts";
import { life } from "./scene.ts";

const random = (low: number, high: number): number => low + Math.random() * (high - low);

interface Walker {
  from: GardenTile;
  to: GardenTile;
  progress: number;
  rest: number;
  /** Sta andando in un angolo a fare una posa: il resto della strada. */
  errand: { route: GardenTile[]; affinity: GardenAffinity } | null;
  /** Sta facendo la posa. */
  activity: { affinity: GardenAffinity; remaining: number } | null;
  /** Da quanti secondi non fa niente di speciale (parte alto, così la prima posa viene presto). */
  idle: number;
  /** Se sta usando una cosa (`GardenInteractions`), e l'ultima che ha usato (non la riprende subito). */
  interacting?: Interacting | null;
  lastInteraction?: string | null;
}

/** Un compagno che va a usare una cosa: la strada che manca, poi il tempo che ci sta (sparisce, e la cosa diventa la scena con lui dentro). */
interface Interacting {
  candidate: InteractionCandidate;
  route: GardenTile[];
  /** Quanto manca alla fine, da quando è arrivato (null finché cammina), e quando è arrivato (l'ora degli effetti). */
  remaining: number | null;
  started: number;
}

const walkers = new Map<string, Walker>();

interface Visitor {
  attraction: Attraction;
  island: string;
  path: GardenTile[];
  index: number;
  next: number;
  progress: number;
  phase: "arriving" | "staying" | "leaving";
  remaining: number;
  greeted: boolean;
  fade: number;
  facingRight: boolean;
}

let visitor: Visitor | null = null;
/** Le fasce della giornata in cui è già venuto qualcuno (o nessuno) da quando la finestra è aperta: non si ripete. */
let visited = new Set<string>();
let visitorClock = 0, visitorCheck = 0;

function occupiedOn(island: GardenIslandData): Set<string> {
  const result = occupiedTiles(island.placements);
  for (const t of landmarkTiles(island.id)) result.add(tileKey(t));
  return result;
}

/** Il compagno è stato portato su un'altra tessera (con il mouse): parte da lì. */
export function placeCompanion(pet: string, t: GardenTile): void {
  walkers.set(pet, { from: t, to: t, progress: 1, rest: 3, errand: null, activity: null, idle: 20 });
}

/** Riparte da capo con gli ospiti (alla riapertura, o cambiando isola): in questa fascia della giornata viene di nuovo lo stesso. */
export function resetVisitors(): void {
  visitor = null;
  visited = new Set();
  visitorClock = 0;
  visitorCheck = 0;
}

/** Se un angolo che gli piace c'è (e nessun altro ci sta andando), ogni tanto ci va: la strada più corta fino a una tessera accanto a una cosa dell'angolo. */
function startErrand(pet: string, walker: Walker, island: GardenIslandData, occupied: ReadonlySet<string>, taken: ReadonlySet<string>): Walker["errand"] {
  if (walker.idle <= 25 || Math.random() >= 0.4) return null;
  const formed = formedCorners(island.placements);
  const options = AFFINITIES.filter((a) => a.pet === pet && formed.has(a.corner));
  const affinity = options[Math.floor(Math.random() * options.length)];
  if (!affinity) return null;
  const ids = formed.get(affinity.corner)!;
  const placement = island.placements.find((p) => ids.includes(p.id) && p.item === affinity.item);
  const item = placement && itemWithId(placement.item);
  if (!placement || !item) return null;
  let best: GardenTile[] | null = null;
  for (const t of standingTiles(footprintTiles(applyTurn(item.footprint, placement.turned), placement), island.size)) {
    if (!isWalkable(t, island.size, occupied) || taken.has(tileKey(t))) continue;
    const way = route(walker.from, t, island.size, occupied);
    if (way && (best === null || way.length < best.length)) best = way;
  }
  return best ? { route: best, affinity } : null;
}

/** Ogni tanto, dopo una passeggiata (un po' dopo l'ultima cosa fatta), va a usare una cosa della sua isola che sa usare (`GardenInteractions`). */
function startInteraction(pet: string, walker: Walker, island: GardenIslandData, occupied: ReadonlySet<string>, taken: ReadonlySet<string>): Interacting | null {
  if (walker.idle <= 15 || Math.random() >= 0.35) return null;
  const chosen = pickInteraction(interactionCandidates(pet, island.placements, walker.from, island.size, occupied, walker.lastInteraction ?? null, taken), Math.random());
  return chosen ? { candidate: chosen, route: [...chosen.route], remaining: null, started: 0 } : null;
}

/** Un passo di chi va a usare una cosa (si chiama quando è fermo su una tessera): cammina fino alla tessera accanto, poi ci sta e alla fine ricompare lì. */
function advanceInteraction(walker: Walker, dt: number, size: number, occupied: ReadonlySet<string>, taken: ReadonlySet<string>): boolean {
  const it = walker.interacting!;
  if (it.remaining !== null) {
    it.remaining -= dt;
    if (it.remaining > 0) return it.candidate.interaction.effect !== "none";
    // finito: ricompare accanto, e per un po' fa altro
    walker.interacting = null;
    walker.lastInteraction = it.candidate.placement.id;
    walker.idle = 0;
    walker.rest = 1.5;
    return true;
  }
  walker.rest -= dt;
  if (walker.rest > 0) return false;
  const next = it.route.shift();
  if (next) {
    if (isWalkable(next, size, occupied) && !taken.has(tileKey(next))) { walker.to = next; walker.progress = 0; } else { walker.interacting = null; walker.idle = 0; }      // la strada si è chiusa
    return true;
  }
  const [low, high] = interactionDuration(it.candidate.interaction);
  it.remaining = random(low, high);
  it.started = life.time;
  return true;
}

/** Per le prove: il compagno sta già usando la prima copia di `item` sull'isola mostrata (se sa usarla). */
export function showInteraction(data: GardenData, pet: string, item: string): void {
  const island = data.islands.find((i) => i.id === pet);
  const placement = island?.placements.find((p) => p.item === item);
  const interaction = interactionOf(pet, item);
  if (!island || !placement || !interaction) return;
  const walker = walkers.get(pet) ?? { from: placement, to: placement, progress: 1, rest: 1, errand: null, activity: null, idle: 0 };
  walker.interacting = { candidate: { placement, interaction, route: [] }, route: [], remaining: 30, started: life.time - 1 };
  walkers.set(pet, walker);
}

/** Fa fare un passo (di `dt` secondi) al compagno dell'isola mostrata. Ritorna se si muove. `carried`: il compagno che si sta portando con il mouse. */
function advanceWalker(data: GardenData, dt: number, carried: string | null): boolean {
  const island = data.islands.find((i) => i.id === data.shown);
  if (!island?.companion || life.reduceMotion || carried === island.id) return false;
  const pet = island.id, home = island.companion, size = island.size;
  const occupied = occupiedOn(island);
  let walker = walkers.get(pet) ?? { from: home, to: home, progress: 1, rest: random(1, 4), errand: null, activity: null, idle: 20 };
  // gli hanno messo un oggetto sotto i piedi (o l'isola è cambiata): torna a casa
  if (!isWalkable(walker.from, size, occupied) || !isWalkable(walker.to, size, occupied)) walker = { ...walker, from: home, to: home, progress: 1, rest: 1, errand: null, activity: null };
  // la cosa che stava usando non c'è più, o è stata spostata: smette (e ricompare accanto)
  if (walker.interacting) {
    const was = walker.interacting.candidate.placement, now = island.placements.find((p) => p.id === was.id);
    if (!now || now.col !== was.col || now.row !== was.row || now.turned !== was.turned) { walker.interacting = null; walker.idle = 0; }
  }
  // l'angolo si è sciolto mentre ci andava o ci stava: smette
  const formed = formedCorners(island.placements);
  if (walker.errand && !formed.has(walker.errand.affinity.corner)) walker.errand = null;
  if (walker.activity && !formed.has(walker.activity.affinity.corner)) { walker.activity = null; walker.idle = 0; }
  walker.idle += dt;
  const taken = new Set<string>();
  let moving = false;
  if (walker.progress < 1) {
    walker.progress = Math.min(1, walker.progress + dt / 1.3);
    moving = true;
  } else {
    walker.from = walker.to;
    if (walker.interacting) {
      if (advanceInteraction(walker, dt, size, occupied, taken)) moving = true;
    } else if (walker.activity) {
      // fa la posa: i fotogrammi cambiano, quindi si ridisegna
      walker.activity.remaining -= dt;
      moving = true;
      if (walker.activity.remaining <= 0) { walker.activity = null; walker.idle = 0; walker.rest = 1.2; }
    } else if (walker.errand) {
      walker.rest -= dt;
      if (walker.rest <= 0) {
        if (walker.errand.route.length === 0) {
          const [low, high] = POSE_DURATION[walker.errand.affinity.pose];
          walker.activity = { affinity: walker.errand.affinity, remaining: random(low, high) };
          walker.errand = null;
        } else {
          const next = walker.errand.route.shift()!;
          if (isWalkable(next, size, occupied) && !taken.has(tileKey(next))) {
            walker.to = next;
            walker.progress = 0;
            moving = true;
          } else {
            walker.errand = null;      // la strada si è chiusa: lascia perdere
          }
        }
      }
    } else {
      walker.rest -= dt;
      if (walker.rest <= 0) {
        const errand = startErrand(pet, walker, island, occupied, taken);
        const interacting = errand ? null : startInteraction(pet, walker, island, occupied, taken);
        if (errand) {
          walker.errand = errand;
          walker.rest = 0;
        } else if (interacting) {
          walker.interacting = interacting;
          walker.rest = 0;
        } else {
          const around = [[1, 0], [-1, 0], [0, 1], [0, -1]].map(([dc, dr]) => ({ col: walker.from.col + dc!, row: walker.from.row + dr! }));
          const free = around.filter((t) => isWalkable(t, size, occupied) && !taken.has(tileKey(t)));
          const next = free[Math.floor(Math.random() * free.length)];
          if (next) { walker.to = next; walker.progress = 0; moving = true; }
          walker.rest = random(1.5, 5);
        }
      }
    }
  }
  walkers.set(pet, walker);
  return moving;
}

/** Verso dove guarda camminando da una tessera all'altra (i disegni guardano a destra). */
function facing(from: GardenTile, to: GardenTile, current: boolean): boolean {
  const dx = (to.col - from.col) - (to.row - from.row);
  return dx === 0 ? current : dx > 0;
}

/** In questa fascia della giornata viene qualcuno? Se sì, dove si ferma e da dove entra. */
function tryArrival(data: GardenData, hour: number): void {
  const island = data.islands.find((i) => i.id === data.shown);
  if (!island) return;
  const slot = daySlotOf(hour);
  const key = `${data.day}-${slot}`;
  if (visited.has(key)) return;
  visited.add(key);
  const formed = formedCorners(island.placements);
  const found = arrival(data.day, slot, island.placements, formed, data.season);
  const item = found && itemWithId(found.placement.item);
  if (!found || !item) return;
  const occupied = occupiedOn(island);
  const busy = new Set([...walkers.values()].flatMap((w) => [tileKey(w.from), tileKey(w.to)]));
  const stands = standingTiles(footprintTiles(applyTurn(item.footprint, found.placement.turned), found.placement), island.size)
    .filter((t) => isWalkable(t, island.size, occupied) && !busy.has(tileKey(t)));
  if (stands.length === 0) return;
  const start = mixedHash(`ospite-posto-${key}`) % stands.length;
  for (let offset = 0; offset < stands.length; offset++) {
    const path = entryRoute(stands[(start + offset) % stands.length]!, island.size, occupied);
    if (!path) continue;
    visitor = { attraction: found, island: island.id, path, index: 0, next: 0, progress: 1, phase: "arriving", remaining: 0, greeted: false, fade: 0, facingRight: true };
    return;
  }
}

/** Fa avanzare l'ospite (se c'è) e, se non c'è, ogni tanto guarda se in questa fascia ne viene uno. Ritorna se qualcosa si muove. */
function advanceVisitor(data: GardenData, dt: number, hour: number): boolean {
  visitorClock += dt;
  const guest = visitor;
  if (!guest) {
    visitorCheck += dt;
    if (visitorClock <= 3 || visitorCheck <= 1) return false;
    visitorCheck = 0;
    tryArrival(data, hour);
    return visitor !== null;
  }
  const island = data.islands.find((i) => i.id === guest.island);
  if (!island || island.id !== data.shown) { visitor = null; return true; }
  // la cosa che l'ha attirato è stata tolta, o gli hanno messo qualcosa sotto i piedi: se ne va
  const occupied = occupiedOn(island);
  if (guest.phase !== "leaving" && (!island.placements.some((p) => p.id === guest.attraction.placement.id)
    || occupied.has(tileKey(guest.path[guest.index]!)) || occupied.has(tileKey(guest.path[guest.next]!)))) guest.phase = "leaving";
  if (guest.phase !== "leaving") guest.fade = Math.min(1, guest.fade + dt / 0.6);
  let moving = guest.fade < 1;
  if (guest.next !== guest.index) {
    // cammina: un passo al secondo
    guest.progress += dt;
    moving = true;
    if (guest.progress >= 1) { guest.index = guest.next; guest.progress = 1; }
  } else if (guest.phase === "arriving") {
    if (life.reduceMotion) {
      // senza movimento compare già lì
      guest.index = guest.next = guest.path.length - 1;
      guest.phase = "staying";
      guest.remaining = random(70, 130);
    } else if (guest.index < guest.path.length - 1) {
      guest.next = guest.index + 1;
      guest.progress = 0;
      guest.facingRight = facing(guest.path[guest.index]!, guest.path[guest.next]!, guest.facingRight);
      moving = true;
    } else {
      guest.phase = "staying";
      guest.remaining = random(70, 130);
    }
  } else if (guest.phase === "staying") {
    guest.remaining -= dt;
    // salutato, si trattiene ancora un po' e poi va
    if (guest.greeted) guest.remaining = Math.min(guest.remaining, 25);
    if (guest.remaining <= 0) guest.phase = "leaving";
  } else {
    const back = guest.path[guest.index - 1];
    if (guest.index > 0 && back && !life.reduceMotion && !occupied.has(tileKey(back))) {
      guest.next = guest.index - 1;
      guest.progress = 0;
      guest.facingRight = facing(guest.path[guest.index]!, back, guest.facingRight);
    } else {
      // arrivato all'ingresso (o non può camminare): sfuma e sparisce
      guest.fade -= dt / 0.6;
      moving = true;
      if (guest.fade <= 0) { visitor = null; return true; }
    }
  }
  return moving;
}

/** Un passo della vita (a ogni fotogramma): i compagni e l'ospite. Aggiorna quello che il disegno legge e dice se qualcosa si muove. */
export function advanceLife(data: GardenData, dt: number, hour: number, carried: string | null): boolean {
  const walking = advanceWalker(data, dt, carried);
  const guesting = advanceVisitor(data, dt, hour);
  life.walkers = new Map([...walkers].map(([pet, w]) => {
    const it = w.interacting && w.interacting.remaining !== null ? w.interacting : null;
    const scene = it === null ? null : { placement: it.candidate.placement.id, interaction: it.candidate.interaction, started: it.started };
    return [pet, { from: w.from, to: w.to, progress: w.progress, pose: w.activity?.affinity.pose ?? null, scene }];
  }));
  const guest = visitor;
  life.visitor = guest === null ? null : {
    id: guest.attraction.visitor.id, image: visitorImage(guest.attraction.visitor), height: guest.attraction.visitor.height, island: guest.island,
    from: guest.path[guest.index]!, to: guest.path[guest.next]!, progress: guest.progress, walking: guest.next !== guest.index && guest.progress < 1,
    facingRight: guest.facingRight, fade: guest.fade, hint: !guest.greeted && guest.phase === "staying",
  };
  return walking || guesting;
}

/** L'ospite che c'è adesso (per il saluto): chi è e cosa l'ha attirato. Lo segna salutato. */
export function greetVisitor(): { id: string; name: string; came: string; item: string; corner: string | null; first: boolean } | null {
  if (!visitor) return null;
  const v = visitor.attraction.visitor;
  const first = !visitor.greeted;
  visitor.greeted = true;
  return { id: v.id, name: v.name, came: v.feminine ? "venuta" : "venuto", item: visitor.attraction.item, corner: visitor.attraction.corner, first };
}

