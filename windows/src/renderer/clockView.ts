// Il mini orologio digitale sotto il compagno: cassa nera, cifre a sette segmenti inclinate e schermo di carta color crema,
// la stessa del fumetto (TimerView in TimerBubble.swift). Si apre dall'alto come una tendina.

import type { Size } from "../core/pets.ts";

export const CLOCK_SIZE: Size = { width: 132, height: 76 };
const DURATION_MS = 350;
const FONT_FAMILY = '"Marker Felt", "MarkerFelt-Wide", "Kalam", "Segoe Print", cursive';
const DIGIT_COLOR = "rgb(33, 31, 26)";
const SHADOW_COLOR = "rgba(89, 71, 38, 0.28)";

// Segmenti accesi per ogni cifra: a=alto, b=alto dx, c=basso dx, d=basso, e=basso sx, f=alto sx, g=centro.
const SEGMENTS: Record<string, string> = {
  "0": "abcdef", "1": "bc", "2": "abdeg", "3": "abcdg", "4": "bcfg", "5": "acdfg", "6": "acdefg", "7": "abc", "8": "abcdefg", "9": "abcdfg",
};

type Point = [number, number];

export class ClockView {
  readonly canvas: HTMLCanvasElement;
  private readonly context: CanvasRenderingContext2D;
  private readonly paper: ImageBitmap | null;
  private label = "FOCUS";
  private time = "00:00";
  /** Quanto è «aperta» la tendina: 0 = chiusa, 1 = tutto l'orologio. */
  private reveal = 0;
  private animation: { from: number; to: number; start: number; opening: boolean } | null = null;
  private dirty = true;
  private shown = false;

  constructor(paper: ImageBitmap | null) {
    this.paper = paper;
    this.canvas = document.createElement("canvas");
    this.canvas.style.visibility = "hidden";
    this.context = this.canvas.getContext("2d")!;
  }

  get isShown(): boolean { return this.shown; }

  setPosition(left: number, top: number): void {
    this.canvas.style.transform = `translate(${Math.round(left * 4) / 4}px, ${Math.round(top * 4) / 4}px)`;
  }

  setText(label: string, time: string): void {
    if (label === this.label && time === this.time) return;
    this.label = label;
    this.time = time;
    this.dirty = true;
  }

  /** Apre (o chiude) la tendina: aprendo decelera, chiudendo accelera. */
  setShown(shown: boolean, now: number): void {
    if (shown === this.shown) return;
    this.shown = shown;
    this.animation = { from: this.reveal, to: shown ? 1 : 0, start: now, opening: shown };
    if (shown) this.canvas.style.visibility = "visible";
    this.dirty = true;
  }

  /** Subito aperta o chiusa, senza animazione (per quando il compagno viene sollevato o rimesso giù). */
  snap(shown: boolean): void {
    this.shown = shown;
    this.reveal = shown ? 1 : 0;
    this.animation = null;
    this.canvas.style.visibility = shown ? "visible" : "hidden";
    this.dirty = true;
  }

  needsRender(): boolean { return this.dirty || this.animation !== null; }

  render(now: number): void {
    if (this.animation) {
      const p = Math.min((now - this.animation.start) / DURATION_MS, 1);
      const eased = this.animation.opening ? 1 - Math.pow(1 - p, 3) : Math.pow(p, 3);
      this.reveal = this.animation.from + (this.animation.to - this.animation.from) * eased;
      if (p >= 1) {
        this.animation = null;
        if (!this.shown) this.canvas.style.visibility = "hidden";
      }
    }
    this.dirty = false;
    const { width, height } = CLOCK_SIZE;
    const ratio = window.devicePixelRatio || 1;
    const pixelWidth = Math.round(width * ratio), pixelHeight = Math.round(height * ratio);
    if (this.canvas.width !== pixelWidth || this.canvas.height !== pixelHeight) {
      this.canvas.width = pixelWidth;
      this.canvas.height = pixelHeight;
      this.canvas.style.width = `${width}px`;
      this.canvas.style.height = `${height}px`;
    }
    const c = this.context;
    c.setTransform(1, 0, 0, 1, 0, 0);
    c.clearRect(0, 0, this.canvas.width, this.canvas.height);
    const shownHeight = height * Math.min(Math.max(this.reveal, 0), 1);
    if (shownHeight <= 0.5) return;
    // Il disegno è fatto con l'origine in basso (come sul Mac): si ribalta, poi si ribaltano i testi.
    c.setTransform(ratio, 0, 0, -ratio, 0, height * ratio);
    c.save();
    c.beginPath();
    c.rect(0, height - shownHeight, width, shownHeight);
    c.clip();
    this.drawCase();
    const screen = { x: 11, y: 10, width: width - 22, height: height - 25 };
    this.drawScreen(screen);
    this.drawLabel(screen);
    this.drawTime(screen);
    c.restore();
  }

  // ---- cassa e schermo

  private roundedRect(x: number, y: number, w: number, h: number, r: number): void {
    const c = this.context;
    c.beginPath();
    c.moveTo(x + r, y);
    c.arcTo(x + w, y, x + w, y + h, r);
    c.arcTo(x + w, y + h, x, y + h, r);
    c.arcTo(x, y + h, x, y, r);
    c.arcTo(x, y, x + w, y, r);
    c.closePath();
  }

  private drawCase(): void {
    const c = this.context;
    const { width, height } = CLOCK_SIZE;
    const body = c.createLinearGradient(0, height, 0, 0);
    body.addColorStop(0, "rgb(77, 77, 77)");
    body.addColorStop(1, "rgb(18, 18, 18)");
    this.roundedRect(1, 1, width - 2, height - 2, 10);
    c.fillStyle = body;
    c.fill();
    // Piastra superiore, un po' più chiara, come il coperchio dell'orologio.
    this.roundedRect(5, height - 13, width - 10, 9, 4);
    c.fillStyle = "rgb(51, 51, 51)";
    c.fill();
    c.strokeStyle = "rgba(107, 107, 107, 0.6)";
    c.lineWidth = 0.8;
    c.stroke();
    this.roundedRect(1, 1, width - 2, height - 2, 10);
    c.strokeStyle = "rgba(0, 0, 0, 0.8)";
    c.lineWidth = 1.2;
    c.stroke();
  }

  private drawScreen(screen: { x: number; y: number; width: number; height: number }): void {
    const c = this.context;
    c.save();
    this.roundedRect(screen.x, screen.y, screen.width, screen.height, 4);
    c.clip();
    if (this.paper) {
      // Un pezzo pulito della carta del fumetto (nell'immagine, dall'alto: x 230, y 200, 250 × 100).
      c.save();
      c.translate(0, screen.y * 2 + screen.height);
      c.scale(1, -1);
      c.drawImage(this.paper, 230, 200, 250, 100, screen.x, screen.y, screen.width, screen.height);
      c.restore();
    } else {
      c.fillStyle = "rgb(245, 230, 189)";
      c.fillRect(screen.x, screen.y, screen.width, screen.height);
    }
    // Un velo d'ombra in alto: lo schermo sembra incassato nella cassa.
    const veil = c.createLinearGradient(0, screen.y + screen.height, 0, screen.y + screen.height - 9);
    veil.addColorStop(0, "rgba(0, 0, 0, 0.28)");
    veil.addColorStop(1, "rgba(0, 0, 0, 0)");
    c.fillStyle = veil;
    c.fillRect(screen.x, screen.y + screen.height - 9, screen.width, 9);
    c.restore();
    this.roundedRect(screen.x, screen.y, screen.width, screen.height, 4);
    c.strokeStyle = "rgba(0, 0, 0, 0.9)";
    c.lineWidth = 1;
    c.stroke();
  }

  private drawLabel(screen: { x: number; y: number; width: number; height: number }): void {
    const c = this.context;
    c.save();
    c.translate(screen.x + 6, screen.y + screen.height - 12);
    c.scale(1, -1);
    c.font = `8.5px ${FONT_FAMILY}`;
    c.fillStyle = "rgba(33, 31, 26, 0.8)";
    c.textBaseline = "alphabetic";
    c.fillText(this.label, 0, 8);
    c.restore();
  }

  // ---- cifre

  private drawTime(screen: { x: number; y: number; width: number; height: number }): void {
    const digitWidth = 17, digitHeight = 25, thickness = 3.6, colonWidth = 7, gap = 3, shear = 0.16;
    const chars = Array.from(this.time);
    const total = chars.reduce((sum, ch) => sum + (ch === ":" ? colonWidth : digitWidth), 0) + gap * (chars.length - 1);
    // Le cifre sono inclinate: si sposta un po' a sinistra per ricentrare l'insieme.
    let x = screen.x + screen.width / 2 - total / 2 - (digitHeight * shear) / 2 + 1;
    const y = screen.y + 5;
    for (const ch of chars) {
      if (ch === ":") {
        this.drawColon(x, y, colonWidth, digitHeight, thickness, shear);
        x += colonWidth + gap;
      } else {
        this.drawDigit(ch, x, y, digitWidth, digitHeight, thickness, shear);
        x += digitWidth + gap;
      }
    }
  }

  private paint(points: Point[], baseY: number, shear: number): void {
    const c = this.context;
    const path = (dx: number, dy: number): void => {
      c.beginPath();
      points.forEach(([px, py], i) => {
        const qx = px + (py - baseY) * shear + dx, qy = py + dy;
        if (i === 0) c.moveTo(qx, qy); else c.lineTo(qx, qy);
      });
      c.closePath();
    };
    // Ombra leggera spostata in basso a destra, poi la cifra.
    path(1.1, -1.1);
    c.fillStyle = SHADOW_COLOR;
    c.fill();
    path(0, 0);
    c.fillStyle = DIGIT_COLOR;
    c.fill();
  }

  private drawDigit(ch: string, ox: number, oy: number, w: number, h: number, t: number, shear: number): void {
    const on = SEGMENTS[ch];
    if (on === undefined) return;
    const g = 0.5;     // piccolo vuoto fra un segmento e l'altro
    const top = oy + h - t / 2, mid = oy + h / 2, bottom = oy + t / 2;
    const left = ox + t / 2, right = ox + w - t / 2;
    const horizontal = (yc: number): Point[] => {
      const x0 = ox + g, x1 = ox + w - g;
      return [[x0, yc], [x0 + t / 2, yc + t / 2], [x1 - t / 2, yc + t / 2], [x1, yc], [x1 - t / 2, yc - t / 2], [x0 + t / 2, yc - t / 2]];
    };
    const vertical = (xc: number, y0: number, y1: number): Point[] => [
      [xc, y0 + g], [xc + t / 2, y0 + g + t / 2], [xc + t / 2, y1 - g - t / 2], [xc, y1 - g], [xc - t / 2, y1 - g - t / 2], [xc - t / 2, y0 + g + t / 2],
    ];
    const shapes: Record<string, Point[]> = {
      a: horizontal(top), b: vertical(right, mid, oy + h), c: vertical(right, oy, mid), d: horizontal(bottom),
      e: vertical(left, oy, mid), f: vertical(left, mid, oy + h), g: horizontal(mid),
    };
    for (const key of on) {
      const points = shapes[key];
      if (points) this.paint(points, oy, shear);
    }
  }

  private drawColon(ox: number, oy: number, w: number, h: number, t: number, shear: number): void {
    const size = t * 0.95;
    const cx = ox + w / 2;
    for (const yc of [oy + h * 0.30, oy + h * 0.70]) {
      this.paint([[cx - size / 2, yc - size / 2], [cx + size / 2, yc - size / 2], [cx + size / 2, yc + size / 2], [cx - size / 2, yc + size / 2]], oy, shear);
    }
  }
}
