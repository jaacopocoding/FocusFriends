// La musica del focus sul disco: i file di una cartella (MusicLibrary.swift). Le parti che non toccano il disco sono in tracks.ts.

import { opendirSync, statSync } from "node:fs";
import { join } from "node:path";
import { isAudio } from "./tracks.ts";

export { AUDIO_EXTENSIONS, isAudio, shuffled, titleOf } from "./tracks.ts";

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
