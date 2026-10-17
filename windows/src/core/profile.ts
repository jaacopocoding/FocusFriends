// Il profilo di chi usa l'app (FORMATI.md §4): il nome, la presentazione vista, i compagni sbloccati.
// Sta in `profilo.json` accanto ai dati. Il nome NON è scritto nelle sessioni: i titoli si compongono al momento di mostrarli.

import { existsSync, renameSync, rmSync } from "node:fs";
import { join } from "node:path";
import { readText, stringifyJson, writeFileAtomic } from "./files.ts";
import { cleanName } from "./text.ts";

export const PROFILE_FORMAT_VERSION = 1;

export interface ProfileOptions {
  /** L'istante di «adesso» in millisecondi (per dare un nome ai file messi da parte). */
  now?: () => number;
  /** Modalità sviluppatore (`developerMode` nelle impostazioni): tutti i compagni risultano sbloccati, senza scrivere niente. */
  developer?: () => boolean;
}

interface Contents {
  name?: string;
  introSeen: boolean;
  unlocked?: string[];
  firstCompanion?: string;
}

/** Il contenuto di un profilo valido, o null se è rovinato: `version` e `introSeen` ci devono essere, gli altri campi
 *  se ci sono devono avere il tipo giusto (null = assente). */
function decode(raw: unknown): Contents | null {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) return null;
  const source = raw as Record<string, unknown>;
  if (typeof source["version"] !== "number" || !Number.isInteger(source["version"])) return null;
  if (typeof source["introSeen"] !== "boolean") return null;
  const contents: Contents = { introSeen: source["introSeen"] };
  const name = source["name"];
  if (name !== undefined && name !== null) {
    if (typeof name !== "string") return null;
    contents.name = name;
  }
  const unlocked = source["unlocked"];
  if (unlocked !== undefined && unlocked !== null) {
    if (!Array.isArray(unlocked) || !unlocked.every((id) => typeof id === "string")) return null;
    contents.unlocked = unlocked as string[];
  }
  const first = source["firstCompanion"];
  if (first !== undefined && first !== null) {
    if (typeof first !== "string") return null;
    contents.firstCompanion = first;
  }
  return contents;
}

export class Profile {
  readonly directory: string;
  private readonly file: string;
  private readonly now: () => number;
  private readonly developer: () => boolean;
  private _name: string | null = null;
  private _introSeen = false;
  private _unlocked: Set<string> | null = null;
  private _firstCompanion: string | null = null;
  private observers: Array<() => void> = [];
  /** Il file c'è ma non si legge (o è rovinato e non si riesce a metterlo da parte): non lo sovrascrivo. */
  private isReadOnly = false;
  private pendingProblems: string[] = [];
  private problemHandler: ((message: string) => void) | undefined;
  private writeFailureReported = false;

  constructor(directory: string, options: ProfileOptions = {}) {
    this.directory = directory;
    this.now = options.now ?? (() => Date.now());
    this.developer = options.developer ?? (() => false);
    this.file = join(directory, "profilo.json");
    this.load();
  }

  get name(): string | null { return this._name; }
  /** La scheda di introduzione è già stata mostrata (e chiusa). */
  get introSeen(): boolean { return this._introSeen; }
  /** I compagni sbloccati; null = niente è bloccato (chi usava già l'app, o chi non ha ancora scelto). */
  get unlocked(): ReadonlySet<string> | null { return this._unlocked; }
  get firstCompanion(): string | null { return this._firstCompanion; }

  /** Chiamata quando qualcosa non va con il file: il testo è per chi usa l'app. I problemi nati nel costruttore arrivano appena ci si registra. */
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

  private report(message: string): void {
    if (this.problemHandler) this.problemHandler(message);
    else this.pendingProblems.push(message);
  }

  private load(): void {
    if (!existsSync(this.file)) return;
    const text = readText(this.file);
    if (text === null) {
      this.isReadOnly = true;
      this.report("Il file del profilo non si legge: non lo modifico.");
      return;
    }
    let contents: Contents | null = null;
    try {
      contents = decode(JSON.parse(text.replace(/^\uFEFF/, "")));
    } catch {
      contents = null;
    }
    if (contents !== null) {
      this._name = cleanName(contents.name);
      this._introSeen = contents.introSeen;
      this._unlocked = contents.unlocked ? new Set(contents.unlocked) : null;
      this._firstCompanion = contents.firstCompanion ?? null;
      return;
    }
    // Rovinato: lo metto da parte invece di sovrascriverlo alla prossima modifica.
    const asideName = `profilo.corrotto-${Math.floor(this.now() / 1000)}.json`;
    try {
      renameSync(this.file, join(this.directory, asideName));
      this.report(`Il file del profilo era rovinato: l'ho messo da parte come ${asideName}.`);
    } catch {
      this.isReadOnly = true;
      this.report("Il file del profilo è rovinato e non riesco a metterlo da parte: non lo modifico.");
    }
  }

  // ---- il nome

  setName(text: string | null): void {
    this._name = cleanName(text);
    this.save();
  }

  markIntroSeen(): void {
    this._introSeen = true;
    this.save();
  }

  // ---- i compagni sbloccati

  /** Il compagno è usabile? Se non è mai stato deciso niente, sì (non si toglie nulla a chi usava già l'app). */
  isCompanionUnlocked(id: string): boolean {
    return this.developer() || (this._unlocked?.has(id) ?? true);
  }

  /** Chi usava già l'app (la presentazione è già stata vista) li tiene tutti: non gli tolgo niente. */
  keepAllCompanions(ids: readonly string[]): void {
    if (this._unlocked !== null || !this._introSeen) return;
    this._unlocked = new Set(ids);
    this.save();
  }

  /** Il primo compagno, scelto nella presentazione: è l'unico libero, gli altri si guadagnano. */
  chooseFirstCompanion(id: string): void {
    if (this._unlocked !== null) return;
    this._firstCompanion = id;
    this._unlocked = new Set([id]);
    this.save();
  }

  /** Segna come sbloccati questi compagni (non si richiudono più, anche se poi si cancellano sessioni). */
  unlock(ids: readonly string[]): void {
    if (this._unlocked === null || ids.length === 0) return;
    const before = this._unlocked.size;
    const next = new Set(this._unlocked);
    ids.forEach((id) => next.add(id));
    if (next.size === before) return;
    this._unlocked = next;
    this.save();
  }

  /** Dimentica nome e introduzione (per «Cancella tutto…»): alla prossima apertura si ricomincia. */
  reset(): void {
    this._name = null;
    this._introSeen = false;
    this._unlocked = null;
    this._firstCompanion = null;
    try { rmSync(this.file, { force: true }); } catch { /* il file non c'era o non si toglie */ }
    this.isReadOnly = false;      // «Cancella tutto» è una scelta esplicita: da qui si riparte
    this.observers.forEach((observer) => observer());
  }

  private save(): void {
    if (!this.isReadOnly) {
      const contents: Record<string, unknown> = {
        version: PROFILE_FORMAT_VERSION, introSeen: this._introSeen,
        name: this._name ?? undefined,
        unlocked: this._unlocked ? [...this._unlocked].sort() : undefined,
        firstCompanion: this._firstCompanion ?? undefined,
      };
      try {
        writeFileAtomic(this.file, stringifyJson(contents) + "\n");
        this.writeFailureReported = false;
      } catch (error) {
        if (!this.writeFailureReported) {
          this.writeFailureReported = true;
          this.report(`Non riesco a salvare il profilo (nome e compagni sbloccati): ${error instanceof Error ? error.message : String(error)}.`);
        }
      }
    }
    this.observers.forEach((observer) => observer());
  }

  // ---- i titoli

  /** «Il giardino di Marco», oppure «Il mio giardino» se non c'è il nome. */
  get gardenTitle(): string {
    return this._name === null ? "Il mio giardino" : `Il giardino di ${this._name}`;
  }

  /** «Le statistiche di Marco», oppure «Statistiche e riepilogo». */
  get statsTitle(): string {
    return this._name === null ? "Statistiche e riepilogo" : `Le statistiche di ${this._name}`;
  }
}
