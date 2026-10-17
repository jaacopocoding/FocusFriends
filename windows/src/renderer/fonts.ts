// Il carattere «pennarello» dei titoli e dei fumetti: sta in una variabile del foglio di stile (`--marker`), così lo si cambia in un posto solo.

let cached: string | null = null;

/** Le famiglie del carattere pennarello, come stanno in `--marker` (per i disegni sul canvas). */
export function markerFamily(): string {
  if (cached === null) cached = getComputedStyle(document.documentElement).getPropertyValue("--marker").trim() || "cursive";
  return cached;
}

/** Dimentica quello letto (dopo aver cambiato `--marker`, nelle prove). */
export function resetMarkerFamily(): void {
  cached = null;
}
