// La lista delle cose da fare: sta in `dafare.json` accanto ai dati (FORMATI.md §9). Stesse regole di ToDoList in ToDo.swift:
// le voci si ripuliscono alla lettura, quelle fatte da più di 7 giorni spariscono, un file rovinato si mette da parte e uno
// di una versione più nuova si legge senza riscriverlo.

import { randomUUID } from "node:crypto";
import { existsSync, renameSync } from "node:fs";
import { join } from "node:path";
import { readText, stringifyJson, writeFileAtomic } from "./files.ts";
import { cleanSubject } from "./text.ts";
import { isoUtc, parseIsoUtc } from "./time.ts";
import { cleanToDoText, doneItems, isValidDay, openItems, sections, TODO_KEEP_DONE_DAYS, TODO_MAX_ITEMS } from "./todo.ts";
import type { ToDoItem, ToDoSection } from "./todo.ts";

export const TODO_FORMAT_VERSION = 1;

const UUID_PATTERN = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

export type AddResult = { kind: "added"; item: ToDoItem } | { kind: "empty" } | { kind: "full" };

export interface ToDoListOptions {
  now?: () => number;
}

/** Una voce letta dal file così com'è, o null se un campo manca o ha il tipo sbagliato (allora tutto il file è rovinato, come in Swift). */
function decodeItem(raw: unknown): ToDoItem | null {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) return null;
  const source = raw as Record<string, unknown>;
  const id = source["id"], text = source["text"];
  if (typeof id !== "string" || !UUID_PATTERN.test(id) || typeof text !== "string") return null;
  const createdAt = parseIsoUtc(source["createdAt"]);
  if (createdAt === null) return null;
  const optionalString = (key: string): string | null | undefined => {
    const value = source[key];
    if (value === undefined || value === null) return null;
    return typeof value === "string" ? value : undefined;
  };
  const due = optionalString("due"), subject = optionalString("subject");
  if (due === undefined || subject === undefined) return null;
  let doneAt: number | null = null;
  const done = source["doneAt"];
  if (done !== undefined && done !== null) {
    doneAt = parseIsoUtc(done);
    if (doneAt === null) return null;
  }
  return { id: id.toUpperCase(), text, due, subject, createdAt, doneAt };
}

function decode(raw: unknown): { version: number; items: ToDoItem[] } | null {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) return null;
  const source = raw as Record<string, unknown>;
  const version = source["version"], items = source["items"];
  if (typeof version !== "number" || !Number.isInteger(version) || !Array.isArray(items)) return null;
  const decoded: ToDoItem[] = [];
  for (const entry of items) {
    const item = decodeItem(entry);
    if (item === null) return null;
    decoded.push(item);
  }
  return { version, items: decoded };
}

/** Una voce letta dal file, ripulita: testo vuoto = si scarta, scadenza che non esiste = si toglie, materia pulita. */
function sanitized(item: ToDoItem): ToDoItem | null {
  const text = cleanToDoText(item.text);
  if (text === null) return null;
  return { ...item, text, due: item.due !== null && isValidDay(item.due) ? item.due : null, subject: cleanSubject(item.subject) };
}

export class ToDoList {
  readonly directory: string;
  private readonly file: string;
  private readonly now: () => number;
  private _items: ToDoItem[] = [];
  private _readOnly = false;
  private observers: Array<() => void> = [];
  private pendingProblems: string[] = [];
  private problemHandler: ((message: string) => void) | undefined;
  private writeFailureReported = false;

  constructor(directory: string, options: ToDoListOptions = {}) {
    this.directory = directory;
    this.file = join(directory, "dafare.json");
    this.now = options.now ?? (() => Date.now());
    this.load();
  }

  get items(): readonly ToDoItem[] { return this._items; }
  get isReadOnly(): boolean { return this._readOnly; }
  get openCount(): number { return openItems(this._items).length; }
  get doneItems(): ToDoItem[] { return doneItems(this._items); }
  sections(today: string): ToDoSection[] { return sections(this._items, today); }

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
      this._readOnly = true;
      this.report("Il file delle cose da fare non si legge: non lo modifico.");
      return;
    }
    let contents: ReturnType<typeof decode> = null;
    try {
      contents = decode(JSON.parse(text.replace(/^﻿/, "")));
    } catch {
      contents = null;
    }
    if (contents !== null) {
      if (contents.version > TODO_FORMAT_VERSION) {
        this._readOnly = true;
        this.report("Il file delle cose da fare è di una versione più nuova dell'app: lo leggo ma non lo modifico.");
      }
      this._items = contents.items.flatMap((item) => { const clean = sanitized(item); return clean === null ? [] : [clean]; });
      if (!this._readOnly) this.purgeOldDone();
      return;
    }
    const asideName = `dafare.corrotto-${Math.floor(this.now() / 1000)}.json`;
    try {
      renameSync(this.file, join(this.directory, asideName));
      this.report(`Il file delle cose da fare era rovinato: l'ho messo da parte come ${asideName}.`);
    } catch {
      this._readOnly = true;
      this.report("Il file delle cose da fare è rovinato e non riesco a metterlo da parte: non lo modifico.");
    }
  }

  // ---- modifiche

  add(text: string, due: string | null = null, subject: string | null = null): AddResult {
    const cleaned = cleanToDoText(text);
    if (cleaned === null) return { kind: "empty" };
    if (this._items.length >= TODO_MAX_ITEMS) return { kind: "full" };
    const item: ToDoItem = {
      id: randomUUID().toUpperCase(), text: cleaned, due: due !== null && isValidDay(due) ? due : null,
      subject: cleanSubject(subject), createdAt: this.now(), doneAt: null,
    };
    this._items.push(item);
    this.save();
    return { kind: "added", item };
  }

  /** Cambia il testo, la scadenza e la materia di una voce (la data di quando è stata scritta e se è fatta non cambiano). */
  update(id: string, text: string, due: string | null, subject: string | null): "updated" | "empty" | "missing" {
    const item = this._items.find((x) => x.id === id);
    if (!item) return "missing";
    const cleaned = cleanToDoText(text);
    if (cleaned === null) return "empty";
    const newDue = due !== null && isValidDay(due) ? due : null;
    const newSubject = cleanSubject(subject);
    if (item.text === cleaned && item.due === newDue && item.subject === newSubject) return "updated";
    item.text = cleaned;
    item.due = newDue;
    item.subject = newSubject;
    this.save();
    return "updated";
  }

  /** Segna come fatta (o rimette tra quelle da fare). */
  toggleDone(id: string): void {
    const item = this._items.find((x) => x.id === id);
    if (!item) return;
    item.doneAt = item.doneAt === null ? this.now() : null;
    this.save();
  }

  remove(id: string): void {
    if (!this._items.some((x) => x.id === id)) return;
    this._items = this._items.filter((x) => x.id !== id);
    this.save();
  }

  /** Toglie le voci fatte da più di 7 giorni (non scrive: lo fa chi chiama). */
  private purgeOldDone(): void {
    const limit = this.now() - TODO_KEEP_DONE_DAYS * 86_400_000;
    this._items = this._items.filter((item) => item.doneAt === null || item.doneAt >= limit);
  }

  private save(): void {
    this.purgeOldDone();
    if (this._readOnly) {
      this.observers.forEach((observer) => observer());
      return;
    }
    const contents = {
      version: TODO_FORMAT_VERSION,
      items: this._items.map((item) => ({
        id: item.id, text: item.text, due: item.due ?? undefined, subject: item.subject ?? undefined,
        createdAt: isoUtc(item.createdAt), doneAt: item.doneAt === null ? undefined : isoUtc(item.doneAt),
      })),
    };
    try {
      writeFileAtomic(this.file, stringifyJson(contents) + "\n");
      this.writeFailureReported = false;
    } catch (error) {
      if (!this.writeFailureReported) {
        this.writeFailureReported = true;
        this.report(`Non riesco a salvare le cose da fare: ${error instanceof Error ? error.message : String(error)}.`);
      }
    }
    this.observers.forEach((observer) => observer());
  }
}
