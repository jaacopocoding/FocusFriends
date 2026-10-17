// Il registro delle sessioni di studio: lo stesso che fa SessionLog.swift sul Mac (FORMATI.md §2 e §3).
//
// Cartella dei dati:
//   sessioni.json   { "version": 3, "sessions": [...] }
//   in-corso.json   il focus in corso (sparisce quando finisce)
//   backup/         una copia al giorno (le ultime 7) e le copie intatte dei file di versioni precedenti

import { copyFileSync, existsSync, mkdirSync, readdirSync, renameSync, rmSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { join } from "node:path";
import { isoUtc, localString, parseIsoUtc, wallOf } from "./time.ts";
import type { Wall } from "./time.ts";
import { cleanFocusNotes, cleanNote, cleanSubject, subjectKey } from "./text.ts";
import { readJson, readText, stringifyJson, writeFileAtomic } from "./files.ts";

export type Rating = "good" | "soso" | "poor";
export const RATINGS: readonly Rating[] = ["good", "soso", "poor"];

/** Un focus: quando è iniziato, quanto è durato davvero e su quale materia. */
export interface StudySession {
  id: string;
  /** L'istante di inizio, in millisecondi dal 1970 (UTC). */
  start: number;
  /** L'ora «sull'orologio» («2026-10-14T09:30»): le statistiche usano questa. */
  localStart?: string;
  /** Secondi di focus davvero svolti. */
  seconds: number;
  plannedMinutes: number;
  completed: boolean;
  subject?: string;
  pet?: string;
  rating?: Rating;
  note?: string;
  notes?: string[];
}

export const FORMAT_VERSION = 3;
/** Un focus sotto il minuto non conta. */
export const MINIMUM_SECONDS = 60;
export const BACKUPS_TO_KEEP = 7;

// ---- lettura di una sessione (rigorosa, come il Codable di Swift)

const UUID_PATTERN = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

class Unreadable extends Error {}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Un campo facoltativo: assente o null = niente; di un altro tipo = la sessione non si legge. */
function optional<T>(source: Record<string, unknown>, key: string, check: (v: unknown) => v is T): T | undefined {
  const value = source[key];
  if (value === undefined || value === null) return undefined;
  if (!check(value)) throw new Unreadable(key);
  return value;
}

function required<T>(source: Record<string, unknown>, key: string, check: (v: unknown) => v is T): T {
  const value = source[key];
  if (value === undefined || value === null || !check(value)) throw new Unreadable(key);
  return value;
}

const isString = (v: unknown): v is string => typeof v === "string";
const isInteger = (v: unknown): v is number => typeof v === "number" && Number.isInteger(v);
const isBoolean = (v: unknown): v is boolean => typeof v === "boolean";
const isStringList = (v: unknown): v is string[] => Array.isArray(v) && v.every(isString);

/** La sessione letta da un oggetto JSON, o null se non si legge (manca un campo, ha il tipo sbagliato, data non valida). */
export function decodeSession(raw: unknown): StudySession | null {
  if (!isRecord(raw)) return null;
  try {
    const id = required(raw, "id", isString);
    if (!UUID_PATTERN.test(id)) return null;
    const start = parseIsoUtc(required(raw, "start", isString));
    if (start === null) return null;
    const session: StudySession = {
      id, start,
      seconds: required(raw, "seconds", isInteger),
      plannedMinutes: required(raw, "plannedMinutes", isInteger),
      completed: required(raw, "completed", isBoolean),
    };
    const localStart = optional(raw, "localStart", isString);
    if (localStart !== undefined) session.localStart = localStart;
    const subject = optional(raw, "subject", isString);
    if (subject !== undefined) session.subject = subject;
    const pet = optional(raw, "pet", isString);
    if (pet !== undefined) session.pet = pet;
    // Un voto che non conosco (scritto da una versione futura) non deve rendere illeggibile il file.
    const rating = raw["rating"];
    if (typeof rating === "string" && (RATINGS as readonly string[]).includes(rating)) session.rating = rating as Rating;
    const note = optional(raw, "note", isString);
    if (note !== undefined) session.note = note;
    const notes = optional(raw, "notes", isStringList);
    if (notes !== undefined) session.notes = notes;
    return session;
  } catch (error) {
    if (error instanceof Unreadable) return null;
    throw error;
  }
}

/** La sessione com'è nel file: i campi vuoti non ci sono, le date hanno i secondi interi. */
export function encodeSession(session: StudySession): Record<string, unknown> {
  return {
    id: session.id, start: isoUtc(session.start), localStart: session.localStart, seconds: session.seconds,
    plannedMinutes: session.plannedMinutes, completed: session.completed, subject: session.subject, pet: session.pet,
    rating: session.rating, note: session.note, notes: session.notes,
  };
}

// ---- il focus in corso

interface InProgress {
  start: number;
  plannedMinutes: number;
  subject?: string;
  pet?: string;
  lastSeen: number;
  notes?: string[];
  /** I secondi in cui il timer è stato fermo (le pause già finite). */
  pausedSeconds?: number;
  /** Da quando è fermo adesso (assente = sta andando). */
  pausedSince?: number;
}

function decodeInProgress(raw: unknown): InProgress | null {
  if (!isRecord(raw)) return null;
  try {
    const start = parseIsoUtc(required(raw, "start", isString));
    const lastSeen = parseIsoUtc(required(raw, "lastSeen", isString));
    if (start === null || lastSeen === null) return null;
    const progress: InProgress = { start, lastSeen, plannedMinutes: required(raw, "plannedMinutes", isInteger) };
    const subject = optional(raw, "subject", isString);
    if (subject !== undefined) progress.subject = subject;
    const pet = optional(raw, "pet", isString);
    if (pet !== undefined) progress.pet = pet;
    const notes = optional(raw, "notes", isStringList);
    if (notes !== undefined) progress.notes = notes;
    const pausedSeconds = optional(raw, "pausedSeconds", isInteger);
    if (pausedSeconds !== undefined) progress.pausedSeconds = pausedSeconds;
    const sinceText = optional(raw, "pausedSince", isString);
    if (sinceText !== undefined) {
      const since = parseIsoUtc(sinceText);
      if (since === null) return null;
      progress.pausedSince = since;
    }
    return progress;
  } catch (error) {
    if (error instanceof Unreadable) return null;
    throw error;
  }
}

function encodeInProgress(p: InProgress): Record<string, unknown> {
  return {
    start: isoUtc(p.start), plannedMinutes: p.plannedMinutes, subject: p.subject, pet: p.pet, lastSeen: isoUtc(p.lastSeen),
    notes: p.notes, pausedSeconds: p.pausedSeconds, pausedSince: p.pausedSince === undefined ? undefined : isoUtc(p.pausedSince),
  };
}

// ---- il registro

export interface LogOptions {
  /** L'«adesso», per le prove. */
  now?: () => number;
  /** Il fuso (nome IANA, per esempio «Europe/Rome»); senza, quello del computer. */
  zone?: string;
}

interface Salvaged {
  sessions: StudySession[];
  version: number;
  dropped: number;
}

export class SessionLog {
  sessions: StudySession[] = [];
  /** Il file è di una versione più nuova, o non si legge, o non si può mettere da parte: si legge ma non si riscrive. */
  isReadOnly = false;
  /** L'ultima scrittura di `sessioni.json` non è riuscita: in memoria c'è più di quello che c'è sul disco. */
  hasUnsavedChanges = false;

  readonly directory: string;
  private readonly file: string;
  private readonly progressFile: string;
  private readonly backupDirectory: string;
  private readonly now: () => number;
  private readonly zone: string | undefined;
  private lastHeartbeat = -Infinity;
  private observers: Array<() => void> = [];
  private pendingProblems: string[] = [];
  private activeProblems = new Set<string>();
  private problemHandler: ((message: string) => void) | undefined;

  constructor(directory: string, options: LogOptions = {}) {
    this.directory = directory;
    this.now = options.now ?? (() => Date.now());
    this.zone = options.zone;
    this.file = join(directory, "sessioni.json");
    this.progressFile = join(directory, "in-corso.json");
    this.backupDirectory = join(directory, "backup");
    this.load();
  }

  /** Chiamata quando qualcosa non va con i dati: il testo è per chi usa l'app. I problemi nati nel costruttore arrivano appena ci si registra. */
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

  /** Segnala un problema una volta sola, finché non si risolve. */
  private fail(key: string, message: string): void {
    if (!this.activeProblems.has(key)) {
      this.activeProblems.add(key);
      this.report(message);
    }
  }

  private recover(key: string): void {
    this.activeProblems.delete(key);
  }

  private wall(instantMs: number): Wall {
    return wallOf(instantMs, this.zone);
  }

  // ---- lettura

  private load(): void {
    if (!existsSync(this.file)) return;
    const text = readText(this.file);
    if (text === null) {
      // C'è ma non si legge: non è come se non ci fosse, perché la prossima scrittura lo sostituirebbe.
      this.isReadOnly = true;
      this.report("Il file delle sessioni non si legge: non lo modifico. Controlla i permessi della cartella FocusFriends.");
      return;
    }
    let raw: unknown;
    let parsed = true;
    try {
      raw = JSON.parse(text.replace(/^\uFEFF/, ""));
    } catch {
      parsed = false;
    }
    let needsSave = false;

    const wrapped = parsed ? decodeWrapped(raw) : null;
    const legacy = parsed && wrapped === null ? decodeSessionList(raw) : null;
    if (wrapped) {
      this.sessions = wrapped.sessions;
      if (wrapped.version > FORMAT_VERSION) {
        this.isReadOnly = true;
        this.report("I dati sono di una versione più nuova di questa app: li leggo ma non li modifico, e i nuovi focus non vengono salvati.");
      } else if (wrapped.version < FORMAT_VERSION) {
        // Passo a un formato nuovo: tengo intatta la copia di quello vecchio.
        this.keepCopy(`sessioni-formato${wrapped.version}.json`, text);
        needsSave = true;
      }
    } else if (legacy) {
      // Formato precedente (la sola lista): tengo una copia intatta e passo al nuovo.
      this.keepCopy("sessioni-formato0.json", text);
      this.sessions = legacy;
      needsSave = true;
    } else {
      const salvaged = parsed ? salvage(raw) : null;
      if (salvaged) {
        // Qualche sessione non si legge: tengo le altre, e il file com'era resta come copia.
        this.sessions = salvaged.sessions;
        if (salvaged.version > FORMAT_VERSION) {
          this.isReadOnly = true;
          this.report("I dati sono di una versione più nuova dell'app e alcune sessioni non si leggono: non li modifico.");
        } else if (salvaged.dropped === 0) {
          needsSave = true;
        } else {
          const name = `sessioni.corrotto-${Math.floor(this.now() / 1000)}.json`;
          try {
            writeFileAtomic(join(this.directory, name), text);
            needsSave = true;
            this.report(`${salvaged.dropped} sessioni non erano leggibili: le altre sono a posto, e il file com'era è in ${name}.`);
          } catch {
            this.isReadOnly = true;
            this.report("Alcune sessioni non si leggono e non riesco a tenerne una copia: non modifico il file.");
          }
        }
      } else {
        // File rovinato: lo metto da parte invece di perderlo, e si riparte da vuoto.
        const name = `sessioni.corrotto-${Math.floor(this.now() / 1000)}.json`;
        try {
          renameSync(this.file, join(this.directory, name));
          this.report(`Il file delle sessioni era rovinato: l'ho messo da parte come ${name} e riparto da zero.`);
        } catch {
          // Non riesco a spostarlo: non lo sovrascrivo.
          this.isReadOnly = true;
          this.report("Il file delle sessioni è rovinato e non riesco a metterlo da parte: non lo modifico.");
        }
        this.sessions = [];
        return;
      }
    }

    if (this.normalize()) needsSave = true;
    if (needsSave && !this.isReadOnly) this.save();
  }

  /** Una copia intatta, in backup/ (senza avvisi: se non riesce, la riscrittura va avanti comunque, come sul Mac). */
  private keepCopy(name: string, text: string): void {
    try {
      writeFileAtomic(join(this.backupDirectory, name), text);
    } catch { /* come sul Mac: si prosegue */ }
  }

  /** Ogni materia con la scrittura più recente, e l'ora locale dove manca. Ritorna true se ha cambiato qualcosa. */
  private normalize(): boolean {
    let changed = false;
    const spelling = new Map<string, string>();
    for (const session of [...this.sessions].sort((a, b) => a.start - b.start)) {
      if (session.subject !== undefined) spelling.set(subjectKey(session.subject), session.subject);     // l'ultima vince
    }
    for (const session of this.sessions) {
      if (session.subject !== undefined) {
        const canonical = spelling.get(subjectKey(session.subject));
        if (canonical !== undefined && canonical !== session.subject) {
          session.subject = canonical;
          changed = true;
        }
      }
      if (session.localStart === undefined) {
        session.localStart = localString(this.wall(session.start));
        changed = true;
      }
    }
    return changed;
  }

  // ---- scrittura

  private save(): void {
    if (this.isReadOnly) return;
    try {
      mkdirSync(this.directory, { recursive: true });
      this.makeDailyBackupIfNeeded();
      writeFileAtomic(this.file, stringifyJson({ version: FORMAT_VERSION, sessions: this.sessions.map(encodeSession) }));
      this.hasUnsavedChanges = false;
      this.recover("save");
    } catch (error) {
      this.hasUnsavedChanges = true;
      this.fail("save", `Non riesco a salvare le sessioni sul disco (${(error as Error).message}): finché l'app resta aperta le vedi, ma se si chiude le perdo.`);
    }
    // Le viste mostrano lo stato in memoria, che è cambiato in ogni caso.
    this.observers.forEach((observer) => observer());
  }

  /** Prima della prima modifica della giornata copia il file com'era, e tiene solo le ultime 7. */
  private makeDailyBackupIfNeeded(): void {
    if (!existsSync(this.file)) return;
    const day = this.wall(this.now());
    const d = new Date(day);
    const name = `sessioni-${String(d.getUTCFullYear()).padStart(4, "0")}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-${String(d.getUTCDate()).padStart(2, "0")}.json`;
    const target = join(this.backupDirectory, name);
    if (existsSync(target)) return;
    try {
      mkdirSync(this.backupDirectory, { recursive: true });
      copyFileSync(this.file, target);
      this.recover("backup");
    } catch {
      this.fail("backup", "Non riesco a fare la copia di sicurezza di oggi delle sessioni.");
      return;
    }
    let daily: string[] = [];
    try {
      daily = readdirSync(this.backupDirectory).filter((n) => n.startsWith("sessioni-2") && n.endsWith(".json")).sort();
    } catch { /* niente da potare */ }
    if (daily.length > BACKUPS_TO_KEEP) {
      for (const old of daily.slice(0, daily.length - BACKUPS_TO_KEEP)) {
        try { rmSync(join(this.backupDirectory, old), { force: true }); } catch { /* resta */ }
      }
    }
  }

  // ---- modifiche

  /** La scrittura di una materia da usare: se esiste già con maiuscole o accenti diversi, vale quella più recente. */
  private canonicalSubject(cleaned: string | null): string | undefined {
    if (cleaned === null) return undefined;
    const key = subjectKey(cleaned);
    for (let i = this.sessions.length - 1; i >= 0; i -= 1) {
      const existing = this.sessions[i]?.subject;
      if (existing !== undefined && subjectKey(existing) === key) return existing;
    }
    return cleaned;
  }

  /** Aggiunge una sessione (se dura almeno un minuto) e ritorna quella salvata. */
  add(input: { start: number; seconds: number; plannedMinutes: number; completed: boolean; subject?: string | null; pet?: string | null; notes?: string[] | null }): StudySession | null {
    if (input.seconds < MINIMUM_SECONDS || this.isReadOnly) return null;
    const session: StudySession = {
      id: randomUUID().toUpperCase(), start: input.start, localStart: localString(this.wall(input.start)),
      seconds: input.seconds, plannedMinutes: input.plannedMinutes, completed: input.completed,
    };
    const subject = this.canonicalSubject(cleanSubject(input.subject));
    if (subject !== undefined) session.subject = subject;
    if (input.pet != null) session.pet = input.pet;
    const notes = cleanFocusNotes(input.notes);
    if (notes !== null) session.notes = notes;
    this.sessions.push(session);
    this.sessions.sort((a, b) => a.start - b.start);
    this.save();
    return session;
  }

  remove(id: string): void {
    if (this.isReadOnly) return;
    this.sessions = this.sessions.filter((s) => s.id !== id);
    this.save();
  }

  setSubject(id: string, subject: string | null): void {
    const session = this.find(id);
    if (!session) return;
    const next = this.canonicalSubject(cleanSubject(subject));
    if (next === undefined) delete session.subject; else session.subject = next;
    this.save();
  }

  /** «Com'è andata» e «cosa hai fatto» di una sessione (null = niente). */
  setReflection(id: string, rating: Rating | null, note: string | null): void {
    const session = this.find(id);
    if (!session) return;
    if (rating === null) delete session.rating; else session.rating = rating;
    const cleaned = cleanNote(note);
    if (cleaned === null) delete session.note; else session.note = cleaned;
    this.save();
  }

  /** Le note del focus di una sessione (una per riga; vuote = nessuna). */
  setNotes(id: string, notes: string[] | null): void {
    const session = this.find(id);
    if (!session) return;
    const cleaned = cleanFocusNotes(notes);
    if (cleaned === null) delete session.notes; else session.notes = cleaned;
    this.save();
  }

  private find(id: string): StudySession | undefined {
    if (this.isReadOnly) return undefined;
    return this.sessions.find((s) => s.id === id);
  }

  /** L'ultima nota scritta, con la sua materia: «L'ultima volta su Anatomia: nervi cranici». */
  lastNote(): { subject?: string; note: string } | null {
    for (let i = this.sessions.length - 1; i >= 0; i -= 1) {
      const session = this.sessions[i];
      if (session?.note) return session.subject === undefined ? { note: session.note } : { subject: session.subject, note: session.note };
    }
    return null;
  }

  /** Rinomina una materia in tutte le sessioni; se esiste già una materia con il nuovo nome le due si uniscono. Ritorna quante sessioni sono cambiate. */
  renameSubject(oldName: string, newName: string | null): number {
    if (this.isReadOnly) return 0;
    const oldKey = subjectKey(oldName);
    const target = this.canonicalSubject(cleanSubject(newName));
    let changed = 0;
    for (const session of this.sessions) {
      if (session.subject === undefined || subjectKey(session.subject) !== oldKey || session.subject === target) continue;
      if (target === undefined) delete session.subject; else session.subject = target;
      changed += 1;
    }
    if (changed > 0) this.save();
    return changed;
  }

  /** Cancella tutto: le sessioni, il focus in corso e le copie di sicurezza. Non si può annullare. */
  deleteAll(): void {
    this.sessions = [];
    this.isReadOnly = false;
    rmSync(this.file, { force: true });
    rmSync(this.progressFile, { force: true });
    rmSync(this.backupDirectory, { force: true, recursive: true });
    this.lastHeartbeat = -Infinity;
    this.observers.forEach((observer) => observer());
  }

  /** Le materie usate, dalla più recente: per i suggerimenti quando si avvia un focus. */
  recentSubjects(limit = 6): string[] {
    const seen = new Set<string>();
    const result: string[] = [];
    for (let i = this.sessions.length - 1; i >= 0; i -= 1) {
      const subject = this.sessions[i]?.subject;
      if (subject === undefined || seen.has(subjectKey(subject))) continue;
      seen.add(subjectKey(subject));
      result.push(subject);
      if (result.length === limit) break;
    }
    return result;
  }

  // ---- focus in corso

  beginInProgress(input: { start: number; plannedMinutes: number; subject?: string | null; pet?: string | null; notes?: string[] }): void {
    const progress: InProgress = { start: input.start, plannedMinutes: input.plannedMinutes, lastSeen: this.now() };
    if (input.subject != null) progress.subject = input.subject;
    if (input.pet != null) progress.pet = input.pet;
    if (input.notes && input.notes.length > 0) progress.notes = input.notes;
    // Lo stesso focus che si aggiorna (per esempio con «+5 minuti»): il tempo fermo non si perde.
    // (le date nel file hanno i secondi interi: si confronta con una tolleranza)
    const old = this.readProgress();
    if (old && Math.abs(old.start - input.start) < 1000) {
      if (old.pausedSeconds !== undefined) progress.pausedSeconds = old.pausedSeconds;
      if (old.pausedSince !== undefined) progress.pausedSince = old.pausedSince;
    }
    this.writeProgress(progress);
  }

  /** Quanto è rimasto fermo il focus in corso: `seconds` di pause già finite e, se è fermo adesso, da quando. */
  updateInProgressPause(seconds: number, since: number | null): void {
    const progress = this.readProgress();
    if (!progress) return;
    if (seconds > 0) progress.pausedSeconds = seconds; else delete progress.pausedSeconds;
    if (since === null) delete progress.pausedSince; else progress.pausedSince = since;
    this.writeProgress(progress);
  }

  /** Le note del focus in corso: si salvano subito. */
  updateInProgressNotes(notes: string[]): void {
    const progress = this.readProgress();
    if (!progress) return;
    if (notes.length > 0) progress.notes = notes; else delete progress.notes;
    this.writeProgress(progress);
  }

  /** Segna che l'app è ancora viva (al massimo una volta ogni 30 secondi). */
  heartbeat(at?: number): void {
    const moment = at ?? this.now();
    if (moment - this.lastHeartbeat < 30_000) return;
    const progress = this.readProgress();
    if (!progress) return;
    this.lastHeartbeat = moment;
    progress.lastSeen = moment;
    this.writeProgress(progress);
  }

  finishInProgress(): void {
    rmSync(this.progressFile, { force: true });
    this.lastHeartbeat = -Infinity;
  }

  /** All'avvio: se l'app si era chiusa di colpo durante un focus, lo salva come interrotto. */
  recoverInterrupted(): StudySession | null {
    const progress = this.readProgress();
    if (!progress) return null;
    // Il tempo fermo non è studio: né le pause già finite né quella in corso quando l'app si è chiusa.
    let stopped = progress.pausedSeconds ?? 0;
    if (progress.pausedSince !== undefined) stopped += Math.max(0, (progress.lastSeen - progress.pausedSince) / 1000);
    const seconds = Math.max(0, Math.trunc((progress.lastSeen - progress.start) / 1000 - stopped));
    const capped = Math.min(seconds, progress.plannedMinutes * 60);
    const session = this.add({
      start: progress.start, seconds: capped, plannedMinutes: progress.plannedMinutes, completed: false,
      subject: progress.subject ?? null, pet: progress.pet ?? null, notes: progress.notes ?? null,
    });
    // Il segno «in corso» si toglie solo dopo averlo salvato; se il registro è in sola lettura resta dov'è
    // (sotto il minuto, invece, non c'è niente da conservare).
    if (session !== null || !this.isReadOnly) this.finishInProgress();
    return session;
  }

  private readProgress(): InProgress | null {
    return decodeInProgress(readJson(this.progressFile));
  }

  private writeProgress(progress: InProgress): void {
    try {
      writeFileAtomic(this.progressFile, stringifyJson(encodeInProgress(progress)));
      this.recover("progress");
    } catch {
      this.fail("progress", "Non riesco a salvare il focus in corso: se l'app si chiude di colpo non lo recupero.");
    }
  }
}

// ---- lettura di un file di sessioni

function decodeSessionList(raw: unknown): StudySession[] | null {
  if (!Array.isArray(raw)) return null;
  const sessions: StudySession[] = [];
  for (const item of raw) {
    const session = decodeSession(item);
    if (session === null) return null;
    sessions.push(session);
  }
  return sessions;
}

function decodeWrapped(raw: unknown): { version: number; sessions: StudySession[] } | null {
  if (!isRecord(raw)) return null;
  const version = raw["version"];
  if (!isInteger(version)) return null;
  const sessions = decodeSessionList(raw["sessions"]);
  return sessions === null ? null : { version, sessions };
}

/** Legge una sessione alla volta: ritorna quelle leggibili, la versione e quante non lo erano; null se non è un elenco di sessioni. */
function salvage(raw: unknown): Salvaged | null {
  let version = 0;
  let items: unknown[];
  if (isRecord(raw) && Array.isArray(raw["sessions"])) {
    const declared = raw["version"];
    version = isInteger(declared) ? declared : 0;
    items = raw["sessions"];
  } else if (Array.isArray(raw)) {
    items = raw;
  } else {
    return null;
  }
  const sessions: StudySession[] = [];
  for (const item of items) {
    const session = decodeSession(item);
    if (session !== null) sessions.push(session);
  }
  return { sessions, version, dropped: items.length - sessions.length };
}
