// Il palco della pagina «Avatar» (AvatarStage.swift): i compagni in fila, quello scelto grande al centro e i vicini più piccoli ai lati.
// Si scorre trascinando, con due dita sul touchpad (o la rotella in orizzontale), toccando un vicino o con le frecce della pagina.
// Chi non è sbloccato è una sagoma nera e sfocata: si capisce che c'è qualcuno, ma non chi.

import type { PetData } from "../../core/pets.ts";

export interface StageSlot {
  pet: PetData;
  unlocked: boolean;
}

/** Quanto distano i centri di due compagni vicini, e quanto è grande lo spazio di una figura (il vicino è più piccolo). */
const SPACING = 104;
const BOX = { width: 150, height: 176 };
/** Quanto sfocare la sagoma, in frazione del lato più lungo della figura: abbastanza da perdere orecchie, becco e zampe, non da sparire. */
const BLUR = 0.065;
/** L'altezza massima, in pixel, con cui si lavora la sagoma. */
const SILHOUETTE_HEIGHT = 300;

interface Figure {
  /** La figura ritagliata sul disegno (i piedi toccano il bordo di sotto). */
  image: HTMLCanvasElement;
  /** La sagoma nera e sfocata, più grande della figura: `padX`/`padY` dicono di quanto, in frazione della figura. */
  silhouette: HTMLCanvasElement;
  padX: number;
  padY: number;
}

const figures = new Map<string, Promise<Figure | null>>();
const ready = new Map<string, Figure>();

/** La figura e la sagoma di un compagno, ricavate dall'immagine con cui sta fermo e tenute in memoria. */
function loadFigure(pet: PetData, urlOf: (path: string) => string): Promise<Figure | null> {
  const known = figures.get(pet.id);
  if (known) return known;
  const promise = new Promise<Figure | null>((resolve) => {
    const image = new Image();
    image.onload = () => {
      const figure = makeFigure(image);
      if (figure) ready.set(pet.id, figure);
      resolve(figure);
    };
    image.onerror = () => resolve(null);
    image.src = urlOf(pet.iconImage);
  });
  figures.set(pet.id, promise);
  return promise;
}

function makeFigure(image: HTMLImageElement): Figure | null {
  const w = image.naturalWidth, h = image.naturalHeight;
  if (w === 0 || h === 0) return null;
  const full = document.createElement("canvas");
  full.width = w;
  full.height = h;
  const fullContext = full.getContext("2d", { willReadFrequently: true });
  if (!fullContext) return null;
  fullContext.drawImage(image, 0, 0);
  // senza i margini trasparenti
  const pixels = fullContext.getImageData(0, 0, w, h).data;
  let minX = w, maxX = -1, minY = h, maxY = -1;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (pixels[(y * w + x) * 4 + 3]! > 20) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < minX || maxY < minY) return null;
  const tw = maxX - minX + 1, th = maxY - minY + 1;
  const trimmed = document.createElement("canvas");
  trimmed.width = tw;
  trimmed.height = th;
  trimmed.getContext("2d")?.drawImage(full, minX, minY, tw, th, 0, 0, tw, th);

  // la sagoma: nera (si tiene solo la trasparenza del disegno) e sfocata, su una tela più grande perché il bordo sfumato esce un po'
  const scale = Math.min(1, SILHOUETTE_HEIGHT / th);
  const sw = tw * scale, sh = th * scale;
  const sigma = Math.max(sw, sh) * BLUR;
  const pad = Math.ceil(sigma * 3);
  const silhouette = document.createElement("canvas");
  silhouette.width = Math.ceil(sw + 2 * pad);
  silhouette.height = Math.ceil(sh + 2 * pad);
  const shade = silhouette.getContext("2d");
  if (!shade) return null;
  shade.filter = `brightness(0) blur(${sigma}px)`;
  shade.drawImage(trimmed, pad, pad, sw, sh);
  return { image: trimmed, silhouette, padX: pad / sw, padY: pad / sh };
}

export class AvatarStage {
  readonly element: HTMLCanvasElement;
  private slots: StageSlot[] = [];
  /** Il compagno al centro. */
  private current = 0;
  /** Il punto in cui si trova la fila, in compagni (con la virgola mentre scorre): da 0 all'ultimo. */
  private position = 0;
  private frame = 0;
  private lastTick = 0;
  private drag: { x: number; position: number; index: number; moved: boolean; pointer: number } | null = null;
  private wheelSum = 0;
  private wheelUsed = false;
  private wheelTimer: number | undefined;
  /** Cambia quando si arriva su un altro compagno. */
  onChange: ((index: number) => void) | null = null;

  private readonly urlOf: (path: string) => string;
  private readonly width: number;
  private readonly height: number;

  constructor(urlOf: (path: string) => string, width: number, height: number) {
    this.urlOf = urlOf;
    this.width = width;
    this.height = height;
    const canvas = document.createElement("canvas");
    canvas.className = "avatar-stage";
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;
    canvas.setAttribute("aria-hidden", "true");
    this.element = canvas;
    canvas.addEventListener("pointerdown", (event) => this.pointerDown(event));
    canvas.addEventListener("pointermove", (event) => this.pointerMove(event));
    canvas.addEventListener("pointerup", (event) => this.pointerUp(event));
    canvas.addEventListener("pointercancel", () => { this.drag = null; this.go(Math.round(this.position)); });
    canvas.addEventListener("wheel", (event) => this.wheel(event), { passive: false });
  }

  get index(): number { return this.current; }

  /** Mette i compagni sul palco; `index` dice chi sta al centro (se è un altro da quello di adesso, la fila scorre). */
  configure(slots: StageSlot[], index: number): void {
    const first = this.slots.length === 0;
    this.slots = slots;
    const target = Math.max(0, Math.min(index, slots.length - 1));
    for (const slot of slots) void loadFigure(slot.pet, this.urlOf).then(() => this.draw());
    if (first) {
      this.current = target;
      this.position = target;
      this.draw();
    } else if (target !== this.current) {
      this.go(target, false);
    } else {
      this.draw();
    }
  }

  private get reduceMotion(): boolean {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  }

  go(requested: number, notify = true): void {
    const target = Math.max(0, Math.min(requested, this.slots.length - 1));
    const changed = target !== this.current;
    this.current = target;
    if (this.reduceMotion) {
      this.position = target;
      this.draw();
    } else {
      this.startTicker();
    }
    if (changed && notify) this.onChange?.(target);
  }

  private startTicker(): void {
    if (this.frame !== 0) return;
    this.lastTick = performance.now();
    const tick = (now: number): void => {
      // lo stesso passo del Mac (22% della strada ogni sessantesimo di secondo), qualunque sia la frequenza dello schermo
      const steps = Math.min((now - this.lastTick) / (1000 / 60), 4);
      this.lastTick = now;
      const gap = this.current - this.position;
      if (Math.abs(gap) < 0.003) {
        this.position = this.current;
        this.frame = 0;
      } else {
        this.position += gap * (1 - Math.pow(1 - 0.22, steps));
        this.frame = requestAnimationFrame(tick);
      }
      this.draw();
    };
    this.frame = requestAnimationFrame(tick);
  }

  private stopTicker(): void {
    if (this.frame !== 0) cancelAnimationFrame(this.frame);
    this.frame = 0;
  }

  // ---- gesti

  private pointerDown(event: PointerEvent): void {
    if (event.button !== 0) return;
    try { this.element.setPointerCapture(event.pointerId); } catch { /* un puntatore che non c'è più: si trascina lo stesso finché resta sopra */ }
    this.drag = { x: event.offsetX, position: this.position, index: this.current, moved: false, pointer: event.pointerId };
    this.stopTicker();
  }

  private pointerMove(event: PointerEvent): void {
    const drag = this.drag;
    if (!drag || drag.pointer !== event.pointerId) return;
    const dx = event.offsetX - drag.x;
    if (Math.abs(dx) > 3) drag.moved = true;
    if (!drag.moved) return;
    this.position = Math.max(-0.25, Math.min(drag.position - dx / SPACING, this.slots.length - 1 + 0.25));
    this.draw();
  }

  private pointerUp(event: PointerEvent): void {
    const drag = this.drag;
    if (!drag || drag.pointer !== event.pointerId) return;
    this.drag = null;
    const x = event.offsetX;
    if (drag.moved) {
      // un trascinamento deciso va al vicino; uno piccolo torna dov'era (o va al più vicino)
      const dx = x - drag.x;
      this.go(Math.abs(dx) > 36 ? drag.index + (dx < 0 ? 1 : -1) : Math.round(this.position));
    } else if (x - this.width / 2 < -50) {
      this.go(this.current - 1);
    } else if (x - this.width / 2 > 50) {
      this.go(this.current + 1);
    } else {
      this.go(this.current);
    }
  }

  /** Due dita sul touchpad (o la rotella in orizzontale): un passo per gesto. Lo scorrimento in verticale resta alla scheda. */
  private wheel(event: WheelEvent): void {
    if (Math.abs(event.deltaX) <= Math.abs(event.deltaY)) return;
    event.preventDefault();
    window.clearTimeout(this.wheelTimer);
    this.wheelTimer = window.setTimeout(() => { this.wheelSum = 0; this.wheelUsed = false; }, 180);
    if (this.wheelUsed) return;
    this.wheelSum += event.deltaMode === WheelEvent.DOM_DELTA_PIXEL ? event.deltaX : event.deltaX * 40;
    if (Math.abs(this.wheelSum) > 30) {
      this.wheelUsed = true;
      this.go(this.current + (this.wheelSum > 0 ? 1 : -1));
    }
  }

  // ---- disegno

  draw(): void {
    const canvas = this.element;
    const ratio = window.devicePixelRatio || 1;
    const pixelWidth = Math.round(this.width * ratio), pixelHeight = Math.round(this.height * ratio);
    if (canvas.width !== pixelWidth || canvas.height !== pixelHeight) { canvas.width = pixelWidth; canvas.height = pixelHeight; }
    const ctx = canvas.getContext("2d");
    if (!ctx || this.slots.length === 0) return;
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    ctx.clearRect(0, 0, this.width, this.height);
    ctx.imageSmoothingQuality = "high";
    const ground = this.height - 22;
    // dal più lontano al più vicino, così quello al centro sta sopra
    const order = this.slots.map((_, i) => i).sort((a, b) => Math.abs(b - this.position) - Math.abs(a - this.position));
    for (const i of order) {
      const d = i - this.position;
      const distance = Math.abs(d);
      if (distance >= 2) continue;
      const scale = 1 - 0.4 * Math.min(distance, 1);
      const alpha = distance <= 1 ? 1 - 0.15 * distance : Math.max(0, 2 - distance) * 0.85;
      const centerX = this.width / 2 + d * SPACING;
      ctx.globalAlpha = 1;
      ctx.fillStyle = `rgba(41, 26, 15, ${0.16 * alpha})`;
      ctx.beginPath();
      ctx.ellipse(centerX, ground, 56 * scale, 7 * scale, 0, 0, Math.PI * 2);
      ctx.fill();
      const w = BOX.width * scale, h = BOX.height * scale;
      this.drawFigure(ctx, this.slots[i]!, { x: centerX - w / 2, y: ground - h, width: w, height: h }, alpha);
    }
    ctx.globalAlpha = 1;
  }

  /** La figura nel suo spazio, coi piedi sul fondo. */
  private drawFigure(ctx: CanvasRenderingContext2D, slot: StageSlot, box: { x: number; y: number; width: number; height: number }, alpha: number): void {
    const figure = ready.get(slot.pet.id);
    if (!figure) return;
    const fit = Math.min(box.width / figure.image.width, box.height / figure.image.height);
    const w = figure.image.width * fit, h = figure.image.height * fit;
    const x = box.x + box.width / 2 - w / 2, y = box.y + box.height - h;
    if (slot.unlocked) {
      ctx.globalAlpha = alpha;
      ctx.drawImage(figure.image, x, y, w, h);
    } else {
      ctx.globalAlpha = alpha * 0.92;
      ctx.drawImage(figure.silhouette, x - w * figure.padX, y - h * figure.padY, w * (1 + 2 * figure.padX), h * (1 + 2 * figure.padY));
    }
  }
}
