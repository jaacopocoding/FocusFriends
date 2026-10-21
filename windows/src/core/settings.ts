// Le preferenze (FORMATI.md §6): un oggetto JSON piatto in `impostazioni.json`, con gli stessi nomi di chiave di
// UserDefaults sul Mac. Un valore mancante, di un tipo sbagliato o fuori elenco vale il predefinito: non è mai un errore.

import { join } from "node:path";
import { readJson, stringifyJson, writeFileAtomic } from "./files.ts";
import { DEFAULT_PET, PET_IDS } from "./pets.ts";
import {
  ALLOWED_TIMERS, AMBIENT_DEFAULT_VOLUME, AMBIENT_SOUNDS, BUILT_IN_TIMERS, CHATTINESS, MAX_CUSTOM_PER_KIND, MUSIC_DEFAULT_VOLUME,
  MUSIC_SOURCES, clampVolume,
} from "./rules.ts";
import type { AddTimerResult, AmbientSound, Chattiness, MusicSource, TimerKind } from "./rules.ts";

// ---- le impostazioni

type Raw = Record<string, unknown>;

const oneOf = <T extends string>(list: readonly T[], value: unknown): T | undefined =>
  typeof value === "string" ? list.find((item) => item === value) : undefined;

export class Settings {
  private readonly file: string;
  private values: Raw = {};
  private observers: Array<() => void> = [];
  private pendingProblems: string[] = [];
  private problemHandler: ((message: string) => void) | undefined;
  private writeFailureReported = false;

  constructor(directory: string) {
    this.file = join(directory, "impostazioni.json");
    // Se non è un oggetto JSON (mancante, rovinato) si parte dai predefiniti, e il primo salvataggio lo sostituisce:
    // sono solo preferenze.
    const raw = readJson(this.file);
    if (typeof raw === "object" && raw !== null && !Array.isArray(raw)) this.values = { ...(raw as Raw) };
  }

  set onProblem(handler: ((message: string) => void) | undefined) {
    this.problemHandler = handler;
    if (handler && this.pendingProblems.length > 0) {
      const pending = this.pendingProblems;
      this.pendingProblems = [];
      pending.forEach(handler);
    }
  }

  addObserver(observer: () => void): void {
    this.observers.push(observer);
  }

  private set(key: string, value: unknown): void {
    if (value === undefined || value === null) delete this.values[key]; else this.values[key] = value;
    try {
      writeFileAtomic(this.file, stringifyJson(this.values) + "\n");
      this.writeFailureReported = false;
    } catch (error) {
      if (!this.writeFailureReported) {
        this.writeFailureReported = true;
        const message = `Non riesco a salvare le impostazioni: ${error instanceof Error ? error.message : String(error)}.`;
        if (this.problemHandler) this.problemHandler(message); else this.pendingProblems.push(message);
      }
    }
    this.observers.forEach((observer) => observer());
  }

  private bool(key: string, fallback: boolean): boolean {
    const value = this.values[key];
    return typeof value === "boolean" ? value : fallback;
  }

  private number(key: string): number | undefined {
    const value = this.values[key];
    return typeof value === "number" ? value : undefined;
  }

  // ---- il compagno e le frasi

  /** Il compagno scelto; un id sconosciuto vale Pianty. */
  get pet(): string {
    const value = this.values["pet"];
    return typeof value === "string" && PET_IDS.includes(value) ? value : DEFAULT_PET;
  }
  set pet(id: string) { this.set("pet", id); }

  get phraseFrequency(): Chattiness { return oneOf(CHATTINESS, this.values["phraseFrequency"]) ?? "sometimes"; }
  set phraseFrequency(value: Chattiness) { this.set("phraseFrequency", value); }

  /** Cammina per lo schermo. */
  get movement(): boolean { return this.bool("movement", true); }
  set movement(value: boolean) { this.set("movement", value); }

  /** Mostra «Com'è andata?» a fine focus. */
  get askHowItWent(): boolean { return this.bool("askHowItWent", true); }
  set askHowItWent(value: boolean) { this.set("askHowItWent", value); }

  /** Il lunedì (come «AAAA-MM-GG») della settimana di cui il compagno ha già detto il riepilogo; null se non l'ha mai detto. */
  get lastWeeklyRecap(): string | null {
    const value = this.values["lastWeeklyRecap"];
    return typeof value === "string" && value !== "" ? value : null;
  }
  set lastWeeklyRecap(value: string | null) { this.set("lastWeeklyRecap", value); }

  /** Pausa lunga dopo quattro focus. */
  get longBreakEnabled(): boolean { return this.bool("longBreakEnabled", true); }
  set longBreakEnabled(value: boolean) { this.set("longBreakEnabled", value); }

  /** Modalità sviluppatore: tutti i compagni (e gli oggetti del giardino) sbloccati, senza toccare il profilo. */
  get developerMode(): boolean { return this.bool("developerMode", false); }
  set developerMode(value: boolean) { this.set("developerMode", value); }

  // ---- i suoni

  get ambientSound(): AmbientSound { return oneOf(AMBIENT_SOUNDS, this.values["ambientSound"]) ?? "none"; }
  set ambientSound(value: AmbientSound) { this.set("ambientSound", value); }

  get ambientVolume(): number { return clampVolume(this.number("ambientVolume") ?? AMBIENT_DEFAULT_VOLUME); }
  set ambientVolume(value: number) { this.set("ambientVolume", clampVolume(value)); }

  get musicSource(): MusicSource { return oneOf(MUSIC_SOURCES, this.values["musicSource"]) ?? "off"; }
  set musicSource(value: MusicSource) { this.set("musicSource", value); }

  /** La cartella della musica dell'utente (dipende dal sistema: non si porta da un computer all'altro). */
  get musicFolder(): string | null {
    const value = this.values["musicFolder"];
    return typeof value === "string" && value !== "" ? value : null;
  }
  set musicFolder(value: string | null) { this.set("musicFolder", value); }

  get musicVolume(): number { return clampVolume(this.number("musicVolume") ?? MUSIC_DEFAULT_VOLUME); }
  set musicVolume(value: number) { this.set("musicVolume", clampVolume(value)); }

  // ---- i timer personalizzati

  /** Solo quelli aggiunti dall'utente, in ordine crescente. Valori fuori misura o ripetuti vengono ignorati. */
  customTimers(kind: TimerKind): number[] {
    const stored = this.values[`customTimers.${kind}`];
    if (!Array.isArray(stored) || !stored.every((value) => typeof value === "number" && Number.isInteger(value))) return [];
    const { min, max } = ALLOWED_TIMERS[kind];
    const builtIn = new Set(BUILT_IN_TIMERS[kind]);
    return [...new Set(stored as number[])].filter((m) => m >= min && m <= max && !builtIn.has(m)).sort((a, b) => a - b);
  }

  /** Quelli di serie e quelli personalizzati, in ordine crescente. */
  allTimers(kind: TimerKind): number[] {
    return [...new Set([...BUILT_IN_TIMERS[kind], ...this.customTimers(kind)])].sort((a, b) => a - b);
  }

  isCustomTimer(minutes: number, kind: TimerKind): boolean {
    return this.customTimers(kind).includes(minutes);
  }

  addCustomTimer(minutes: number, kind: TimerKind): AddTimerResult {
    const { min, max } = ALLOWED_TIMERS[kind];
    if (!Number.isInteger(minutes) || minutes < min || minutes > max) return { result: "outOfRange", min, max };
    if (this.allTimers(kind).includes(minutes)) return { result: "alreadyExists" };
    const current = this.customTimers(kind);
    if (current.length >= MAX_CUSTOM_PER_KIND) return { result: "tooMany", max: MAX_CUSTOM_PER_KIND };
    this.set(`customTimers.${kind}`, [...current, minutes].sort((a, b) => a - b));
    return { result: "added" };
  }

  removeCustomTimer(minutes: number, kind: TimerKind): void {
    this.set(`customTimers.${kind}`, this.customTimers(kind).filter((m) => m !== minutes));
  }
}
