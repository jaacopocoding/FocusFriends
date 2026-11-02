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
  /** A quanti focus pieni si sblocca. */
  need: number;
}

/** L'arrivo di un compagno appena sbloccato: i ponti da costruire e le isole da accogliere (con il regalo di benvenuto). */
export interface GardenArrival { bridges: string[]; welcomed: string[] }
export interface GardenWelcome { island: string; item: string; placement: string | null }

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
  /** L'ora è forzata (`gardenHour`): non avanza da sola. */
  hourForced: boolean;
  /** Oggi, «AAAA-MM-GG» (per gli ospiti). */
  day: string;
  /** Gli angoli appena sbloccati (le stelline con «Hai sbloccato…»): ci sono una volta sola. */
  newCorners: string[];
  season: Season;
  /** Il titolo della finestra («Il giardino di Marco»). */
  title: string;
  /** Quante figurine si sono trovate e quante sono in tutto. */
  found: number;
  total: number;
  /** Quanti minuti di studio mancano alla prossima figurina (null se non c'è più niente da trovare) e quanta strada si è fatta. */
  minutesToNextGift: number | null;
  nextGiftProgress: number | null;
  /** Gli oggetti trovati (quelli che stanno nella cassetta, se ci stanno sull'isola). */
  has: string[];
  /** La serie di giorni di studio, e se è ghiacciata. */
  streakDays: number;
  streakFrozen: boolean;
  /** Quanti focus pieni di studio ci sono (per «si sblocca a 50 focus: ne hai 32»). */
  focuses: number;
  /** La finestra si è appena riaperta: si torna all'isola intera. */
  reset?: boolean;
  /** Con la riapertura: la cerimonia d'arrivo da fare (mai durante un focus). */
  arrival?: GardenArrival;
}

/** Un comando dalla pagina: mettere, spostare, girare, togliere una copia, spostare un compagno. Risponde se è riuscito. */
export type GardenCommand =
  | { name: "place"; item: string; col: number; row: number; turned: boolean; island: string }
  | { name: "placeSomewhere"; item: string; island: string }
  | { name: "move"; id: string; col: number; row: number; turned: boolean; island: string }
  | { name: "rotate"; id: string }
  | { name: "remove"; id: string }
  | { name: "companion"; pet: string; col: number; row: number };

export interface GardenApi {
  getData(): Promise<GardenData>;
  /** Il giardino è cambiato (una figurina nuova, un compagno sbloccato…): i dati nuovi. */
  onData(callback: (data: GardenData) => void): void;
  /** La pagina porta in primo piano un'altra isola (la più vicina al centro della vista). */
  showIsland(id: string): void;
  /** «‹ Menu»: la finestra si chiude e si torna alla scheda. */
  back(): void;
  command(command: GardenCommand): Promise<boolean>;
  /** Una frase del compagno toccato. */
  phrase(petId: string): Promise<string>;
  /** Il tasto destro su una copia: il menu «Gira» / «Togli dal giardino». */
  contextMenu(id: string): void;
  /** Una riga da mostrare in basso (per esempio «Girata non ci sta»), dal menu del tasto destro. */
  onMessage(callback: (text: string) => void): void;
  /** La cerimonia è finita: i ponti si salvano costruiti e le isole accolte; risponde con i regali di benvenuto. */
  finishArrival(arrival: GardenArrival): Promise<GardenWelcome[]>;
  /** Il pulsante «Album». */
  showAlbum(): void;
  /** Saluti l'ospite (`id` è la specie, `reason` cosa l'ha attirato): la prima volta lascia un regalo (il suo nome), le altre conta la visita. */
  greetGuest(id: string, reason: string): Promise<{ isFirst: boolean; gift: string | null }>;
}

export const GARDEN_CHANNEL = {
  getData: "garden:get-data",
  data: "garden:data",
  showIsland: "garden:show-island",
  back: "garden:back",
  command: "garden:command",
  phrase: "garden:phrase",
  contextMenu: "garden:context-menu",
  message: "garden:message",
  finishArrival: "garden:finish-arrival",
  showAlbum: "garden:show-album",
  greetGuest: "garden:greet-guest",
} as const;
