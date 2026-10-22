// L'ora «sull'orologio». Le statistiche contano i giorni come li ha visti chi studiava, non secondo l'istante assoluto:
// una sessione non deve cambiare giorno se poi cambia il fuso orario o l'ora legale (vedi FORMATI.md §2.4).
//
// Per non avere a che fare con i fusi a ogni calcolo, un'ora «sull'orologio» si rappresenta come un numero di
// millisecondi (`Wall`) che legge il giorno e l'ora come se fossero UTC. Su un `Wall` i giorni durano sempre 24 ore e le
// settimane 7 giorni, quindi si può fare aritmetica semplice. Solo il passaggio istante → orologio dipende dal fuso.

export type Wall = number;

export const DAY_MS = 86_400_000;
export const HOUR_MS = 3_600_000;

const formatters = new Map<string, Intl.DateTimeFormat>();

function build(zone: string | undefined): Intl.DateTimeFormat {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: zone, hourCycle: "h23", year: "numeric", month: "numeric", day: "numeric",
    hour: "numeric", minute: "numeric", second: "numeric",
  });
}

function formatter(zone: string | undefined): Intl.DateTimeFormat {
  const key = zone ?? "";
  let found = formatters.get(key);
  if (!found) {
    found = build(zone);
    formatters.set(key, found);
  }
  return found;
}

// Il fuso del computer può cambiare mentre l'app è aperta (un viaggio, l'ora legale che cambia, un cambio a mano): un
// `Intl.DateTimeFormat` senza fuso lo legge una volta sola, quando nasce. Per questo il fuso del computer si rilegge ogni
// pochi secondi e il formattatore si tiene per nome (e si rilegge subito dopo uno sleep: vedi `refreshSystemZone`).
const SYSTEM_ZONE_TTL_MS = 5000;
let systemZoneName = "";
let systemZoneCheckedAt = 0;

/** Il nome del fuso del computer adesso (riletto al massimo ogni 5 secondi). */
export function systemZone(now: number = Date.now()): string {
  if (systemZoneName === "" || now - systemZoneCheckedAt >= SYSTEM_ZONE_TTL_MS || now < systemZoneCheckedAt) {
    systemZoneName = new Intl.DateTimeFormat().resolvedOptions().timeZone;
    systemZoneCheckedAt = now;
  }
  return systemZoneName;
}

/** Dopo uno sleep o un cambio d'ora: la prossima volta il fuso del computer si rilegge. */
export function refreshSystemZone(): void {
  systemZoneName = "";
}

function systemFormatter(): Intl.DateTimeFormat {
  const name = systemZone();
  try {
    return formatter(name);
  } catch {
    return build(undefined);           // un nome che il motore non conosce: meglio il fuso che sceglie lui (senza tenerlo da parte)
  }
}

/** L'istante (millisecondi dal 1970, UTC) letto sull'orologio del fuso dato (nessun fuso = quello del computer). */
export function wallOf(instantMs: number, zone?: string): Wall {
  const parts = (zone === undefined ? systemFormatter() : formatter(zone)).formatToParts(new Date(instantMs));
  const get = (type: string): number => Number(parts.find((p) => p.type === type)?.value);
  const fraction = ((instantMs % 1000) + 1000) % 1000;
  return Date.UTC(get("year"), get("month") - 1, get("day"), get("hour"), get("minute"), get("second")) + fraction;
}

export interface WallParts {
  year: number;
  month: number;       // 1...12
  day: number;
  hour: number;
  minute: number;
  second: number;
  /** Come in Calendar: 1 = domenica ... 7 = sabato. */
  weekday: number;
}

export function partsOf(wall: Wall): WallParts {
  const d = new Date(wall);
  return {
    year: d.getUTCFullYear(), month: d.getUTCMonth() + 1, day: d.getUTCDate(),
    hour: d.getUTCHours(), minute: d.getUTCMinutes(), second: d.getUTCSeconds(), weekday: d.getUTCDay() + 1,
  };
}

const pad = (n: number, width = 2): string => String(n).padStart(width, "0");

/** «2026-10-14T09:30» (16 caratteri), l'ora «sull'orologio» che sta in `localStart`. */
export function localString(wall: Wall): string {
  const p = partsOf(wall);
  return `${pad(p.year, 4)}-${pad(p.month)}-${pad(p.day)}T${pad(p.hour)}:${pad(p.minute)}`;
}

/** Legge un `localStart`: formato fisso `AAAA-MM-GGThh:mm`; null se non lo è. */
export function parseLocal(text: string): Wall | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(text);
  if (!m) return null;
  const [year, month, day, hour, minute] = m.slice(1).map(Number) as [number, number, number, number, number];
  const wall = Date.UTC(year, month - 1, day, hour, minute);
  const p = partsOf(wall);
  // Un giorno o un'ora che non esistono («2026-13-45T25:61») non sono un'ora sull'orologio.
  return p.year === year && p.month === month && p.day === day && p.hour === hour && p.minute === minute ? wall : null;
}

/** «2026-10-14» di un giorno sull'orologio. */
export function dayString(wall: Wall): string {
  const p = partsOf(wall);
  return `${pad(p.year, 4)}-${pad(p.month)}-${pad(p.day)}`;
}

export function startOfDay(wall: Wall): Wall {
  return Math.floor(wall / DAY_MS) * DAY_MS;
}

/** Il lunedì (alle 00:00) della settimana che contiene `wall`: la settimana parte dal lunedì. */
export function startOfWeek(wall: Wall): Wall {
  const sinceMonday = (partsOf(wall).weekday + 5) % 7;       // lunedì = 0 ... domenica = 6
  return startOfDay(wall) - sinceMonday * DAY_MS;
}

export function startOfMonth(wall: Wall): Wall {
  const p = partsOf(wall);
  return Date.UTC(p.year, p.month - 1, 1);
}

/** Il 1 gennaio (alle 00:00) dell'anno che contiene `wall`. */
export function startOfYear(wall: Wall): Wall {
  return Date.UTC(partsOf(wall).year, 0, 1);
}

export function addMonths(wall: Wall, count: number): Wall {
  const p = partsOf(wall);
  return Date.UTC(p.year, p.month - 1 + count, Math.min(p.day, daysInMonth(p.year, p.month + count)), p.hour, p.minute, p.second);
}

export function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();       // `month` è 1...12 (anche fuori misura: si riporta)
}

// ---- le date dei file: ISO 8601 UTC con secondi interi e «Z»

/** «2026-10-14T07:00:00Z»: senza frazioni di secondo (toISOString ne aggiunge). */
export function isoUtc(instantMs: number): string {
  return new Date(instantMs).toISOString().replace(/\.\d{3}Z$/, "Z");
}

/** Legge una data dei file; null se non è nel formato (le frazioni di secondo non sono ammesse). */
export function parseIsoUtc(text: unknown): number | null {
  if (typeof text !== "string") return null;
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})$/.test(text)) return null;
  const ms = Date.parse(text);
  return Number.isNaN(ms) ? null : ms;
}
