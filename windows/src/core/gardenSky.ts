// Il cielo del giardino: la luce di ogni ora in ogni stagione, quando si accendono i lampioni e le lucciole, e il moto di quello che cade, vola,
// ondeggia o fuma. Sono numeri e funzioni del tempo, come GardenSky.swift, così si confrontano con il Mac. Niente `node:*`.

import { mixedHash } from "./gardenDrops.ts";
import { partsOf } from "./time.ts";
import type { Wall } from "./time.ts";

export type Season = "spring" | "summer" | "autumn" | "winter";
export const SEASONS: readonly Season[] = ["spring", "summer", "autumn", "winter"];
export const SEASON_TITLES: Readonly<Record<Season, string>> = { spring: "Primavera", summer: "Estate", autumn: "Autunno", winter: "Inverno" };

/** La stagione di un momento sull'orologio: marzo–maggio primavera, giugno–agosto estate, settembre–novembre autunno. */
export function seasonOf(wall: Wall): Season {
  const month = partsOf(wall).month;
  if (month >= 3 && month <= 5) return "spring";
  if (month >= 6 && month <= 8) return "summer";
  if (month >= 9 && month <= 11) return "autumn";
  return "winter";
}

export const isSeason = (value: unknown): value is Season => typeof value === "string" && (SEASONS as readonly string[]).includes(value);

export interface GardenRGB { red: number; green: number; blue: number }

/** La luce di un momento: un colore che tinge la scena (da moltiplicare) e quanto è buio (0 = giorno, fino a 0,55 = notte). */
export interface GardenLight { darkness: number; tint: GardenRGB; tintStrength: number }

export function smoothstep(x: number, low: number, high: number): number {
  const t = Math.min(Math.max((x - low) / (high - low), 0), 1);
  return t * t * (3 - 2 * t);
}

/** Quanto brillano i lampioni (0 di giorno, 1 di notte). */
export const lampAmount = (light: GardenLight): number => smoothstep(light.darkness, 0.16, 0.40);

/** Il colore con cui si moltiplica la scena. */
export function lightMultiplier(light: GardenLight): GardenRGB {
  const s = light.tintStrength;
  return { red: 255 + (light.tint.red - 255) * s, green: 255 + (light.tint.green - 255) * s, blue: 255 + (light.tint.blue - 255) * s };
}

const SUNRISE: Readonly<Record<Season, number>> = { spring: 6.5, summer: 5.5, autumn: 7.0, winter: 7.5 };
const SUNSET: Readonly<Record<Season, number>> = { spring: 19.5, summer: 21.0, autumn: 18.0, winter: 17.0 };
export const sunrise = (season: Season): number => SUNRISE[season];
export const sunset = (season: Season): number => SUNSET[season];

const rgb = (red: number, green: number, blue: number): GardenRGB => ({ red, green, blue });
const NIGHT = rgb(62, 72, 150), NONE = rgb(255, 255, 255);

function keyframes(season: Season): Array<{ hour: number; darkness: number; tint: GardenRGB; strength: number }> {
  const rise = sunrise(season), set = sunset(season);
  const k = (hour: number, darkness: number, tint: GardenRGB, strength: number) => ({ hour, darkness, tint, strength });
  return [
    k(0, 0.55, NIGHT, 0.55),
    k(rise - 1.5, 0.55, NIGHT, 0.55),
    k(rise - 0.5, 0.30, rgb(150, 120, 190), 0.40),
    k(rise + 0.3, 0.12, rgb(255, 190, 150), 0.28),
    k(rise + 1.8, 0, NONE, 0),
    k(set - 2, 0, NONE, 0),
    k(set - 0.6, 0.06, rgb(255, 176, 100), 0.25),
    k(set + 0.2, 0.22, rgb(190, 112, 150), 0.38),
    k(set + 1.2, 0.45, rgb(92, 82, 162), 0.50),
    k(set + 2, 0.55, NIGHT, 0.55),
    k(24, 0.55, NIGHT, 0.55),
  ];
}

/** La luce a un'ora del giorno (0…24, con la virgola) in una stagione. */
export function lightAt(hour: number, season: Season): GardenLight {
  const h = ((hour % 24) + 24) % 24;
  const frames = keyframes(season);
  for (let i = 0; i + 1 < frames.length; i++) {
    const a = frames[i]!, b = frames[i + 1]!;
    if (!(h >= a.hour && h <= b.hour)) continue;
    const t = b.hour > a.hour ? (h - a.hour) / (b.hour - a.hour) : 0;
    const mix = (x: number, y: number): number => x + (y - x) * t;
    return {
      darkness: mix(a.darkness, b.darkness),
      tint: rgb(mix(a.tint.red, b.tint.red), mix(a.tint.green, b.tint.green), mix(a.tint.blue, b.tint.blue)),
      tintStrength: mix(a.strength, b.strength),
    };
  }
  return { darkness: 0, tint: NONE, tintStrength: 0 };
}

/** L'ora di un momento sull'orologio, con la virgola. */
export function hourOf(wall: Wall): number {
  const p = partsOf(wall);
  return p.hour + p.minute / 60 + p.second / 3600;
}

/** La stagione che si vede nel giardino e dietro l'album: quella del calendario, o quella forzata per provarle. */
export function shownSeason(wall: Wall, forced: Season | null = null): Season {
  return forced ?? seasonOf(wall);
}

// ---- quello che cade e quello che vola

export type GardenParticleKind = "petal" | "leaf" | "snow";
export interface GardenParticle { x: number; y: number; size: number; angle: number; alpha: number; tone: number }

export function particleKind(season: Season): GardenParticleKind | null {
  switch (season) {
    case "spring": return "petal";
    case "summer": return null;
    case "autumn": return "leaf";
    case "winter": return "snow";
  }
}

export function particleCount(kind: GardenParticleKind): number {
  return kind === "petal" ? 26 : kind === "leaf" ? 22 : 70;
}

const unit = (index: number, salt: number): number => mixedHash(`cielo-${salt}-${index}`) / 4_294_967_296;

/** Come `truncatingRemainder` di Swift, ma sempre fra 0 e `period`. */
function wrapped(value: number, period: number): number {
  const r = value % period;
  return r < 0 ? r + period : r;
}

/** Una particella al tempo `time` (in secondi): scende ondeggiando e, uscita dal fondo, rientra dall'alto. */
export function particle(kind: GardenParticleKind, index: number, time: number, width: number, height: number): GardenParticle {
  let fall: number, drift: number, size: number;
  switch (kind) {
    case "petal": fall = 22 + unit(index, 1) * 18; drift = 8 + unit(index, 2) * 10; size = 3.2 + unit(index, 6) * 3; break;
    case "leaf": fall = 30 + unit(index, 1) * 22; drift = 10 + unit(index, 2) * 12; size = 5 + unit(index, 6) * 4; break;
    case "snow": fall = 20 + unit(index, 1) * 30; drift = (unit(index, 2) - 0.5) * 8; size = 1.4 + unit(index, 6) * 2.4; break;
  }
  const sway = 10 + unit(index, 3) * 20, swayRate = 0.5 + unit(index, 4) * 0.9, phase = unit(index, 5) * 2 * Math.PI;
  const y = wrapped(unit(index, 7) * (height + 40) + fall * time, height + 40) - 20;
  const x = wrapped(unit(index, 8) * (width + 60) + drift * time + Math.sin(time * swayRate + phase) * sway, width + 60) - 30;
  return { x, y, size, angle: phase + time * (0.8 + unit(index, 9) * 1.6), alpha: 0.6 + unit(index, 10) * 0.4, tone: unit(index, 11) };
}

// ---- le lucciole

export function fireflyAmount(season: Season, light: GardenLight): number {
  const factor = season === "summer" ? 1 : season === "spring" ? 0.7 : season === "autumn" ? 0.35 : 0;
  return smoothstep(light.darkness, 0.25, 0.5) * factor;
}

export const FIREFLY_COUNT = 24;

export function firefly(index: number, time: number, width: number, height: number): { x: number; y: number; glow: number } {
  const ax = width * (0.12 + unit(index, 21) * 0.76), ay = height * (0.22 + unit(index, 22) * 0.62);
  const x = ax + Math.sin(time * (0.25 + unit(index, 23) * 0.4) + unit(index, 24) * 6.28) * (18 + unit(index, 25) * 26);
  const y = ay + Math.sin(time * (0.3 + unit(index, 26) * 0.4) + unit(index, 27) * 6.28) * (10 + unit(index, 28) * 16);
  const pulse = (Math.sin(time * (0.7 + unit(index, 29) * 0.9) + unit(index, 30) * 6.28) + 1) / 2;
  return { x, y, glow: Math.pow(pulse, 2.2) };
}

// ---- il vento, l'acqua e il fumo

export function wind(season: Season): number {
  return season === "spring" ? 0.8 : season === "summer" ? 0.45 : season === "autumn" ? 1.0 : 0.9;
}

/** Di quanto si sposta di lato la cima di una pianta (da −1 a 1). `height` da 0 (la base) a 1 (la cima), `seed` da 0 a 1. */
export function sway(time: number, col: number, row: number, seed: number, height: number): number {
  const gust = 0.65 + 0.35 * Math.sin(time * 0.11 + 1.3);
  const wave = Math.sin(time * 0.95 - (col + row) * 0.45 + seed * 6.283) * 0.75 + Math.sin(time * 2.1 + seed * 12.5) * 0.25;
  return wave * gust * Math.pow(Math.min(Math.max(height, 0), 1), 1.6);
}

export const SPARKLE_COUNT = 3;

export function sparkle(index: number, time: number): { x: number; y: number; glow: number } {
  const angle = unit(index, 41) * 2 * Math.PI, radius = Math.sqrt(unit(index, 42)) * 0.78;
  const flash = Math.max(0, Math.sin(time * (1.1 + unit(index, 43) * 1.3) + unit(index, 44) * 6.28));
  return { x: Math.cos(angle) * radius, y: Math.sin(angle) * radius, glow: Math.pow(flash, 6) };
}

/** Il cerchio che si allarga sull'acqua: ogni 3,4 secondi nasce in un punto e svanisce crescendo. */
export function ripple(time: number, seed: number): { x: number; y: number; phase: number; alpha: number } {
  const shifted = time / 3.4 + seed;
  const number = Math.floor(shifted);
  const phase = shifted - number;
  return { x: unit(number, 51) - 0.5, y: (unit(number, 52) - 0.5) * 0.7, phase, alpha: (1 - phase) * Math.min(phase * 8, 1) * 0.55 };
}

export function smokeAmount(season: Season): number {
  return season === "spring" ? 0.5 : season === "summer" ? 0.15 : season === "autumn" ? 0.85 : 1;
}

export const SMOKE_COUNT = 9;

/** Uno sbuffo di fumo, dalla bocca del camino (l'alto è negativo). */
export function smoke(index: number, time: number, windAmount: number): { dx: number; dy: number; radius: number; alpha: number } {
  const life = 7;
  const shifted = (time + index * life / SMOKE_COUNT) / life;
  const t = shifted - Math.floor(shifted);
  const dx = Math.sin(t * 2.6 + index * 1.7) * 7 + t * t * 34 * windAmount;
  return { dx, dy: -t * 92, radius: 3 + 15 * Math.pow(t, 0.8), alpha: Math.min(1, t * 7) * Math.pow(1 - t, 1.3) * 0.6 };
}

// ---- gli angoli

/** Qualcosa che cade o sale vicino a un oggetto di un angolo: `progress` da 0 a 1, `x` da −1 a 1, `spin` un angolo, `alpha`. */
export function drift(index: number, time: number, period: number): { progress: number; x: number; spin: number; alpha: number } {
  const cycle = time / period + unit(index, 61);
  const progress = cycle - Math.floor(cycle);
  const lap = Math.floor(cycle);
  // Swift fa `index &+ lap &* 7` con gli interi a 64 bit: per i tempi dell'app non trabocca
  const start = unit(index + lap * 7, 62) * 2 - 1;
  const x = start * 0.7 + Math.sin(time * (0.8 + unit(index, 63) * 0.8) + unit(index, 64) * 6.28) * 0.3;
  const alpha = Math.max(Math.min(progress * 5, (1 - progress) * 3, 1), 0);
  return { progress, x, spin: unit(index, 65) * 6.28 + time * (0.5 + unit(index, 66)), alpha };
}

export function butterfly(index: number, time: number): { x: number; y: number; flap: number } {
  const x = Math.sin(time * (0.25 + unit(index, 71) * 0.3) + unit(index, 73) * 6.28) * (0.65 + unit(index, 74) * 0.3);
  const y = Math.sin(time * (0.6 + unit(index, 72) * 0.5) + unit(index, 75) * 6.28) * 0.5;
  return { x, y, flap: (Math.sin(time * (11 + unit(index, 76) * 3)) + 1) / 2 };
}

export function cornerFirefly(index: number, time: number): { x: number; y: number; glow: number } {
  const x = Math.sin(time * (0.2 + unit(index, 81) * 0.3) + unit(index, 82) * 6.28) * (0.5 + unit(index, 83) * 0.45);
  const y = Math.sin(time * (0.25 + unit(index, 84) * 0.3) + unit(index, 85) * 6.28) * (0.4 + unit(index, 86) * 0.4);
  const pulse = (Math.sin(time * (0.7 + unit(index, 87) * 0.9) + unit(index, 88) * 6.28) + 1) / 2;
  return { x, y, glow: Math.pow(pulse, 2) };
}

export const BURST_STAR_COUNT = 18;

/** Una stellina dello sblocco di un angolo, a `progress` (da 0 a 1) della festa. */
export function burstStar(index: number, progress: number): { dx: number; dy: number; size: number; angle: number; alpha: number } {
  const delay = unit(index, 91) * 0.35;
  const t = Math.min(Math.max((progress - delay) / (1 - delay), 0), 1);
  const eased = 1 - Math.pow(1 - t, 2.4);
  const direction = (index + unit(index, 92) * 0.8) / BURST_STAR_COUNT * 2 * Math.PI;
  const reach = 50 + unit(index, 93) * 70;
  const size = 7 + unit(index, 94) * 10;
  const alpha = t <= 0 ? 0 : Math.min(t * 8, 1) * Math.min((1 - t) * 2.2, 1);
  return { dx: Math.cos(direction) * reach * eased, dy: Math.sin(direction) * reach * eased * 0.8 - 14 * eased, size, angle: direction + t * 2.4, alpha };
}
