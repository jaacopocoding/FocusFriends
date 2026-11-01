// Le figurine di fine focus: come GardenDrops.swift. Il tiro è deterministico (dipende solo dall'identificativo del focus e da ciò che si è già
// trovato), quindi Mac e Windows danno lo stesso regalo sugli stessi dati: le prove di contratto lo confrontano. Niente `node:*`.

import { GARDEN_ITEMS, isStarter, itemNumber, itemWithId, rarityOf, rarityRank, RARITIES } from "./gardenCatalog.ts";
import type { GardenItem, GardenRarity } from "./gardenCatalog.ts";
import type { StudySession } from "./log.ts";
import { analyzeStreak, startTime } from "./stats.ts";
import { DAY_MS, startOfDay } from "./time.ts";

/** Quello che il giardino ricorda dei regali: cosa si è trovato, i secondi di studio messi da parte e i contatori delle garanzie. */
export interface GardenDropState {
  /** Gli oggetti trovati (il numero è rimasto dalle versioni con le copie: conta solo se c'è). */
  found: Record<string, number>;
  sinceRare: number;
  sinceLegendary: number;
  studyBank: number;
}

export interface GardenDrop { item: string; rarity: GardenRarity }

/** Cosa è successo alla fine di un focus. */
export type GardenGift =
  | { kind: "notEligible" }
  | { kind: "progress" }
  | { kind: "complete" }
  | { kind: "found"; drop: GardenDrop };

// ---- i numeri

export const DROP_MINIMUM_SECONDS = 20 * 60;
export const FIRST_GIFT_MINUTES = 60;
export const GIFT_MINUTES_STEP = 8;
export const BASE_RARE = 0.22;
export const BASE_LEGENDARY = 0.03;
export const STREAK_BONUS: ReadonlyArray<{ days: number; rare: number; legendary: number }> = [
  { days: 3, rare: 0.04, legendary: 0 }, { days: 7, rare: 0.08, legendary: 0.005 }, { days: 14, rare: 0.12, legendary: 0.010 },
];
export const LONG_FOCUS_SECONDS = 45 * 60;
export const LONG_FOCUS_RARE_BONUS = 0.04;
export const RARE_PITY = 10;
export const LEGENDARY_PITY = 40;

/** Chi comincia ha già gli oggetti che non costano niente (la «dotazione»). */
export function startingDropState(pool: readonly GardenItem[] = GARDEN_ITEMS): GardenDropState {
  const found: Record<string, number> = {};
  for (const x of pool) if (isStarter(x)) found[x.id] = 1;
  return { found, sinceRare: 0, sinceLegendary: 0, studyBank: 0 };
}

export function cloneDropState(state: GardenDropState): GardenDropState {
  return { ...state, found: { ...state.found } };
}

const STARTERS = GARDEN_ITEMS.filter(isStarter).length;
const foundCount = (state: GardenDropState): number => Object.keys(state.found).length;

export function isEligible(session: StudySession, minimumSeconds: number = DROP_MINIMUM_SECONDS): boolean {
  return session.completed && session.seconds >= minimumSeconds;
}

/** Quanti secondi di studio costa il prossimo regalo, avendo già trovato `found` cose in tutto (la dotazione non conta). */
export function giftCostSeconds(found: number, starters: number = STARTERS): number {
  return (FIRST_GIFT_MINUTES + GIFT_MINUTES_STEP * Math.max(found - starters, 0)) * 60;
}

export function hasSomethingToFind(state: GardenDropState, pool: readonly GardenItem[]): boolean {
  return pool.some((x) => state.found[x.id] === undefined);
}

/** Quanti minuti di studio mancano al prossimo regalo (0 = è già maturato); null se non c'è più niente da trovare. */
export function minutesToNextGift(state: GardenDropState, pool: readonly GardenItem[]): number | null {
  if (!hasSomethingToFind(state, pool)) return null;
  const missing = giftCostSeconds(foundCount(state)) - state.studyBank;
  return missing <= 0 ? 0 : Math.trunc((missing + 59) / 60);
}

/** Quanta strada si è fatta verso il prossimo regalo, da 0 a 1; null se non c'è più niente da trovare. */
export function giftProgress(state: GardenDropState, pool: readonly GardenItem[]): number | null {
  if (!hasSomethingToFind(state, pool)) return null;
  return Math.min(Math.max(state.studyBank / giftCostSeconds(foundCount(state)), 0), 1);
}

/** Le probabilità di raro e di leggendario per un focus. */
export function chances(streakDays: number, seconds: number): { rare: number; legendary: number } {
  let rare = BASE_RARE, legendary = BASE_LEGENDARY;
  const step = [...STREAK_BONUS].reverse().find((x) => streakDays >= x.days);
  if (step) {
    rare += step.rare;
    legendary += step.legendary;
  }
  if (seconds >= LONG_FOCUS_SECONDS) rare += LONG_FOCUS_RARE_BONUS;
  return { rare: Math.min(rare, 0.5), legendary: Math.min(legendary, 0.1) };
}

// ---- il generatore di numeri (uguale in Swift)

const encoder = new TextEncoder();

/** FNV-1a a 32 bit sul testo (i byte UTF-8). */
export function hash(text: string): number {
  let h = 2_166_136_261;
  for (const byte of encoder.encode(text)) {
    h ^= byte;
    h = Math.imul(h, 16_777_619) >>> 0;
  }
  return h >>> 0;
}

/** L'hash con in più il rimescolamento finale di MurmurHash3: testi vicini danno numeri lontani. */
export function mixedHash(text: string): number {
  let x = hash(text);
  x = (x ^ (x >>> 16)) >>> 0;
  x = Math.imul(x, 0x85EB_CA6B) >>> 0;
  x = (x ^ (x >>> 13)) >>> 0;
  x = Math.imul(x, 0xC2B2_AE35) >>> 0;
  x = (x ^ (x >>> 16)) >>> 0;
  return x;
}

/** Un numero da 0 a 1 dall'hash rimescolato di un testo. */
export function unitOf(text: string): number { return mixedHash(text) / 4_294_967_296; }

/** Mulberry32: numeri da 0 (incluso) a 1 (escluso), sempre gli stessi per lo stesso seme. */
export class DropStream {
  private state: number;
  constructor(seed: number) { this.state = seed >>> 0; }

  next(): number {
    this.state = (this.state + 0x6D2B_79F5) >>> 0;
    let t = this.state;
    t = Math.imul(t ^ (t >>> 15), t | 1) >>> 0;
    t = (t ^ ((t + Math.imul(t ^ (t >>> 7), t | 61)) >>> 0)) >>> 0;
    return ((t ^ (t >>> 14)) >>> 0) / 4_294_967_296;
  }
}

// ---- il tiro

/** Un focus che conta: i suoi secondi vanno nella riserva e, se bastano per il prossimo regalo e c'è ancora qualcosa da trovare, il regalo si tira e
 *  ne costa il prezzo. `state` cambia. `scale` moltiplica i secondi (per provare). */
export function credit(sessionId: string, streakDays: number, seconds: number, state: GardenDropState,
  pool: readonly GardenItem[] = GARDEN_ITEMS, scale = 1): GardenDrop | null {
  state.studyBank += Math.max(seconds, 0) * Math.max(scale, 1);
  if (!hasSomethingToFind(state, pool)) return null;
  const cost = giftCostSeconds(foundCount(state));
  if (state.studyBank < cost) return null;
  const drop = roll(sessionId, streakDays, seconds, state, pool);
  if (drop === null) return null;
  state.studyBank -= cost;
  return drop;
}

/** Il regalo (sempre qualcosa che non hai ancora), o null se non c'è più niente da trovare. `state` cambia. */
export function roll(sessionId: string, streakDays: number, seconds: number, state: GardenDropState,
  pool: readonly GardenItem[] = GARDEN_ITEMS): GardenDrop | null {
  const stream = new DropStream(hash(sessionId.toUpperCase()));
  const rarityDraw = stream.next(), pickDraw = stream.next();

  const fresh = pool.filter((x) => state.found[x.id] === undefined);
  if (fresh.length === 0) return null;

  const { rare, legendary } = chances(streakDays, seconds);
  let rarity: GardenRarity;
  if (state.sinceLegendary + 1 >= LEGENDARY_PITY) rarity = "legendary";
  else if (rarityDraw < legendary) rarity = "legendary";
  else if (state.sinceRare + 1 >= RARE_PITY || rarityDraw < legendary + rare) rarity = "rare";
  else rarity = "common";
  // se di quella rarità non c'è più niente da trovare si scende (dalla più vicina) e, in ultimo, si sale
  const rank = rarityRank(rarity);
  const order = [...RARITIES.filter((r) => rarityRank(r) <= rank).reverse(), ...RARITIES.filter((r) => rarityRank(r) > rank)];
  let candidates: GardenItem[] = [];
  for (const next of order) {
    if (candidates.length > 0) break;
    candidates = fresh.filter((x) => rarityOf(x) === next);
    rarity = next;
  }
  const chosen = candidates[Math.min(Math.trunc(pickDraw * candidates.length), candidates.length - 1)]!;
  state.found[chosen.id] = 1;
  state.sinceRare = rarityRank(rarity) >= rarityRank("rare") ? 0 : state.sinceRare + 1;
  state.sinceLegendary = rarity === "legendary" ? 0 : state.sinceLegendary + 1;
  return { item: chosen.id, rarity };
}

/** Tutti i regali che il registro avrebbe dato, in ordine di tempo, partendo da un album appena cominciato. Per le prove e il confronto con il Mac. */
export function simulate(sessions: readonly StudySession[], nowInstant: number, zone?: string,
  pool: readonly GardenItem[] = GARDEN_ITEMS): Array<{ session: StudySession; drop: GardenDrop | null }> {
  const streak = analyzeStreak(sessions, nowInstant, zone);
  const state = startingDropState(pool);
  const ordered = [...sessions].sort((a, b) => {
    const x = startTime(a, zone), y = startTime(b, zone);
    return x !== y ? x - y : (a.id.toUpperCase() < b.id.toUpperCase() ? -1 : a.id.toUpperCase() > b.id.toUpperCase() ? 1 : 0);
  });
  const result: Array<{ session: StudySession; drop: GardenDrop | null }> = [];
  for (const session of ordered) {
    if (!isEligible(session)) continue;
    const day = Math.floor(startOfDay(startTime(session, zone)) / DAY_MS);
    result.push({ session, drop: credit(session.id.toUpperCase(), streak.perDay.get(day) ?? 1, session.seconds, state, pool) });
  }
  return result;
}

// ---- le parole

const minutesWords = (minutes: number): string => (minutes === 1 ? "1 minuto" : `${minutes} minuti`);

/** Sotto la riga «Album» e nel giardino: quanto manca alla prossima figurina. Vuota se non c'è più niente da trovare. */
export function nextGiftLine(minutesLeft: number | null): string {
  if (minutesLeft === null) return "";
  return minutesLeft === 0 ? "Prossima figurina: al prossimo focus" : `Prossima figurina: ancora ${minutesWords(minutesLeft)} di studio`;
}

/** La frase di fine focus sul regalo (vuota se il focus non contava, o se c'è già tutto). */
export function giftLine(gift: GardenGift, minutesLeft: number | null = null): string {
  const next = minutesLeft === null ? "" : minutesLeft === 0 ? "Ne hai già un'altra pronta: arriva al prossimo focus." : `La prossima tra ${minutesWords(minutesLeft)} di studio.`;
  switch (gift.kind) {
    case "notEligible":
    case "complete":
      return "";
    case "progress":
      return minutesLeft !== null && minutesLeft > 0 ? `Ancora ${minutesWords(minutesLeft)} di studio e trovi una figurina.` : "";
    case "found": {
      const name = itemWithId(gift.drop.item)?.name ?? gift.drop.item;
      const number = itemNumber(gift.drop.item);
      const tag = number === undefined ? "" : ` (n. ${number})`;
      const sentence = gift.drop.rarity === "legendary" ? `Una figurina leggendaria: ${name}${tag}!`
        : gift.drop.rarity === "rare" ? `Nuova figurina rara: ${name}${tag}!` : `Nuova figurina: ${name}${tag}.`;
      return next === "" ? sentence : sentence + " " + next;
    }
  }
}
