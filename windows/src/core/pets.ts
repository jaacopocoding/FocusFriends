// I compagni. I dati (immagini, misure, fotogrammi, frasi di riserva…) stanno in `data/pets.json`, generato dall'app per
// Mac (tools/genera-pets.sh) a partire da Pet.swift: così non possono differire. Qui ci sono i tipi e le regole che da
// quei dati ricavano gli stadi di crescita.

import data from "../../data/pets.json" with { type: "json" };

export interface Size { width: number; height: number }
export interface Rect { x: number; y: number; width: number; height: number }

export interface PetData {
  id: string;
  name: string;
  /** I file in assets/ (per esempio «ciccio/frame3.png»), nell'ordine delle pose. Per chi cresce: prima tutti i fotogrammi del primo stadio, poi quelli del secondo… */
  images: string[];
  /** La dimensione, in punti. */
  size: Size;
  quotesFile: string;
  /** Se non c'è nessuna frase (file mancante o vuoto) dice questa. */
  fallbackQuote: string;
  greeting: string;
  /** Ombra a terra: larghezza come frazione di quella della finestra. */
  shadowWidthFraction: number;
  /** Altezza della linea di terra nell'immagine, come frazione dell'altezza (0 = bordo inferiore). */
  groundFraction: number;
  /** La porzione dell'ultima immagine da usare come icona (coordinate 0…1, origine in basso). */
  iconCrop: Rect | null;
  /** Dove sta il «volto» nell'immagine dell'avatar, come frazione della larghezza. */
  iconFocus: number;
  /** Se cammina per lo schermo: le immagini sono pose (0 = fermo, poi i passi) e non stadi di crescita. */
  walks: boolean;
  walkFrames: number[];
  stepInterval: number;
  talkFrame: number | null;
  /** Le immagini guardano a destra: quando va a sinistra vengono specchiate. */
  facesRight: boolean;
  eatFrames: number[];
  sleepIntroFrame: number | null;
  sleepFrames: number[];
  popcornFrames: number[];
  popcornInterval: number;
  /** Le immagini che prendono il posto del personaggio durante un focus, dal primo all'ultimo stadio. */
  focusGrowthImages: string[];
  focusGrowthFeetFraction: number;
  eatsWhenFocusCompletes: boolean;
  /** Il disegno mostrato mentre lo si solleva col mouse. */
  picked: { image: string; size: Size; grab: { x: number; y: number } } | null;
  /** Per chi cammina e cresce insieme (Pianty): quanti fotogrammi ha ogni stadio. */
  framesPerStage: number | null;
  // Valori che l'app per Mac ricava dagli altri: la prova di contratto controlla che qui si ricavino uguali.
  stageCount: number;
  finalStage: number;
  restStage: number;
  restImageIndex: number;
  growsWithTimer: boolean;
  iconImage: string;
  stages: number[];
  focusGrowthStages: number[];
}

export const PETS: readonly PetData[] = (data as { pets: PetData[] }).pets;
export const PET_IDS: readonly string[] = PETS.map((pet) => pet.id);

/** Pianty è il personaggio di partenza. */
export const DEFAULT_PET = "pianty";

export function petInfo(id: string): PetData {
  return PETS.find((pet) => pet.id === id) ?? PETS[0]!;
}

// ---- stadi di crescita (le stesse regole di Pet.swift)

export function stageCount(pet: PetData): number {
  return pet.framesPerStage !== null ? Math.trunc(pet.images.length / pet.framesPerStage) : pet.walks ? 1 : pet.images.length;
}

export function finalStage(pet: PetData): number {
  return stageCount(pet) - 1;
}

/** Lo stadio con cui sta fermo: l'ultimo per chi cresce, la posa «fermo» per chi cammina. */
export function restStage(pet: PetData): number {
  return pet.walks ? 0 : finalStage(pet);
}

/** L'immagine con cui sta fermo, contando anche chi cresce e cammina (ultimo stadio, fotogramma fermo). */
export function restImageIndex(pet: PetData): number {
  return pet.framesPerStage !== null ? finalStage(pet) * pet.framesPerStage : restStage(pet);
}

export function growsWithTimer(pet: PetData): boolean {
  return stageCount(pet) > 1;
}

/** Lo stadio da mostrare durante un focus, dato quanta parte del tempo è trascorsa (0…1): quote uguali, l'ultimo a 4/5 del tempo. */
export function stageForProgress(pet: PetData, progress: number): number {
  if (!growsWithTimer(pet)) return 0;
  const p = Math.min(Math.max(progress, 0), 0.999_999);
  return Math.min(Math.trunc(p * stageCount(pet)), finalStage(pet));
}

/** Lo stadio delle immagini di crescita, dato quanta parte del focus è passata (0…1). */
export function focusGrowthStage(pet: PetData, progress: number): number {
  const n = pet.focusGrowthImages.length;
  if (n === 0) return 0;
  return Math.min(Math.trunc(Math.min(Math.max(progress, 0), 0.999_999) * n), n - 1);
}

/** L'immagine da cui si ricava l'icona. */
export function iconImage(pet: PetData): string {
  const index = pet.framesPerStage !== null ? restImageIndex(pet) : pet.walks ? 0 : finalStage(pet);
  return pet.images[index]!;
}
