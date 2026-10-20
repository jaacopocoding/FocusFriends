// Gli indirizzi che le finestre dell'app possono aprire: solo le pagine dell'app stessa (`ff://app/…`, vedi main/protocol.ts).

/** Un indirizzo delle pagine dell'app. Tutto il resto (web, file, altri schemi) non si apre. */
export function isAppUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    return parsed.protocol === "ff:" && parsed.host === "app";
  } catch {
    return false;
  }
}

/** Come si scrive un indirizzo rifiutato nel registro dell'app: solo schema e sito, mai il percorso né i parametri. */
export function describeUrl(url: string): string {
  try {
    const parsed = new URL(url);
    return parsed.origin !== "null" ? parsed.origin : `${parsed.protocol}…`;
  } catch {
    return "indirizzo non valido";
  }
}
