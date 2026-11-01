// La finestra del giardino (GardenController in GardenWindow.swift): una finestra vera, con la barra del titolo, grande come la scena del Mac
// (1000 × 600, più piccola su uno schermo stretto), che si crea alla prima richiesta e si distrugge alla chiusura. Il disegno lo fa la pagina;
// qui c'è il giardino e la fotografia che le si manda.

import { BrowserWindow, ipcMain, screen } from "electron";
import { join } from "node:path";
import type { Garden } from "../core/garden.ts";
import { GARDEN_ITEMS } from "../core/gardenCatalog.ts";
import { ISLANDS, isKnownIsland } from "../core/gardenGrid.ts";
import { hourOf, isSeason, shownSeason } from "../core/gardenSky.ts";
import type { Season } from "../core/gardenSky.ts";
import { PETS } from "../core/pets.ts";
import type { Profile } from "../core/profile.ts";
import { wallOf } from "../core/time.ts";
import { GARDEN_CHANNEL } from "../shared/gardenApi.ts";
import type { GardenData } from "../shared/gardenApi.ts";
import { SCHEME } from "./protocol.ts";

/** La scena, come sul Mac: tutto il disegno è in queste unità. */
export const GARDEN_SCENE = { width: 1000, height: 600 } as const;

export interface GardenDeps {
  appPath: string;
  garden: Garden;
  profile: Profile;
  /** L'ora e la stagione forzate (per provarle senza aspettare: `gardenHour`, `gardenSeason` in `impostazioni.json`). */
  forcedHour: () => number | null;
  forcedSeason: () => string | null;
  /** «‹ Menu»: si torna alla scheda. */
  onBack(): void;
}

export interface GardenController {
  show(): void;
  refreshTitle(): void;
  readonly window: BrowserWindow | null;
}

/** Quanto rimpicciolire il giardino perché ci stia nello schermo (1 = a grandezza piena), come `GardenController.scale` sul Mac. */
export function gardenScale(width: number, height: number): number {
  return Math.min(1, Math.max(Math.min((width - 40) / GARDEN_SCENE.width, (height - 90) / GARDEN_SCENE.height), 0.5));
}

export function createGardenController(deps: GardenDeps): GardenController {
  let window: BrowserWindow | null = null;
  const { garden, profile } = deps;

  const data = (): GardenData => {
    const now = Date.now();
    const forcedHour = deps.forcedHour();
    const forced = deps.forcedSeason();
    const season: Season = shownSeason(wallOf(now), isSeason(forced) ? forced : null);
    return {
      islands: ISLANDS.map((id, index) => {
        const open = profile.isCompanionUnlocked(id);
        return {
          id, size: garden.islandSizeOf(id), open, name: PETS.find((pet) => pet.id === id)?.name ?? id,
          placements: garden.placementsOn(id).map((p) => ({ ...p })),
          companion: open ? garden.companionTile(id, index) : null,
        };
      }),
      shown: garden.shownIsland, home: garden.homeIsland, bridges: [...garden.bridges],
      hour: forcedHour ?? hourOf(wallOf(now)), season, title: profile.gardenTitle,
      found: GARDEN_ITEMS.filter((x) => garden.isFound(x.id)).length, total: GARDEN_ITEMS.length,
      minutesToNextGift: garden.minutesToNextGift, nextGiftProgress: garden.nextGiftProgress,
    };
  };
  const push = (): void => {
    if (window && !window.isDestroyed()) window.webContents.send(GARDEN_CHANNEL.data, data());
  };
  garden.addObserver(push);
  profile.addObserver(push);

  /** Solo la nostra finestra può dare questi comandi. */
  const trusted = (event: Electron.IpcMainEvent | Electron.IpcMainInvokeEvent): boolean =>
    window !== null && !window.isDestroyed() && event.sender === window.webContents;

  ipcMain.handle(GARDEN_CHANNEL.getData, (event) => (trusted(event) ? data() : null));
  ipcMain.on(GARDEN_CHANNEL.showIsland, (event, id: unknown) => {
    if (trusted(event) && typeof id === "string" && isKnownIsland(id) && profile.isCompanionUnlocked(id)) garden.showIsland(id);
  });
  ipcMain.on(GARDEN_CHANNEL.back, (event) => {
    if (!trusted(event)) return;
    window?.close();
    deps.onBack();
  });

  return {
    get window() { return window; },
    refreshTitle() {
      if (window && !window.isDestroyed()) window.setTitle(profile.gardenTitle);
    },
    show() {
      // un angolo che c'era già prima di aprire la finestra si sblocca adesso
      garden.discoverCorners();
      if (window && !window.isDestroyed()) {
        push();
        window.setTitle(profile.gardenTitle);
        if (window.isMinimized()) window.restore();
        window.show();
        window.focus();
        return;
      }
      const area = screen.getPrimaryDisplay().workAreaSize;
      const scale = gardenScale(area.width, area.height);
      const created = new BrowserWindow({
        width: Math.round(GARDEN_SCENE.width * scale), height: Math.round(GARDEN_SCENE.height * scale), useContentSize: true,
        resizable: false, maximizable: false, fullscreenable: false,
        title: profile.gardenTitle, backgroundColor: "#9ebf8c", autoHideMenuBar: true, show: false,
        webPreferences: {
          preload: join(deps.appPath, "dist", "preload", "preload-garden.cjs"),
          contextIsolation: true, sandbox: true, nodeIntegration: false, backgroundThrottling: true,
        },
      });
      created.setMenuBarVisibility(false);
      created.once("ready-to-show", () => { created.show(); created.focus(); });
      created.on("closed", () => { if (window === created) window = null; });
      created.on("page-title-updated", (event) => event.preventDefault());
      window = created;
      void created.loadURL(`${SCHEME}://app/garden.html`);
    },
  };
}
