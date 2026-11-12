// La figurina trovata a fine focus (GiftCard.swift): compare accanto al compagno, si gira e resta qualche secondo, con la luce che passa se è
// rara o leggendaria. Non cattura i clic. Segue il compagno se si muove.

import { itemNumber, itemWithId, rarityOf } from "../core/gardenCatalog.ts";
import type { GardenDrop } from "../core/gardenDrops.ts";
import { drawSticker, rarityColor } from "./garden/sticker.ts";
import { sprite } from "./garden/sprites.ts";
import { GIFT_HEIGHT as HEIGHT, GIFT_WIDTH as WIDTH, giftPosition } from "../core/giftPlacement.ts";

const DURATION = 6.5;

export interface GiftCardHost {
  container: HTMLElement;
  petBox(): { left: number; top: number; width: number; height: number };
  /** Dove stanno i piedi del compagno (in punti della pagina). */
  feetY(): number;
  scene(): { width: number; height: number };
  /** Quello che la figurina non deve coprire (la scheda «Com'è andata?», che compare insieme a lei), se c'è. */
  avoid?(): { left: number; top: number; width: number; height: number } | null;
}

export class GiftCard {
  private readonly host: GiftCardHost;
  private canvas: HTMLCanvasElement | null = null;
  private frame = 0;

  constructor(host: GiftCardHost) {
    this.host = host;
  }

  /** Dove sta adesso (per non metterci sopra il fumetto), se c'è. */
  get box(): { left: number; top: number; width: number; height: number } | null {
    return this.canvas ? { ...this.position(), width: WIDTH, height: HEIGHT } : null;
  }

  async show(drop: GardenDrop): Promise<void> {
    this.hide();
    const item = itemWithId(drop.item);
    if (!item) return;
    await sprite("giardino/" + item.id);
    const canvas = document.createElement("canvas");
    canvas.className = "gift-card";
    const dpr = window.devicePixelRatio;
    canvas.width = WIDTH * dpr;
    canvas.height = HEIGHT * dpr;
    canvas.style.width = `${WIDTH}px`;
    canvas.style.height = `${HEIGHT}px`;
    this.host.container.append(canvas);
    this.canvas = canvas;
    const ctx = canvas.getContext("2d")!;
    const look = { item, number: itemNumber(item.id) ?? 0, found: true, isNew: true, placing: null };
    const rarity = rarityOf(item);
    const start = performance.now();
    const tick = (): void => {
      if (this.canvas !== canvas) return;
      const elapsed = (performance.now() - start) / 1000;
      if (elapsed >= DURATION) { this.hide(); return; }
      // compare con una girata (0,45 s), resta, e sparisce nell'ultimo mezzo secondo
      const appear = Math.min(elapsed / 0.45, 1);
      const turn = 1 - Math.pow(1 - appear, 3);
      const shine = (elapsed % 1.8) / 1.8;
      const fade = Math.min((DURATION - elapsed) / 0.5, 1);
      canvas.style.opacity = String(Math.min(appear * 2, 1) * Math.max(fade, 0));
      const p = this.position();
      canvas.style.left = `${p.left}px`;
      canvas.style.top = `${p.top}px`;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, WIDTH, HEIGHT);
      // una girata: la figurina si allarga dal centro (e un filo più in grande a metà, come un rimbalzo)
      const pop = 1 + 0.08 * Math.sin(turn * Math.PI);
      ctx.translate(WIDTH / 2, HEIGHT / 2);
      ctx.scale(Math.max(turn, 0.02) * pop, pop);
      ctx.translate(-WIDTH / 2, -HEIGHT / 2);
      const card = { x: 8, y: 8, w: WIDTH - 16, h: HEIGHT - 16 };
      // l'alone: oro per il leggendario, argento per il raro
      if (rarity !== "common") {
        ctx.save();
        ctx.globalAlpha = rarity === "legendary" ? 0.34 : 0.22;
        ctx.fillStyle = rarityColor(item);
        ctx.beginPath();
        ctx.roundRect(card.x - 5, card.y - 5, card.w + 10, card.h + 10, 16);
        ctx.fill();
        ctx.restore();
      }
      drawSticker(ctx, look, card.x, card.y, card.w, card.h, rarity !== "common" ? shine : null);
      this.frame = requestAnimationFrame(tick);
    };
    tick();
  }

  hide(): void {
    cancelAnimationFrame(this.frame);
    this.canvas?.remove();
    this.canvas = null;
  }

  private position(): { left: number; top: number } {
    return giftPosition(this.host.petBox(), this.host.feetY(), this.host.scene(), this.host.avoid?.() ?? null);
  }
}
