// Il registro dell'app, per capire cosa è successo dopo un arresto inatteso: una riga per fatto (avvio, chiusura, errori, processi caduti),
// senza dati personali (niente nomi, materie o note: solo cosa ha fatto l'app) e senza il nome dell'utente nei percorsi. Non fa mai cadere l'app.

import { appendFileSync, mkdirSync, renameSync, rmSync, statSync } from "node:fs";
import { join } from "node:path";

export interface AppLogOptions {
  /** Dove sta il file `registro-app.log` (la cartella dei dati). */
  directory: string;
  /** Oltre questa dimensione il file diventa `registro-app.1.log` e se ne comincia uno nuovo. */
  maxBytes?: number;
  now?: () => number;
  /** La cartella dell'utente: nei messaggi diventa «~». */
  home?: string;
}

export const MAX_MESSAGE = 4000;

export class AppLog {
  readonly file: string;
  private readonly older: string;
  private readonly maxBytes: number;
  private readonly now: () => number;
  private readonly home: string | undefined;

  constructor(options: AppLogOptions) {
    this.file = join(options.directory, "registro-app.log");
    this.older = join(options.directory, "registro-app.1.log");
    this.maxBytes = options.maxBytes ?? 200_000;
    this.now = options.now ?? (() => Date.now());
    this.home = options.home && options.home.length > 3 ? options.home : undefined;
    try { mkdirSync(options.directory, { recursive: true }); } catch { /* si prova lo stesso a scrivere */ }
  }

  /** Il testo senza il percorso della cartella dell'utente e a una lunghezza ragionevole. */
  sanitize(text: string): string {
    let result = text;
    if (this.home) {
      // La cartella dell'utente, scritta con la barra giusta o con quella sbagliata, e senza badare alle maiuscole.
      const parts = this.home.split(/[\\/]+/).filter((part) => part !== "").map((part) => part.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
      const leading = /^[\\/]/.test(this.home) ? "[\\\\/]" : "";
      result = result.replace(new RegExp(leading + parts.join("[\\\\/]+"), "gi"), "~");
    }
    return result.length > MAX_MESSAGE ? `${result.slice(0, MAX_MESSAGE)}…` : result;
  }

  private write(level: string, message: string): void {
    try {
      try {
        if (statSync(this.file).size > this.maxBytes) {
          rmSync(this.older, { force: true });
          renameSync(this.file, this.older);
        }
      } catch { /* il file non c'è ancora */ }
      const line = `${new Date(this.now()).toISOString()} ${level} ${this.sanitize(message).replace(/\r?\n/g, "\n    ")}\n`;
      appendFileSync(this.file, line, "utf8");
    } catch {
      /* il registro non deve mai far cadere niente */
    }
  }

  info(message: string): void { this.write("INFO", message); }
  warn(message: string): void { this.write("WARN", message); }

  error(message: string, error?: unknown): void {
    const detail = error instanceof Error ? `${error.name}: ${error.message}${error.stack ? `\n${error.stack}` : ""}` : error === undefined ? "" : String(error);
    this.write("ERROR", detail === "" ? message : `${message}: ${detail}`);
  }
}
