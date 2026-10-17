// I brani del focus, senza toccare il disco (si usano anche dalla pagina): quali file sono audio, che nome leggibile hanno, in che
// ordine suonano.

export const AUDIO_EXTENSIONS: ReadonlySet<string> = new Set(["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "caf"]);

/** L'ultimo pezzo di un percorso (con «/» o «\»). */
const baseName = (path: string): string => path.split(/[\\/]/).filter((part) => part !== "").at(-1) ?? "";

function extension(name: string): string {
  const dot = name.lastIndexOf(".");
  return dot <= 0 ? "" : name.slice(dot + 1).toLowerCase();
}

export function isAudio(path: string): boolean {
  const name = baseName(path);
  return AUDIO_EXTENSIONS.has(extension(name)) && !name.startsWith(".");
}

/** Un ordine casuale; il primo brano non è mai quello appena suonato (se ce n'è più di uno). */
export function shuffled(tracks: readonly string[], avoidingFirst: string | null, random: () => number = Math.random): string[] {
  const result = [...tracks];
  for (let i = result.length - 1; i > 0; i -= 1) {
    const j = Math.floor(random() * (i + 1));
    [result[i], result[j]] = [result[j]!, result[i]!];
  }
  if (result.length > 1 && avoidingFirst !== null && result[0] === avoidingFirst) [result[0], result[1]] = [result[1]!, result[0]!];
  return result;
}

/** Un nome leggibile dal nome del file: «01_dreamy_night.m4a» → «dreamy night». */
export function titleOf(path: string): string {
  let name = baseName(path);
  const dot = name.lastIndexOf(".");
  if (dot > 0) name = name.slice(0, dot);
  if (name.startsWith("music_")) name = name.slice("music_".length);
  name = name.replaceAll("_", " ").replaceAll("-", " ");
  // toglie un numero d'ordine iniziale («01 », «2. »)
  name = name.replace(/^\d+[.\s]+/, "");
  return name.split(" ").filter((part) => part !== "").join(" ");
}
