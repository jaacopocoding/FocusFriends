// Gli oggetti del giardino, le dimensioni dei compagni sull'isola e le pagine dell'album: come GardenCatalog.swift, voce per voce.
// Il numero di una figurina è la sua posizione nel catalogo (i nuovi oggetti si aggiungono in fondo). Niente `node:*`: lo usano anche le pagine.

export type GardenCategory = "flowers" | "companions" | "furniture";
export const GARDEN_CATEGORIES: readonly GardenCategory[] = ["flowers", "companions", "furniture"];
export const CATEGORY_TITLES: Readonly<Record<GardenCategory, string>> = { flowers: "Fiori", companions: "Per i compagni", furniture: "Arredi" };

export type GardenRarity = "common" | "rare" | "legendary";
export const RARITIES: readonly GardenRarity[] = ["common", "rare", "legendary"];
export const RARITY_TITLES: Readonly<Record<GardenRarity, string>> = { common: "Comune", rare: "Raro", legendary: "Leggendario" };
export function rarityRank(rarity: GardenRarity): number { return RARITIES.indexOf(rarity); }

/** Quante tessere occupa un oggetto (larghezza lungo `col`, profondità lungo `row`). */
export interface GardenFootprint { cols: number; rows: number }

/** Girato di un quarto, larghezza e profondità si scambiano. */
export function applyTurn(footprint: GardenFootprint, turned: boolean): GardenFootprint {
  return turned ? { cols: footprint.rows, rows: footprint.cols } : footprint;
}

/** La luce che fa un oggetto la sera: un alone caldo attorno a un punto del disegno e una pozza di luce sul prato. */
export interface GardenGlow {
  red: number; green: number; blue: number;
  /** Quanto è largo l'alone, in larghezze di tessera (la pozza sul prato è un quinto più larga). */
  radius: number;
  /** Dove sta la luce nel disegno: da 0 in cima a 1 ai piedi. */
  top: number;
  /** Quanto è forte (1 = come il lampione). */
  strength: number;
  /** Vibra piano come una fiamma. */
  flickers: boolean;
}

export const LAMP_GLOW: GardenGlow = { red: 255, green: 196, blue: 104, radius: 1.25, top: 0.10, strength: 1, flickers: false };

export interface GardenItem {
  id: string;
  name: string;
  category: GardenCategory;
  /** Quanto è alto, nelle unità del disegno: sull'isola `height × larghezza di una tessera ÷ 115` (0 per quelli che stanno sul lato). */
  height: number;
  /** Il vecchio prezzo: 0 = c'è fin dall'inizio; decide la rarità. */
  price: number;
  castsShadow: boolean;
  footprint: GardenFootprint;
  /** Una cosa piatta che sta sul lato della tessera (la staccionata, le bandierine, l'amaca, l'arco di rose). */
  axial: boolean;
  /** Quanto si inclina il disegno adagiato sul lato. */
  slope: number;
  /** Si unisce alle uguali che ha accanto (la staccionata, `GardenLinks`). */
  joins: boolean;
  glow: GardenGlow | null;
  /** Ha un disegno «acceso» (`<id>-acceso`) che si vede quando fa buio. */
  litDrawing: boolean;
  /** L'isola dell'animale a cui appartiene; null = universale. */
  island: string | null;
}

interface ItemOptions {
  shadow?: boolean; cols?: number; rows?: number; axial?: boolean; slope?: number; joins?: boolean;
  glow?: GardenGlow; litDrawing?: boolean; island?: string;
}

function item(id: string, name: string, category: GardenCategory, height: number, price: number, options: ItemOptions = {}): GardenItem {
  return {
    id, name, category, height, price, castsShadow: options.shadow ?? true,
    footprint: { cols: options.cols ?? 1, rows: options.rows ?? 1 }, axial: options.axial ?? false, slope: options.slope ?? 0.5,
    joins: options.joins ?? false, glow: options.glow ?? null, litDrawing: options.litDrawing ?? false, island: options.island ?? null,
  };
}

const glow = (red: number, green: number, blue: number, radius: number, top: number, strength: number, flickers = false): GardenGlow =>
  ({ red, green, blue, radius, top, strength, flickers });

/** Tutti gli oggetti, nell'ordine dell'album. */
export const GARDEN_ITEMS: readonly GardenItem[] = [
  // Fiori
  item("margherite", "Margherite", "flowers", 90, 0),
  item("trifoglio", "Trifoglio", "flowers", 45, 0),
  item("mughetti", "Mughetti", "flowers", 110, 0),
  item("tulipani", "Tulipani", "flowers", 100, 2),
  item("funghi", "Funghi", "flowers", 70, 2),
  item("lavanda", "Lavanda", "flowers", 105, 3),
  item("papaveri", "Papaveri", "flowers", 120, 3),
  item("felci", "Felci", "flowers", 110, 3),
  item("girasole", "Girasole", "flowers", 170, 4),
  item("rosaio", "Rosaio", "flowers", 130, 8),
  // Case e cose per i compagni
  item("cesto-carote", "Cesto di carote", "companions", 55, 2, { island: "porcellino" }),
  item("annaffiatoio", "Annaffiatoio", "companions", 50, 2, { island: "pianty" }),
  item("cesto-cuscino", "Cesto con cuscino", "companions", 60, 3, { island: "gattino" }),
  item("tunnel", "Tunnel con fieno", "companions", 55, 3, { island: "porcellino" }),
  item("altalena-uccelli", "Altalena uccelli", "companions", 85, 3, { island: "ciccio" }),
  item("bagnetto", "Bagnetto uccelli", "companions", 75, 4, { island: "ciccio" }),
  item("aiuola", "Aiuola rialzata", "companions", 75, 4, { island: "pianty" }),
  item("tiragraffi", "Tiragraffi", "companions", 115, 5, { island: "gattino" }),
  item("casetta-uccelli", "Casa per uccelli", "companions", 95, 5, { island: "ciccio" }),
  item("casetta-gatto", "Casa del gatto", "companions", 115, 6, { island: "gattino" }),
  item("casetta-porcellino", "Casa porcellino", "companions", 88, 6, { island: "porcellino" }),
  // Arredi
  item("picnic", "Tappeto da picnic", "furniture", 70, 4, { shadow: false }),
  item("bandierine", "Bandierine", "furniture", 0, 4, { shadow: false, axial: true }),
  item("cancelletto", "Cancelletto", "furniture", 0, 4, { shadow: false, axial: true, joins: true }),
  item("tavolino", "Tavolino da tè", "furniture", 95, 5),
  item("sdraio", "Sdraio", "furniture", 110, 5),
  item("carillon", "Carillon a vento", "furniture", 120, 5),
  item("panchina", "Panchina", "furniture", 95, 6),
  item("lampione", "Lampione", "furniture", 170, 6, { glow: LAMP_GLOW }),
  item("ponticello", "Ponticello", "furniture", 82, 8),
  item("amaca", "Amaca", "furniture", 0, 9, { shadow: false, cols: 2, axial: true, slope: 0.3 }),
  item("altalena", "Altalena", "furniture", 0, 10, { shadow: false, axial: true }),
  item("arco-rose", "Arco di rose", "furniture", 0, 12, { shadow: false, cols: 2, axial: true, slope: 0.3 }),
  // Le luci (il lampione è fra gli arredi, più su)
  item("alberello-lucine", "Alberello di lucine", "furniture", 135, 5, { glow: glow(255, 230, 160, 0.85, 0.40, 0.8) }),
  item("lanterna-ceppo", "Lanterna sul ceppo", "furniture", 105, 4, { glow: glow(255, 190, 100, 0.8, 0.32, 0.85) }),
  item("braciere", "Braciere", "furniture", 80, 7, { shadow: false, glow: glow(255, 150, 70, 1.15, 0.35, 1, true), litDrawing: true }),
  // Una luce per ogni animale, sulla sua isola
  item("barattolo-lucciole", "Barattolo di lucciole", "companions", 78, 4, { glow: glow(232, 244, 150, 0.7, 0.45, 0.7), island: "pianty" }),
  item("lanterna-voliera", "Lanterna per la voliera", "companions", 105, 5, { glow: glow(255, 200, 110, 0.8, 0.45, 0.85), island: "ciccio" }),
  item("lampada-fienile", "Lampada da fienile", "companions", 96, 4, { glow: glow(255, 175, 85, 0.85, 0.36, 0.85), island: "porcellino" }),
  item("candela-cesto", "Candela nel cesto", "companions", 62, 3, { glow: glow(255, 205, 130, 0.65, 0.22, 0.8), island: "gattino" }),
  // Le cose del Riccio, sulla sua isola (la zucca è la sua luce)
  item("mucchio-foglie", "Mucchio di foglie", "companions", 55, 2, { island: "riccio" }),
  item("cassetta-mele", "Cassetta di mele", "companions", 58, 3, { island: "riccio" }),
  item("tronco-cavo", "Tronco cavo", "companions", 62, 4, { island: "riccio" }),
  item("zucca-lanterna", "Zucca con candela", "companions", 74, 4, { glow: glow(255, 156, 64, 0.7, 0.5, 0.85), island: "riccio" }),
  item("hotel-insetti", "Hotel degli insetti", "companions", 112, 5, { island: "riccio" }),
  item("carriola-ghiande", "Carriola di ghiande", "companions", 78, 5, { island: "riccio" }),
  item("tana-foglie", "Tana di foglie", "companions", 90, 6, { island: "riccio" }),
];

const byId = new Map(GARDEN_ITEMS.map((x, index) => [x.id, { item: x, number: index + 1 }]));

/** Gli oggetti tolti dal catalogo: chi li aveva li perde (`Garden` li toglie leggendo il file). */
export const RETIRED_ITEMS: ReadonlySet<string> = new Set(["erba-alta", "erbe", "vaso-grande"]);

const COMPANION_HEIGHTS: Readonly<Record<string, number>> = { pianty: 120, porcellino: 60, ciccio: 105, gattino: 92, riccio: 66 };

/** Quanto è alto un compagno sull'isola (unità della scena): chi non c'è è 100. */
export function companionHeight(petId: string): number { return COMPANION_HEIGHTS[petId] ?? 100; }

export function itemWithId(id: string): GardenItem | undefined { return byId.get(id)?.item; }

/** Il numero della figurina nell'album (da 1). */
export function itemNumber(id: string): number | undefined { return byId.get(id)?.number; }

export const universalItems = (): GardenItem[] => GARDEN_ITEMS.filter((x) => x.island === null);
export const itemsForIsland = (island: string): GardenItem[] => GARDEN_ITEMS.filter((x) => x.island === island);
export const itemsInCategory = (category: GardenCategory): GardenItem[] => GARDEN_ITEMS.filter((x) => x.category === category);

/** Il regalo di benvenuto di un'isola: il primo oggetto dell'animale che non si ha ancora, o null. */
export function welcomeGift(island: string, has: (id: string) => boolean): string | null {
  return itemsForIsland(island).find((x) => !has(x.id))?.id ?? null;
}

/** Può stare su questa isola? Gli universali ovunque, quelli di un animale solo sulla sua. */
export function fitsIsland(x: GardenItem, island: string): boolean { return x.island === null || x.island === island; }

/** C'è fin dall'inizio (la «dotazione»). */
export function isStarter(x: GardenItem): boolean { return x.price === 0; }

/** La rarità, dal vecchio prezzo: fino a 3 comune, fino a 6 raro, oltre leggendario. */
export function rarityOf(x: GardenItem): GardenRarity {
  if (x.price <= 3) return "common";
  if (x.price <= 6) return "rare";
  return "legendary";
}

const FEMININE = ["casa", "lanterna", "lampada", "candela", "cassetta", "zucca", "carriola", "tana"];

/** Il nome con l'articolo, per le frasi: «il cesto di carote», «la casa del gatto», «l'annaffiatoio». */
export function nameWithArticle(x: GardenItem): string {
  const lower = x.name.slice(0, 1).toLowerCase() + x.name.slice(1);
  const first = lower.slice(0, 1);
  if ((first !== "" && "aeiou".includes(first)) || lower.startsWith("hotel ")) return "l'" + lower;
  return (FEMININE.some((word) => lower.startsWith(word + " ")) ? "la " : "il ") + lower;
}

/** Dove si può mettere, a parole (per l'album). */
export function islandRule(x: GardenItem, ownerName: string): string {
  return x.island === null ? "universale" : `solo sull'isola di ${ownerName}`;
}

/** «La casa del gatto sta solo sull'isola di Gattino.» */
export function wrongIslandLine(x: GardenItem, ownerName: string): string {
  const phrase = nameWithArticle(x);
  return phrase.slice(0, 1).toUpperCase() + phrase.slice(1) + ` sta solo sull'isola di ${ownerName}.`;
}

/** Quanti lati di tessera è lunga una cosa sul lato. */
export function sides(x: GardenItem): number { return Math.max(x.footprint.cols, x.footprint.rows); }

export const AXIAL_SUFFIX = "@asse";

/** Il nome dell'immagine di fronte (`assets/giardino/<id>.png`): quella dell'album e della cassetta. */
export function itemImage(x: GardenItem): string { return x.id; }
/** Il disegno da acceso, se c'è. */
export function litImage(x: GardenItem): string | null { return x.litDrawing ? x.id + "-acceso" : null; }
/** Il disegno con cui sta sull'isola (per le cose sul lato quello adagiato sull'asse: `amaca@asse2`). */
export function gardenImage(x: GardenItem): string { return x.axial ? x.id + AXIAL_SUFFIX + (sides(x) > 1 ? String(sides(x)) : "") : x.id; }
/** Il disegno di un pezzo che si unisce ai vicini, con i suoi bracci (`cancelletto@asse#10`). */
export function joinedImage(x: GardenItem, arms: number): string { return gardenImage(x) + "#" + String(arms); }

/** Quanto ondeggia col vento (0 = fermo). */
export function swayStrength(x: GardenItem): number {
  if (x.id === "funghi") return 0;
  if (x.id === "bandierine" || x.id === "carillon") return 1.8;
  return x.category === "flowers" ? 1 : 0;
}

/** Dove sta l'acqua nel disegno (centro e mezze misure, in frazioni del disegno). */
export function waterSpot(x: GardenItem): { u: number; v: number; halfWidth: number; halfHeight: number } | null {
  return x.id === "bagnetto" ? { u: 0.50, v: 0.255, halfWidth: 0.30, halfHeight: 0.07 } : null;
}

// ---- l'album: sei figurine per pagina, ogni sezione comincia su una pagina di sinistra

export interface AlbumPage {
  category: GardenCategory;
  items: GardenItem[];
  /** Quale pagina della sezione (da 1) e quante sono. */
  index: number;
  count: number;
}

export interface AlbumSpread { left: AlbumPage; right: AlbumPage | null }

export const ALBUM_PER_PAGE = 6;

export function albumSpreads(catalog: readonly GardenItem[] = GARDEN_ITEMS): AlbumSpread[] {
  const result: AlbumSpread[] = [];
  for (const category of GARDEN_CATEGORIES) {
    const items = catalog.filter((x) => x.category === category);
    if (items.length === 0) continue;
    const chunks: GardenItem[][] = [];
    for (let start = 0; start < items.length; start += ALBUM_PER_PAGE) chunks.push(items.slice(start, start + ALBUM_PER_PAGE));
    const pages = chunks.map((chunk, index): AlbumPage => ({ category, items: chunk, index: index + 1, count: chunks.length }));
    for (let start = 0; start < pages.length; start += 2) result.push({ left: pages[start]!, right: pages[start + 1] ?? null });
  }
  return result;
}

/** Quante doppie pagine sono complete: ognuna allarga l'isola. */
export function completedSpreads(isFound: (id: string) => boolean, catalog: readonly GardenItem[] = GARDEN_ITEMS): number {
  return albumSpreads(catalog).filter((spread) => {
    const items = [...spread.left.items, ...(spread.right?.items ?? [])];
    return items.length > 0 && items.every((x) => isFound(x.id));
  }).length;
}
