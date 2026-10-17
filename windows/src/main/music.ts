// I brani del focus: quelli inclusi nell'app o quelli della cartella scelta. La pagina non legge il disco: chiede l'elenco qui e poi
// riceve i file da `ff://app/music/<versione>/<numero>` (la versione cambia a ogni elenco nuovo, così un numero vecchio non vale più).

import { readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { hasTracks, isAudio, titleOf, tracksIn } from "../core/music.ts";
import type { MusicSource } from "../core/rules.ts";
import type { MusicList } from "../shared/api.ts";

export interface MusicService {
  list(source: MusicSource): MusicList;
  /** Il file del brano `id` dell'elenco `version`, se è ancora quello valido. */
  file(version: number, id: number): string | null;
  /** Nella cartella scelta c'è almeno un brano? */
  folderHasTracks(): boolean;
  /** Prepara l'elenco della cartella in secondo piano (alla scelta e all'avvio), così il primo focus non aspetta. */
  prepareFolder(): void;
}

export function createMusicService(options: { assets: string; folder: () => string | null }): MusicService {
  let version = 0;
  let current: string[] = [];
  // La scansione della cartella è ricorsiva e può essere lunga (dischi grandi o di rete): non si rifà a ogni focus.
  let cache: { folder: string; modified: number | null; tracks: string[] } | null = null;

  const modifiedOf = (folder: string): number | null => {
    try { return statSync(folder).mtimeMs; } catch { return null; }
  };

  const folderTracks = (): string[] => {
    const folder = options.folder();
    if (folder === null) return [];
    const modified = modifiedOf(folder);
    if (cache && cache.folder === folder && cache.modified === modified) return cache.tracks;
    const tracks = tracksIn(folder);
    cache = { folder, modified, tracks };
    return tracks;
  };

  /** I brani inclusi nell'app (`assets/music`), in ordine di nome. */
  const bundledTracks = (): string[] => {
    const directory = join(options.assets, "music");
    try {
      return readdirSync(directory).filter((name) => isAudio(name)).sort().map((name) => join(directory, name));
    } catch {
      return [];
    }
  };

  return {
    list(source) {
      current = source === "bundled" ? bundledTracks() : source === "folder" ? folderTracks() : [];
      version += 1;
      return { version, tracks: current.map((path, id) => ({ id, title: titleOf(path) })) };
    },
    file(requested, id) {
      return requested === version ? current[id] ?? null : null;
    },
    folderHasTracks() {
      const folder = options.folder();
      if (folder === null) return false;
      if (cache && cache.folder === folder && cache.modified === modifiedOf(folder)) return cache.tracks.length > 0;
      return hasTracks(folder);
    },
    prepareFolder() {
      setImmediate(() => { folderTracks(); });
    },
  };
}
