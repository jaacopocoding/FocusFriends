// La pagina del giardino: riceve la fotografia del giardino dal processo principale e la disegna (scene.ts) su un <canvas> grande quanto la
// finestra, con le misure della scena del Mac (1000 × 600). Ci si sposta trascinando e si ingrandisce con la rotellina (o due dita sul touchpad);
// «+», «−» e «0» come sul Mac, «M» per vedere tutte le isole.

import type { GardenApi, GardenData } from "../../shared/gardenApi.ts";
import { clampCamera, drawGarden, focusedIsland, islandCamera, SCENE_W, wantedImages, worldCamera, zoomCamera } from "./scene.ts";
import type { Camera, SceneLayers } from "./scene.ts";
import { sprite, whenSpritesLoad } from "./sprites.ts";

declare global {
  interface Window {
    focusfriendsGarden: GardenApi;
    /** Per le prove dal vivo: lo stato e la telecamera. */
    __garden?: unknown;
  }
}

const api = window.focusfriendsGarden;
const canvas = document.getElementById("scene") as HTMLCanvasElement;
const ctx = canvas.getContext("2d")!;

let data: GardenData | null = null;
let camera: Camera = { zoom: 1, panX: 0, panY: 0 };
let version = 0;
let frames = 0;
let scheduled = false;
const layers: SceneLayers = { still: null, stillKey: "" };

/** Quanti punti dello schermo per un punto della scena, e quanti pixel veri. */
const sceneScale = (): number => canvas.clientWidth / SCENE_W;
const pixelRatio = (): number => sceneScale() * window.devicePixelRatio;

function resize(): void {
  const width = Math.round(window.innerWidth * window.devicePixelRatio), height = Math.round(window.innerHeight * window.devicePixelRatio);
  if (canvas.width !== width || canvas.height !== height) {
    canvas.width = width;
    canvas.height = height;
    layers.still = null;
  }
  redraw();
}

function redraw(): void {
  if (scheduled) return;
  scheduled = true;
  requestAnimationFrame(() => {
    scheduled = false;
    if (!data) return;
    const dpr = pixelRatio();
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.imageSmoothingQuality = "high";
    drawGarden(ctx, layers, data, camera, dpr, version);
    frames += 1;
  });
}

whenSpritesLoad(() => {
  version += 1;
  redraw();
});

function resetCamera(): void {
  const shown = data?.islands.find((island) => island.id === data!.shown);
  if (shown) camera = islandCamera(shown);
  redraw();
}

function moveCamera(next: Camera): void {
  camera = clampCamera(next);
  if (data) {
    const focus = focusedIsland(data, camera);
    if (focus !== data.shown) {
      data = { ...data, shown: focus };
      api.showIsland(focus);
    }
  }
  redraw();
}

function receive(next: GardenData, reset: boolean): void {
  const first = data === null;
  data = next;
  document.title = next.title;
  for (const key of wantedImages(next)) void sprite(key);
  if (first || reset) resetCamera(); else redraw();
}

// ---- il mouse e la tastiera

/** Un punto della finestra nelle coordinate della scena. */
const scenePoint = (event: MouseEvent): { x: number; y: number } => ({ x: event.offsetX / sceneScale(), y: event.offsetY / sceneScale() });

let drag: { x: number; y: number } | null = null;
canvas.addEventListener("pointerdown", (event) => {
  if (event.button !== 0) return;
  drag = scenePoint(event);
  canvas.setPointerCapture(event.pointerId);
  canvas.classList.add("panning");
});
canvas.addEventListener("pointermove", (event) => {
  if (!drag) return;
  const p = scenePoint(event);
  moveCamera({ ...camera, panX: camera.panX + p.x - drag.x, panY: camera.panY + p.y - drag.y });
  drag = p;
});
const endDrag = (): void => { drag = null; canvas.classList.remove("panning"); };
canvas.addEventListener("pointerup", endDrag);
canvas.addEventListener("pointercancel", endDrag);
canvas.addEventListener("wheel", (event) => {
  event.preventDefault();
  // due dita sul touchpad arrivano con ctrl; la rotellina a scatti
  const factor = Math.exp(-event.deltaY * (event.ctrlKey ? 0.01 : 0.0015));
  moveCamera(zoomCamera(camera, factor, scenePoint(event)));
}, { passive: false });

window.addEventListener("keydown", (event) => {
  if (event.ctrlKey || event.metaKey || event.altKey) return;
  switch (event.key) {
    case "+": case "=": moveCamera(zoomCamera(camera, 1.3)); break;
    case "-": moveCamera(zoomCamera(camera, 1 / 1.3)); break;
    case "0": resetCamera(); break;
    case "m": case "M": {
      const all = worldCamera();
      const close = Math.abs(camera.zoom - all.zoom) < 0.02 && Math.abs(camera.panX - all.panX) < 3 && Math.abs(camera.panY - all.panY) < 3;
      if (close) resetCamera(); else moveCamera(all);
      break;
    }
    case "Escape": api.back(); break;
    default: return;
  }
  event.preventDefault();
});

window.addEventListener("resize", resize);

window.__garden = {
  get data() { return data; },
  get camera() { return camera; },
  get frames() { return frames; },
  setCamera(next: Camera) { moveCamera(next); },
  resetCamera,
  worldView() { moveCamera(worldCamera()); },
};

api.onData((next) => receive(next, false));
void api.getData().then((next) => { if (next) receive(next, true); });
resize();
