// Disegna il compagno su un canvas: la posa attuale appoggiata sul fondo, la piccola ombra a terra, lo specchio quando
// va a sinistra, la dissolvenza tra due stadi, gli «Zzz» e il disegno «sollevato» che trema. È il PetView di
// PetWindow.swift. Il canvas si sposta con una trasformazione (non si ridisegna per camminare).

import type { PetData, Size } from "../core/pets.ts";

/** Sotto questa opacità (su 255) un pixel non conta come disegno: per la cima del disegno e per i clic. */
const OPAQUE = 25;
const FADE_SECONDS = 0.8;
/** Spazio vuoto sotto i piedi del disegno, in punti. */
const BOTTOM_MARGIN = 3;
const FONT_FAMILY = '"Marker Felt", "MarkerFelt-Wide", "Kalam", "Segoe Print", cursive';

interface LoadedImage {
  bitmap: ImageBitmap;
  width: number;
  height: number;
  /** L'opacità di ogni pixel alla risoluzione dell'immagine. */
  alpha: Uint8Array;
  /** Frazione dell'altezza, dall'alto, in cui comincia il disegno visibile. */
  topFraction: number;
}

interface Rect { x: number; y: number; width: number; height: number }

async function loadImage(url: string): Promise<LoadedImage> {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`immagine non trovata: ${url}`);
  const bitmap = await createImageBitmap(await response.blob());
  const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
  const context = canvas.getContext("2d", { willReadFrequently: true })!;
  context.drawImage(bitmap, 0, 0);
  const pixels = context.getImageData(0, 0, bitmap.width, bitmap.height).data;
  const alpha = new Uint8Array(bitmap.width * bitmap.height);
  let top = -1;
  for (let i = 0; i < alpha.length; i += 1) {
    const a = pixels[i * 4 + 3]!;
    alpha[i] = a;
    if (top < 0 && a > OPAQUE) top = Math.floor(i / bitmap.width);
  }
  return { bitmap, width: bitmap.width, height: bitmap.height, alpha, topFraction: top < 0 ? 0 : top / bitmap.height };
}

export class PetView {
  readonly canvas: HTMLCanvasElement;
  private readonly context: CanvasRenderingContext2D;
  private images: LoadedImage[] = [];
  private growthBase = 0;
  private growthCount = 0;
  private pickedImage: LoadedImage | null = null;
  private stage = 0;
  private framesPerStage = 1;
  private pose = 0;
  private fadingFrom: number | null = null;
  private fadeStart = 0;
  private pickedUp = false;
  private pickedStart = 0;
  private sleepMarks = false;
  private sleepStart = 0;
  private mirrored = false;
  private dirty = true;
  private boxSize: Size;
  private left = 0;
  private top = 0;

  /** Chiamata appena cambia il disegno mostrato (stadio o posa): il fumetto si risistema. */
  onArtChanged: (() => void) | null = null;

  readonly pet: PetData;

  private constructor(pet: PetData) {
    this.pet = pet;
    this.canvas = document.createElement("canvas");
    this.context = this.canvas.getContext("2d")!;
    this.boxSize = { ...pet.size };
    this.framesPerStage = pet.framesPerStage ?? 1;
  }

  static async create(pet: PetData, urlOf: (path: string) => string): Promise<PetView> {
    const view = new PetView(pet);
    view.images = await Promise.all(pet.images.map((path) => loadImage(urlOf(path))));
    // Le immagini di crescita del focus stanno in coda: se ne manca una, niente crescita (mai indici sfasati).
    view.growthBase = view.images.length;
    try {
      const growth = await Promise.all(pet.focusGrowthImages.map((path) => loadImage(urlOf(path))));
      view.images.push(...growth);
      view.growthCount = growth.length;
    } catch {
      view.growthCount = 0;
    }
    if (pet.picked) view.pickedImage = await loadImage(urlOf(pet.picked.image));
    view.stage = Math.min(pet.restImageIndex, Math.max(view.images.length - 1, 0));
    view.pose = view.framesPerStage > 1 ? view.stage % view.framesPerStage : 0;
    return view;
  }

  // ---- posizione e misure

  get size(): Size { return this.boxSize; }
  get position(): { left: number; top: number } { return { left: this.left, top: this.top }; }

  setPosition(left: number, top: number): void {
    this.left = left;
    this.top = top;
    this.canvas.style.transform = `translate(${left}px, ${top}px)`;
  }

  /** Cambia la dimensione della scatola (il disegno «sollevato» è più grande): la posizione la decide chi chiama. */
  setBoxSize(size: Size): void {
    if (size.width === this.boxSize.width && size.height === this.boxSize.height) return;
    this.boxSize = { ...size };
    this.dirty = true;
  }

  /** Altezza dei piedi (la linea di terra del disegno) dal bordo basso della scatola. */
  get feetHeight(): number {
    const rect = this.imageRect(this.pet.size);
    return BOTTOM_MARGIN + this.pet.groundFraction * rect.height;
  }

  /** L'immagine di riferimento adattata allo spazio mantenendo le proporzioni, appoggiata in basso (coordinate con l'origine in alto). */
  private imageRect(box: Size): Rect {
    const reference = this.images[0];
    if (!reference) return { x: 0, y: 0, width: box.width, height: box.height };
    const availableHeight = box.height - BOTTOM_MARGIN;
    const scale = Math.min(box.width / reference.width, availableHeight / reference.height);
    const width = reference.width * scale, height = reference.height * scale;
    return { x: (box.width - width) / 2, y: box.height - BOTTOM_MARGIN - height, width, height };
  }

  /** Il rettangolo in cui si disegna l'immagine `index`. Le immagini di crescita hanno un'altra tela: alla stessa scala del personaggio e con i piedi sulla stessa linea di terra. */
  private drawRect(index: number): Rect {
    const main = this.imageRect(this.boxSize);
    const reference = this.images[0];
    const image = this.images[index];
    if (this.growthCount === 0 || index < this.growthBase || !image || !reference) return main;
    const scale = main.width / reference.width;
    const width = image.width * scale, height = image.height * scale;
    const groundY = main.y + main.height - this.pet.groundFraction * main.height;      // origine in alto
    return { x: this.boxSize.width / 2 - width / 2, y: groundY - (1 - this.pet.focusGrowthFeetFraction) * height, width, height };
  }

  // ---- stadio, posa, specchio, sonno, sollevamento

  get hasFocusGrowthImages(): boolean { return this.growthCount > 0; }

  setStage(next: number, animated: boolean, now = performance.now()): void {
    if (this.images.length === 0) return;
    const target = Math.min(Math.max(next, 0), this.images.length - 1);
    if (target === this.stage) return;
    if (animated) {
      this.fadingFrom = this.stage;
      this.fadeStart = now;
    } else {
      this.fadingFrom = null;
    }
    this.stage = target;
    this.pose = this.framesPerStage > 1 ? target % this.framesPerStage : 0;
    this.dirty = true;
    this.onArtChanged?.();
  }

  /** Cambia lo stadio di crescita (con dissolvenza) tenendo il fotogramma del passo. */
  setGrowth(growth: number, animated: boolean): void {
    if (this.framesPerStage <= 1) { this.setStage(growth, animated); return; }
    const clamped = Math.min(Math.max(growth, 0), Math.max(Math.trunc(this.pet.images.length / this.framesPerStage) - 1, 0));
    this.setStage(clamped * this.framesPerStage + this.pose, animated);
  }

  /** Cambia fotogramma (passo) dentro lo stadio attuale, senza interrompere una dissolvenza in corso. */
  setPose(next: number): void {
    if (this.framesPerStage <= 1) { this.setStage(next, false); return; }
    const clamped = Math.min(Math.max(next, 0), this.framesPerStage - 1);
    if (clamped === this.pose) return;
    this.pose = clamped;
    const base = Math.floor(this.stage / this.framesPerStage) * this.framesPerStage;
    this.stage = base + clamped;
    if (this.fadingFrom !== null) this.fadingFrom = Math.floor(this.fadingFrom / this.framesPerStage) * this.framesPerStage + clamped;
    this.dirty = true;
    this.onArtChanged?.();
  }

  setMirrored(mirrored: boolean): void {
    if (mirrored === this.mirrored) return;
    this.mirrored = mirrored;
    this.dirty = true;
  }

  get isMirrored(): boolean { return this.mirrored; }

  setSleepMarks(on: boolean, now = performance.now()): void {
    if (on === this.sleepMarks) return;
    this.sleepMarks = on;
    if (on) this.sleepStart = now;
    this.dirty = true;
  }

  get hasPickedImage(): boolean { return this.pickedImage !== null; }
  get isPickedUp(): boolean { return this.pickedUp; }

  /** Mostra o toglie il disegno «sollevato», che trema leggermente finché è in aria. */
  setPicked(picked: boolean, now = performance.now()): void {
    if (picked === this.pickedUp) return;
    this.pickedUp = picked;
    if (picked) this.pickedStart = now;
    this.dirty = true;
  }

  // ---- misure del disegno

  /** Altezza (dal bordo basso della scatola) a cui arriva il disegno di una certa immagine. */
  private artTopOf(index: number): number {
    const image = this.images[index];
    if (!image) return this.boxSize.height;
    const rect = this.drawRect(index);
    return this.boxSize.height - rect.y - image.topFraction * rect.height;
  }

  /** Altezza a cui arriva il disegno dello stadio attuale. */
  get artTop(): number {
    return this.pickedUp ? this.boxSize.height : this.artTopOf(this.stage);
  }

  /** Altezza a cui arriva tutto ciò che si vede ora: anche l'immagine che sta svanendo e gli «Zzz». */
  get visibleTop(): number {
    if (this.pickedUp) return this.boxSize.height;
    let top = this.artTopOf(this.stage);
    if (this.fadingFrom !== null) top = Math.max(top, this.artTopOf(this.fadingFrom));
    if (this.sleepMarks) top += 32;
    return top;
  }

  /** Il punto (nelle coordinate della scatola, origine in alto a sinistra) è sopra un pixel del disegno? */
  hitTest(x: number, y: number): boolean {
    const box = this.boxSize;
    if (x < 0 || y < 0 || x >= box.width || y >= box.height) return false;
    const sx = this.mirrored && !this.pickedUp ? box.width - x : x;
    if (this.pickedUp && this.pickedImage) return this.opaqueAt(this.pickedImage, this.pickedRect(this.pickedImage), sx, y);
    const indexes = this.fadingFrom !== null ? [this.stage, this.fadingFrom] : [this.stage];
    return indexes.some((index) => {
      const image = this.images[index];
      return image !== undefined && this.opaqueAt(image, this.drawRect(index), sx, y);
    });
  }

  private opaqueAt(image: LoadedImage, rect: Rect, x: number, y: number): boolean {
    const px = Math.floor(((x - rect.x) / rect.width) * image.width);
    const py = Math.floor(((y - rect.y) / rect.height) * image.height);
    if (px < 0 || py < 0 || px >= image.width || py >= image.height) return false;
    return image.alpha[py * image.width + px]! > OPAQUE;
  }

  // ---- disegno

  /** Serve ridisegnare? (qualcosa è cambiato, o c'è un'animazione in corso) */
  needsRender(now: number): boolean {
    return this.dirty || this.pickedUp || this.sleepMarks || (this.fadingFrom !== null && (now - this.fadeStart) / 1000 < FADE_SECONDS + 0.05);
  }

  render(now: number): void {
    const { width, height } = this.boxSize;
    const ratio = window.devicePixelRatio || 1;
    const pixelWidth = Math.round(width * ratio), pixelHeight = Math.round(height * ratio);
    if (this.canvas.width !== pixelWidth || this.canvas.height !== pixelHeight) {
      this.canvas.width = pixelWidth;
      this.canvas.height = pixelHeight;
    }
    this.canvas.style.width = `${width}px`;
    this.canvas.style.height = `${height}px`;
    const context = this.context;
    context.setTransform(ratio, 0, 0, ratio, 0, 0);
    context.clearRect(0, 0, width, height);
    this.dirty = false;

    if (this.sleepMarks) this.drawSleepMarks(now);
    if (this.pickedUp && this.pickedImage) {
      this.drawPicked(this.pickedImage, now);
      return;
    }
    if (this.images.length === 0) return;

    context.save();
    // Specchio: tutto il disegno viene ribaltato attorno al centro.
    if (this.mirrored) {
      context.translate(width, 0);
      context.scale(-1, 1);
    }
    // Ombra centrata sulla linea di terra del disegno.
    const main = this.imageRect(this.boxSize);
    const shadowWidth = width * this.pet.shadowWidthFraction;
    const groundY = main.y + main.height - this.pet.groundFraction * main.height;
    context.fillStyle = "rgba(0, 0, 0, 0.16)";
    context.beginPath();
    context.ellipse(width / 2, groundY, shadowWidth / 2, 3.5, 0, 0, Math.PI * 2);
    context.fill();

    const draw = (index: number, alpha: number): void => {
      const image = this.images[index];
      if (!image) return;
      const rect = this.drawRect(index);
      context.globalAlpha = alpha;
      context.drawImage(image.bitmap, rect.x, rect.y, rect.width, rect.height);
    };
    if (this.fadingFrom !== null && this.fadingFrom < this.images.length) {
      const t = Math.min(1, (now - this.fadeStart) / 1000 / FADE_SECONDS);
      draw(this.fadingFrom, 1);
      draw(this.stage, t);
      if (t >= 1) this.fadingFrom = null;
    } else {
      draw(this.stage, 1);
    }
    context.restore();
  }

  /** Il disegno «sollevato», con un leggero tremolio attorno al punto in cui lo tiene il cursore. */
  private pickedRect(image: LoadedImage): Rect {
    const { width, height } = this.boxSize;
    const scale = Math.min(width / image.width, height / image.height);
    const w = image.width * scale, h = image.height * scale;
    return { x: (width - w) / 2, y: (height - h) / 2, width: w, height: h };
  }

  private drawPicked(image: LoadedImage, now: number): void {
    const { width, height } = this.boxSize;
    const grab = this.pet.picked?.grab ?? { x: 0.5, y: 0.5 };
    const rect = this.pickedRect(image);
    const seconds = (now - this.pickedStart) / 1000;
    const angle = (Math.sin(seconds * 2 * Math.PI * 5) * 2.5 * Math.PI) / 180;       // 5 oscillazioni al secondo, ±2,5°
    const pivotX = width * grab.x, pivotY = height * (1 - grab.y);
    const context = this.context;
    context.save();
    context.translate(pivotX, pivotY);
    context.rotate(angle);
    context.translate(-pivotX, -pivotY);
    context.drawImage(image.bitmap, rect.x, rect.y, rect.width, rect.height);
    context.restore();
  }

  /** Tre lettere «z» che salgono una dopo l'altra sopra la testa e svaniscono. */
  private drawSleepMarks(now: number): void {
    const seconds = (now - this.sleepStart) / 1000;
    const { width, height } = this.boxSize;
    const headX = width * (this.mirrored ? 0.2 : 0.8);        // la testa sta a destra (a sinistra se specchiato)
    const baseY = this.artTop + 2;                             // dal bordo basso
    const direction = this.mirrored ? -1 : 1;
    const letters = [{ text: "z", size: 9, dx: 0 }, { text: "Z", size: 12, dx: 7 }, { text: "z", size: 9, dx: 14 }];
    const context = this.context;
    letters.forEach((letter, i) => {
      const phase = (seconds - i * 0.7) % 2.8;
      if (phase < 0) return;
      const p = phase / 2.8;
      context.globalAlpha = Math.sin(p * Math.PI);
      context.fillStyle = "rgb(92, 77, 61)";
      context.font = `bold ${letter.size}px ${FONT_FAMILY}`;
      context.textBaseline = "alphabetic";
      context.fillText(letter.text, headX + direction * letter.dx, height - (baseY + p * 14));
    });
    context.globalAlpha = 1;
  }
}
