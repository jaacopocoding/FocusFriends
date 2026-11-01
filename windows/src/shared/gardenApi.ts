// Il contratto tra il processo principale e la finestra del giardino. Il giardino (`core/garden.ts`) sta nel processo principale: la pagina
// riceve una fotografia di com'è adesso e la disegna con le regole di `core/garden*.ts`, che non toccano il disco.

import type { GardenPlacement, GardenTile } from "../core/gardenGrid.ts";
import type { Season } from "../core/gardenSky.ts";

export interface GardenIslandData {
  id: string;
  /** Quante tessere per lato. */
  size: number;
  /** Il compagno è sbloccato (le isole chiuse sono al buio). */
  open: boolean;
  /** Il nome del compagno («Gattino»). */
  name: string;
  placements: GardenPlacement[];
  /** Dove sta il compagno dell'isola (se è aperta). */
  companion: GardenTile | null;
}

export interface GardenData {
  /** Le isole, nell'ordine dei compagni. */
  islands: GardenIslandData[];
  /** L'isola mostrata (quella viva) e quella di casa. */
  shown: string;
  home: string;
  /** I ponti già costruiti (`pianty-porcellino`…). */
  bridges: string[];
  /** L'ora sull'orologio, con la virgola, e la stagione che si vede (tutte e due si possono forzare per provarle). */
  hour: number;
  season: Season;
  /** Il titolo della finestra («Il giardino di Marco»). */
  title: string;
  /** Quante figurine si sono trovate e quante sono in tutto. */
  found: number;
  total: number;
  /** Quanti minuti di studio mancano alla prossima figurina (null se non c'è più niente da trovare) e quanta strada si è fatta. */
  minutesToNextGift: number | null;
  nextGiftProgress: number | null;
}

export interface GardenApi {
  getData(): Promise<GardenData>;
  /** Il giardino è cambiato (una figurina nuova, un compagno sbloccato…): i dati nuovi. */
  onData(callback: (data: GardenData) => void): void;
  /** La pagina porta in primo piano un'altra isola (la più vicina al centro della vista). */
  showIsland(id: string): void;
  /** «‹ Menu»: la finestra si chiude e si torna alla scheda. */
  back(): void;
}

export const GARDEN_CHANNEL = {
  getData: "garden:get-data",
  data: "garden:data",
  showIsland: "garden:show-island",
  back: "garden:back",
} as const;
