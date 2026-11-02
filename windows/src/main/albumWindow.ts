// La finestra dell'album (AlbumController in AlbumWindow.swift): grande come la vista del Mac (980 × 730, più piccola su uno schermo stretto),
// si crea alla prima richiesta e si distrugge alla chiusura. A ogni apertura il libro è chiuso. Il disegno lo fa la pagina.

import { BrowserWindow, ipcMain, screen } from "electron";
import { join } from "node:path";
import type { Garden } from "../core/garden.ts";
import { GARDEN_ITEMS } from "../core/gardenCatalog.ts";
import { ISLANDS } from "../core/gardenGrid.ts";
import { isSeason, shownSeason } from "../core/gardenSky.ts";
import { PETS } from "../core/pets.ts";
import type { Profile } from "../core/profile.ts";
import type { Settings } from "../core/settings.ts";
import { wallOf } from "../core/time.ts";
import { ALBUM_CHANNEL } from "../shared/albumApi.ts";
import type { AlbumData } from "../shared/albumApi.ts";
import { SCHEME } from "./protocol.ts";

export const ALBUM_SIZE = { width: 980, height: 730 } as const;

export interface AlbumDeps {
  appPath: string;
  garden: Garden;
  profile: Profile;
  settings: Settings;
  /** «‹ Menu»: si torna alla scheda. */
  onBack(): void;
}

export interface AlbumController {
  show(): void;
  refreshTitle(): void;
  readonly window: BrowserWindow | null;
}

export function createAlbumController(deps: AlbumDeps): AlbumController {
  const { garden, profile, settings } = deps;
  let window: BrowserWindow | null = null;
  let prepare = false;

  const data = (): AlbumData => {
    const counts: Record<string, number> = {};
    for (const p of garden.allPlacements) counts[p.item] = (counts[p.item] ?? 0) + 1;
    const forced = settings.gardenSeason;
    return {
      has: GARDEN_ITEMS.filter((x) => garden.has(x.id)).map((x) => x.id), unseen: [...garden.unseen], counts,
      islands: ISLANDS.map((id) => ({ id, name: PETS.find((pet) => pet.id === id)?.name ?? id, open: profile.isCompanionUnlocked(id) })),
      owner: profile.name, title: profile.albumTitle, season: shownSeason(wallOf(Date.now()), isSeason(forced) ? forced : null),
      spread: settings.albumSpread, ...(prepare ? { prepare: true } : {}),
    };
  };
  const push = (): void => {
    if (window && !window.isDestroyed()) window.webContents.send(ALBUM_CHANNEL.data, data());
  };
  garden.addObserver(push);
  profile.addObserver(push);

  const trusted = (event: Electron.IpcMainEvent | Electron.IpcMainInvokeEvent): boolean =>
    window !== null && !window.isDestroyed() && event.sender === window.webContents;

  ipcMain.handle(ALBUM_CHANNEL.getData, (event) => {
    if (!trusted(event)) return null;
    prepare = true;
    const made = data();
    prepare = false;
    return made;
  });
  ipcMain.on(ALBUM_CHANNEL.markSeen, (event) => { if (trusted(event)) garden.markSeen(); });
  ipcMain.on(ALBUM_CHANNEL.setSpread, (event, index: unknown) => {
    if (trusted(event) && Number.isInteger(index) && (index as number) >= 0 && (index as number) < 20) settings.albumSpread = index as number;
  });
  ipcMain.on(ALBUM_CHANNEL.back, (event) => {
    if (!trusted(event)) return;
    window?.close();
    deps.onBack();
  });

  return {
    get window() { return window; },
    refreshTitle() {
      if (window && !window.isDestroyed()) window.setTitle(profile.albumTitle);
    },
    show() {
      if (window && !window.isDestroyed()) {
        prepare = true;
        push();
        prepare = false;
        window.setTitle(profile.albumTitle);
        if (window.isMinimized()) window.restore();
        window.show();
        window.focus();
        return;
      }
      const area = screen.getPrimaryDisplay().workAreaSize;
      const scale = Math.min(1, Math.max(Math.min((area.width - 40) / ALBUM_SIZE.width, (area.height - 90) / ALBUM_SIZE.height), 0.5));
      const created = new BrowserWindow({
        width: Math.round(ALBUM_SIZE.width * scale), height: Math.round(ALBUM_SIZE.height * scale), useContentSize: true,
        resizable: false, maximizable: false, fullscreenable: false,
        title: profile.albumTitle, backgroundColor: "#9ebf8c", autoHideMenuBar: true, show: false,
        webPreferences: {
          preload: join(deps.appPath, "dist", "preload", "preload-album.cjs"),
          // disegna solo quando cambia qualcosa (e durante le animazioni): come il giardino, non rallenta in sottofondo
          contextIsolation: true, sandbox: true, nodeIntegration: false, backgroundThrottling: false,
        },
      });
      created.setMenuBarVisibility(false);
      created.once("ready-to-show", () => { created.show(); created.focus(); });
      created.on("closed", () => { if (window === created) window = null; });
      created.on("page-title-updated", (event) => event.preventDefault());
      window = created;
      void created.loadURL(`${SCHEME}://app/album.html`);
    },
  };
}
