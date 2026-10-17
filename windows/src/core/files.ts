// Scrittura e lettura dei file dei dati (FORMATI.md §1): atomica, in UTF-8, con le chiavi in ordine alfabetico.

import { mkdirSync, readFileSync, renameSync, writeFileSync, rmSync } from "node:fs";
import { dirname } from "node:path";
import { randomBytes } from "node:crypto";

/** JSON con 2 spazi di rientro, chiavi in ordine alfabetico e «"chiave" : valore», come lo scrive l'app per Mac. */
export function stringifyJson(value: unknown, indent = ""): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value) ?? "null";
  const inner = indent + "  ";
  if (Array.isArray(value)) {
    if (value.length === 0) return "[]";
    return "[\n" + value.map((v) => inner + stringifyJson(v, inner)).join(",\n") + "\n" + indent + "]";
  }
  const entries = Object.entries(value as Record<string, unknown>)
    .filter(([, v]) => v !== undefined)
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
  if (entries.length === 0) return "{}";
  return "{\n" + entries.map(([k, v]) => `${inner}${JSON.stringify(k)} : ${stringifyJson(v, inner)}`).join(",\n") + "\n" + indent + "}";
}

/** Scrive in un file temporaneo nella stessa cartella e lo rinomina sopra quello vecchio: a metà non resta un file mozzo. */
export function writeFileAtomic(path: string, text: string): void {
  mkdirSync(dirname(path), { recursive: true });
  const temp = `${path}.${randomBytes(4).toString("hex")}.tmp`;
  try {
    writeFileSync(temp, text, "utf8");
    renameSync(temp, path);
  } catch (error) {
    try { rmSync(temp, { force: true }); } catch { /* niente da fare */ }
    throw error;
  }
}

/** Il contenuto di un file di testo, o null se non si legge. */
export function readText(path: string): string | null {
  try {
    return readFileSync(path, "utf8");
  } catch {
    return null;
  }
}

/** Il JSON di un file: null se manca, non si legge o non è JSON. */
export function readJson(path: string): unknown {
  const text = readText(path);
  if (text === null) return null;
  try {
    return JSON.parse(text.replace(/^\uFEFF/, ""));
  } catch {
    return null;
  }
}
