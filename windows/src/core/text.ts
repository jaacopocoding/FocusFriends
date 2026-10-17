// La pulizia dei testi scritti dall'utente: materie, note, nome. Stesse regole dell'app per Mac (FORMATI.md §2.3 e §4).

const graphemes = new Intl.Segmenter("it", { granularity: "grapheme" });

/** I primi `count` «caratteri» come li vede chi legge (una lettera con l'accento o una bandiera valgono uno). */
export function prefixCharacters(text: string, count: number): string {
  let out = "";
  let taken = 0;
  for (const part of graphemes.segment(text)) {
    if (taken === count) break;
    out += part.segment;
    taken += 1;
  }
  return out;
}

const WHITESPACE = /[\s\u0085]+/u;
/** I caratteri di controllo e di formato (categorie Unicode Cc e Cf: tabulazioni, a capo, zero-width...). */
const CONTROL = /[\p{Cc}\p{Cf}]/gu;

function words(text: string): string[] {
  return text.split(WHITESPACE).filter((w) => w !== "");
}

// ---- materia

export const SUBJECT_MAX = 40;
export const NO_SUBJECT = "Senza materia";

/** Toglie gli spazi in eccesso (e basta: i caratteri di controllo restano); vuota = nessuna materia. */
export function cleanSubject(text: string | null | undefined): string | null {
  if (text == null) return null;
  const joined = words(text).join(" ");
  return joined === "" ? null : prefixCharacters(joined, SUBJECT_MAX);
}

/** Con cosa due scritture sono la stessa materia: senza maiuscole e senza accenti («Fisica» = «Física» = «FISICA»). */
export function subjectKey(text: string): string {
  return text.normalize("NFD").replace(/\p{M}/gu, "").toLocaleLowerCase("it");
}

// ---- note

export const NOTE_MAX = 80;
export const FOCUS_NOTE_MAX = 160;
export const FOCUS_NOTES_COUNT = 40;

function cleanLine(text: string | null | undefined, max: number): string | null {
  if (text == null) return null;
  const joined = words(text).map((w) => w.replace(CONTROL, "")).filter((w) => w !== "").join(" ");
  return joined === "" ? null : prefixCharacters(joined, max);
}

/** La riga «cosa hai fatto» di un focus: al massimo 80 caratteri; vuota = nessuna. */
export function cleanNote(text: string | null | undefined): string | null {
  return cleanLine(text, NOTE_MAX);
}

/** Una nota scritta durante il focus: al massimo 160 caratteri. */
export function cleanFocusNote(text: string | null | undefined): string | null {
  return cleanLine(text, FOCUS_NOTE_MAX);
}

/** Le note di un focus: senza vuote, al massimo 40. Nessuna = null (il campo non sta nel file). */
export function cleanFocusNotes(list: readonly string[] | null | undefined): string[] | null {
  if (list == null) return null;
  const cleaned = list.map(cleanFocusNote).filter((n): n is string => n !== null);
  return cleaned.length === 0 ? null : cleaned.slice(0, FOCUS_NOTES_COUNT);
}

// ---- nome

export const NAME_MAX = 24;

/**
 * Il nome: prima si tolgono i caratteri di controllo (lo spazio resta, e anche tabulazioni e a capo spariscono), poi si
 * uniscono le parole con uno spazio solo; al massimo 24 caratteri; vuoto = nessun nome.
 */
export function cleanName(text: string | null | undefined): string | null {
  if (text == null) return null;
  const visible = text.replace(/[\p{Cc}\p{Cf}]/gu, (c) => (c === " " ? " " : ""));
  const joined = words(visible).join(" ");
  return joined === "" ? null : prefixCharacters(joined, NAME_MAX);
}
