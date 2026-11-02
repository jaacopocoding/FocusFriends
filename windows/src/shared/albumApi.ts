// Il contratto tra il processo principale e la finestra dell'album. Il giardino sta nel processo principale: la pagina riceve cosa si è trovato
// e lo disegna con il catalogo (`core/gardenCatalog.ts`).

import type { Season } from "../core/gardenSky.ts";

export interface AlbumData {
  /** Gli oggetti trovati, e quelli non ancora visti nell'album (portano il nastrino «NUOVA»). */
  has: string[];
  unseen: string[];
  /** Quante copie di ogni oggetto ci sono sulle isole. */
  counts: Record<string, number>;
  /** I compagni: il nome e se sono sbloccati (chi non c'è ancora resta «???» sulle figurine delle sue cose). */
  islands: Array<{ id: string; name: string; open: boolean }>;
  /** Il nome di chi usa l'app (la copertina dice «di Jacopo»), o null. */
  owner: string | null;
  /** Il titolo della finestra («L'album di Jacopo»). */
  title: string;
  season: Season;
  /** La doppia pagina dov'era rimasto il libro. */
  spread: number;
  /** La finestra si è appena (ri)aperta: il libro torna chiuso. */
  prepare?: boolean;
}

export interface AlbumApi {
  getData(): Promise<AlbumData>;
  onData(callback: (data: AlbumData) => void): void;
  /** Il libro si è aperto: le figurine nuove non sono più nuove. */
  markSeen(): void;
  /** La doppia pagina mostrata (si ricorda per la prossima volta). */
  setSpread(index: number): void;
  /** «‹ Menu»: la finestra si chiude e si torna alla scheda. */
  back(): void;
}

export const ALBUM_CHANNEL = {
  getData: "album:get-data",
  data: "album:data",
  markSeen: "album:mark-seen",
  setSpread: "album:set-spread",
  back: "album:back",
} as const;
