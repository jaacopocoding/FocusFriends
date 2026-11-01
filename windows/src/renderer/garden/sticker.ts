// Le figurine dell'album (Sticker.swift): un cartoncino crema con il numero, il disegno e il nome. La rarità è la finitura del bordo (semplice,
// argento con un lucido, oro con un luccichio); una figurina che non hai ancora è una casella con il numero e la sagoma. Si disegna su un canvas,
// così la usano la figurina di fine focus (sulla pagina del compagno) e l'album.

import { rarityOf, RARITY_TITLES } from "../../core/gardenCatalog.ts";
import type { GardenItem } from "../../core/gardenCatalog.ts";
import { makeCanvas, ready } from "./sprites.ts";
import type { Sprite } from "./sprites.ts";

export interface StickerLook {
  item: GardenItem;
  number: number;
  found: boolean;
  isNew: boolean;
  /** Dove si può mettere, se la figurina lo dice (l'album sì, il regalo no). */
  placing: { everywhere: true } | { island: string; name: string } | null;
}

export const CARD = "rgb(255, 252, 240)";
export const SILVER = "rgb(148, 168, 196)";
export const GOLD = "rgb(219, 168, 46)";
const EDGE = "rgba(140, 102, 64, 0.45)";
const INK = "rgb(41, 26, 15)";
const INK_LIGHT = "rgb(102, 77, 51)";
const TRACK = "rgba(140, 102, 64, 0.13)";
const UI = 'system-ui, "Segoe UI", sans-serif';

export function rarityColor(item: GardenItem): string {
  const rarity = rarityOf(item);
  return rarity === "legendary" ? GOLD : rarity === "rare" ? SILVER : EDGE;
}

/** Il colore di un'isola (la stessa tinta del giardino), per il segno «solo …». */
function islandTint(island: string, alpha: number): string {
  const rgb: Record<string, [number, number, number]> = {
    pianty: [96, 200, 84], porcellino: [238, 150, 96], ciccio: [70, 170, 214], gattino: [112, 132, 204], riccio: [212, 124, 64],
  };
  const c = rgb[island] ?? [140, 102, 64];
  return `rgba(${c[0]}, ${c[1]}, ${c[2]}, ${alpha})`;
}

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, r);
}

function text(ctx: CanvasRenderingContext2D, value: string, x: number, y: number, width: number, font: string, color: string, align: CanvasTextAlign = "center"): void {
  ctx.font = font;
  ctx.fillStyle = color;
  ctx.textAlign = align;
  ctx.textBaseline = "top";
  let shown = value;
  while (shown.length > 1 && ctx.measureText(shown).width > width) shown = shown.slice(0, -2) + "…";
  ctx.fillText(shown, align === "center" ? x + width / 2 : align === "right" ? x + width : x, y);
}

const silhouettes = new Map<string, HTMLCanvasElement>();

/** La sagoma di un oggetto (il suo disegno tutto di un colore), per le figurine ancora da trovare. */
function silhouette(s: Sprite, key: string): HTMLCanvasElement {
  const known = silhouettes.get(key);
  if (known) return known;
  const made = makeCanvas(s.src.w, s.src.h);
  const ctx = made.getContext("2d")!;
  ctx.drawImage(s.image, s.src.x, s.src.y, s.src.w, s.src.h, 0, 0, s.src.w, s.src.h);
  ctx.globalCompositeOperation = "source-atop";
  ctx.fillStyle = "rgba(140, 102, 64, 0.55)";
  ctx.fillRect(0, 0, made.width, made.height);
  silhouettes.set(key, made);
  return made;
}

function star(ctx: CanvasRenderingContext2D, cx: number, cy: number, radius: number, color: string): void {
  ctx.beginPath();
  for (let i = 0; i < 8; i++) {
    const angle = i * Math.PI / 4 - Math.PI / 2, r = i % 2 === 0 ? radius : radius * 0.28;
    const x = cx + Math.cos(angle) * r, y = cy + Math.sin(angle) * r;
    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
  }
  ctx.closePath();
  ctx.fillStyle = color;
  ctx.fill();
}

/** Disegna la figurina nel rettangolo. `shine` (da 0 a 1) è dove sta la luce che passa; senza, ce n'è una ferma e leggera. */
export function drawSticker(ctx: CanvasRenderingContext2D, look: StickerLook, x: number, y: number, w: number, h: number, shine: number | null = null): void {
  const rarity = rarityOf(look.item);
  const radius = Math.min(w, h) * 0.11;
  const shape = (): void => roundRect(ctx, x + 0.75, y + 0.75, w - 1.5, h - 1.5, radius);
  ctx.save();
  if (look.found) {
    shape();
    ctx.fillStyle = CARD;
    ctx.fill();
    if (rarity === "legendary") { ctx.fillStyle = "rgba(255, 237, 179, 0.55)"; ctx.fill(); }
    if (rarity !== "common") {
      // una striscia di luce in diagonale
      ctx.save();
      shape();
      ctx.clip();
      const slant = h * 0.5, width = w * 0.28;
      const bx = x - slant - width + (w + slant * 2 + width * 2) * (shine ?? 0.22);
      ctx.beginPath();
      ctx.moveTo(bx + slant, y);
      ctx.lineTo(bx + width + slant, y);
      ctx.lineTo(bx + width, y + h);
      ctx.lineTo(bx, y + h);
      ctx.closePath();
      ctx.fillStyle = `rgba(255, 255, 255, ${shine === null ? 0.20 : 0.42})`;
      ctx.fill();
      ctx.restore();
    }
    shape();
    ctx.strokeStyle = rarityColor(look.item);
    ctx.lineWidth = rarity === "common" ? 1.2 : rarity === "rare" ? 2.2 : 3;
    ctx.stroke();
  } else {
    shape();
    ctx.fillStyle = TRACK;
    ctx.fill();
    ctx.setLineDash([4, 3]);
    ctx.strokeStyle = "rgba(140, 102, 64, 0.32)";
    ctx.lineWidth = 1.2;
    ctx.stroke();
    ctx.setLineDash([]);
  }

  // il numero, in alto a sinistra
  text(ctx, `n. ${String(look.number).padStart(2, "0")}`, x + 8, y + 6, 40, `600 9px ${UI}`, look.found ? INK_LIGHT : "rgba(102, 77, 51, 0.8)", "left");

  // il disegno (o la sagoma); se c'è il segno di dove si può mettere, ha una riga sotto il disegno
  const placingRow = 12;
  const marked = look.placing !== null;
  const box = { x: x + 8, y: y + 19, w: w - 16, h: h - 19 - 24 - (marked ? placingRow : 0) };
  const key = "giardino/" + look.item.id;
  const s = ready(key);
  if (s) {
    const scale = Math.min(box.w / Math.max(s.src.w, 1), box.h / Math.max(s.src.h, 1));
    const dw = s.src.w * scale, dh = s.src.h * scale;
    const tx = box.x + box.w / 2 - dw / 2, ty = box.y + box.h - dh;
    ctx.imageSmoothingQuality = "high";
    if (look.found) ctx.drawImage(s.image, s.src.x, s.src.y, s.src.w, s.src.h, tx, ty, dw, dh);
    else ctx.drawImage(silhouette(s, key), tx, ty, dw, dh);
  }

  // il nome, o la rarità se non ce l'hai
  if (look.found) {
    ctx.font = `600 10.5px ${UI}`;
    const font = ctx.measureText(look.item.name).width > w - 10 ? `600 9px ${UI}` : `600 10.5px ${UI}`;
    text(ctx, look.item.name, x + 4, y + h - 19, w - 8, font, INK);
  } else {
    const tint = rarity === "legendary" ? "rgb(158, 117, 20)" : rarity === "rare" ? "rgb(97, 117, 148)" : INK_LIGHT;
    text(ctx, RARITY_TITLES[rarity], x + 4, y + h - 19, w - 8, `600 10px ${UI}`, tint);
  }

  if (look.placing) {
    const row = { x: x + 6, y: y + h - 20 - placingRow - 1, w: w - 12, h: placingRow };
    const dim = look.found ? 1 : 0.75;
    if ("everywhere" in look.placing) {
      text(ctx, "universale", row.x, row.y + 1, row.w, `600 8.5px ${UI}`, `rgba(102, 77, 51, ${0.85 * dim})`);
    } else {
      const label = "solo " + look.placing.name;
      ctx.font = `600 8.5px ${UI}`;
      const pw = Math.min(Math.ceil(ctx.measureText(label).width) + 10, row.w), ph = row.h - 1;
      const px = row.x + row.w / 2 - pw / 2;
      roundRect(ctx, px, row.y, pw, ph, ph / 2);
      ctx.fillStyle = islandTint(look.placing.island, 0.30 * dim);
      ctx.fill();
      roundRect(ctx, px + 0.4, row.y + 0.4, pw - 0.8, ph - 0.8, ph / 2);
      ctx.strokeStyle = islandTint(look.placing.island, 0.85 * dim);
      ctx.lineWidth = 0.8;
      ctx.stroke();
      text(ctx, label, px, row.y + 1, pw, `600 8.5px ${UI}`, `rgba(41, 26, 15, ${dim})`);
    }
  }

  if (look.found) {
    if (rarity === "legendary") {
      star(ctx, x + w - 12, y + 12, 6, GOLD);
      star(ctx, x + 12, y + h - 31, 3.5, "rgba(219, 168, 46, 0.8)");
    }
    if (look.isNew) {
      ctx.font = `bold 9.5px ${UI}`;
      const width = Math.ceil(ctx.measureText("NUOVA").width) + 10;
      roundRect(ctx, x + w - width - 4, y + 4, width, 15, 4);
      ctx.fillStyle = "rgb(204, 64, 56)";
      ctx.fill();
      text(ctx, "NUOVA", x + w - width - 4, y + 7, width, `bold 9.5px ${UI}`, "white");
    }
  }
  ctx.restore();
}
