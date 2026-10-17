// Le frasi dei compagni (FORMATI.md §7): il file dell'utente ha la precedenza su quello incluso nell'app, e si pescano
// da un mazzo mischiato.

import { join } from "node:path";
import { readText } from "./files.ts";
import { petInfo } from "./pets.ts";

/** Il nome del file delle frasi di un compagno (sia quello incluso sia quello dell'utente). */
export function phrasesFileName(petId: string): string {
  return `frasi_${petId}.txt`;
}

/** Una frase per riga; le righe vuote e quelle che iniziano con `#` si ignorano; gli spazi ai bordi si tolgono. */
export function parsePhrases(text: string): string[] {
  return text
    .split(/\r\n|[\n\r\u000B\u000C\u0085\u2028\u2029]/)
    .map((line) => line.replace(/^[\p{Zs}\t]+|[\p{Zs}\t]+$/gu, ""))
    .filter((line) => line !== "" && !line.startsWith("#"));
}

export interface PhraseSources {
  /** La cartella dei dati dell'utente (dove può mettere il suo `frasi_<personaggio>.txt`). */
  userDirectory: string;
  /** La cartella con i file inclusi nell'app. */
  bundledDirectory: string;
}

/** Le frasi di un compagno: il file dell'utente, poi quello incluso; senza nessuna frase, quella di riserva. */
export function loadPhrases(petId: string, sources: PhraseSources): string[] {
  for (const directory of [sources.userDirectory, sources.bundledDirectory]) {
    const text = readText(join(directory, phrasesFileName(petId)));
    if (text === null) continue;
    const lines = parsePhrases(text.replace(/^\uFEFF/, ""));
    if (lines.length > 0) return lines;
  }
  return [petInfo(petId).fallbackQuote];
}

/**
 * Un mazzo di frasi: escono tutte, in ordine casuale, prima che una qualsiasi si ripeta. Finito il mazzo se ne rimescola
 * uno nuovo; la prima frase del nuovo mazzo non è mai uguale all'ultima uscita. Se il file delle frasi cambia a metà mazzo,
 * il mazzo si aggiorna: le frasi tolte spariscono e quelle nuove entrano in posizioni a caso, senza far ripetere quelle
 * già uscite.
 */
export class PhraseDeck {
  private remaining: string[] = [];     // ancora da dire in questo giro, nell'ordine in cui usciranno
  private seen = new Set<string>();     // già dette in questo giro
  last: string | null = null;

  private readonly random: () => number;

  constructor(random: () => number = Math.random) {
    this.random = random;
  }

  private int(lowerInclusive: number, upperExclusive: number): number {
    return lowerInclusive + Math.floor(this.random() * (upperExclusive - lowerInclusive));
  }

  draw(phrases: readonly string[]): string | null {
    const unique = [...new Set(phrases)];
    if (unique.length === 0) return null;
    const known = new Set(unique);

    // Allinea il mazzo al file: via le frasi tolte, dentro quelle nuove (in posizioni a caso).
    this.remaining = this.remaining.filter((phrase) => known.has(phrase));
    this.seen = new Set([...this.seen].filter((phrase) => known.has(phrase)));
    for (const phrase of unique) {
      if (this.remaining.includes(phrase) || this.seen.has(phrase)) continue;
      this.remaining.splice(this.int(0, this.remaining.length + 1), 0, phrase);
    }

    // Mazzo finito: se ne rimescola uno nuovo.
    if (this.remaining.length === 0) {
      this.remaining = [...unique];
      for (let i = this.remaining.length - 1; i > 0; i -= 1) {
        const j = this.int(0, i + 1);
        [this.remaining[i], this.remaining[j]] = [this.remaining[j]!, this.remaining[i]!];
      }
      this.seen = new Set();
      if (this.remaining.length > 1 && this.remaining[0] === this.last) {
        const j = this.int(1, this.remaining.length);
        [this.remaining[0], this.remaining[j]] = [this.remaining[j]!, this.remaining[0]!];
      }
    }

    const next = this.remaining.shift()!;
    this.seen.add(next);
    this.last = next;
    return next;
  }
}
