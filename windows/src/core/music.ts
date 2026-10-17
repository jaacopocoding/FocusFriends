// La musica del focus: quali file ci sono e in che ordine suonano (MusicLibrary.swift).

import { opendirSync, statSync } from "node:fs";
import { basename, extname, join } from "node:path";

export const AUDIO_EXTENSIONS: ReadonlySet<string> = new Set(["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "caf"]);

export function isAudio(path: string): boolean {
  const name = basename(path);
  return AUDIO_EXTENSIONS.has(extname(name).slice(1).toLowerCase()) && !name.startsWith(".");
}

const collator = new Intl.Collator("it", { numeric: true, sensitivity: "base" });

/** Visita una cartella e le sue sottocartelle (senza file e cartelle nascosti) e si ferma quando `visit` dice di sì. */
function walk(folder: string, visit: (file: string) => boolean): boolean {
  let directory;
  try {
    directory = opendirSync(folder);
  } catch {
    return false;
  }
  try {
    for (let entry = directory.readSync(); entry !== null; entry = directory.readSync()) {
      if (entry.name.startsWith(".")) continue;
      const path = join(folder, entry.name);
      let isDirectory = entry.isDirectory(), isFile = entry.isFile();
      if (entry.isSymbolicLink()) {
        try {
          const target = statSync(path);
          isDirectory = target.isDirectory();
          isFile = target.isFile();
        } catch {
          continue;
        }
      }
      if (isFile && visit(path)) return true;
      if (isDirectory && walk(path, visit)) return true;
    }
  } finally {
    directory.closeSync();
  }
  return false;
}

/** I file audio di una cartella (anche nelle sottocartelle), in ordine di nome («2» prima di «10»). Niente file nascosti. */
export function tracksIn(folder: string): string[] {
  const found: string[] = [];
  walk(folder, (file) => {
    if (isAudio(file)) found.push(file);
    return false;
  });
  return found.sort((a, b) => collator.compare(a, b));
}

/** C'è almeno un brano? Si ferma al primo trovato: per sapere solo se la cartella è vuota non serve elencarla tutta. */
export function hasTracks(folder: string): boolean {
  return walk(folder, isAudio);
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
  let name = basename(path, extname(path));
  if (name.startsWith("music_")) name = name.slice("music_".length);
  name = name.replaceAll("_", " ").replaceAll("-", " ");
  // toglie un numero d'ordine iniziale («01 », «2. »)
  name = name.replace(/^\d+[.\s]+/, "");
  return name.split(" ").filter((part) => part !== "").join(" ");
}
