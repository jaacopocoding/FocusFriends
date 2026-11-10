// La finestra del giardino (GardenController in GardenWindow.swift): una finestra vera, con la barra del titolo, grande come la scena del Mac
// (1000 × 600, più piccola su uno schermo stretto), che si crea alla prima richiesta e si distrugge alla chiusura. Il disegno lo fa la pagina;
// qui c'è il giardino e la fotografia che le si manda.

import { BrowserWindow, ipcMain, Menu, screen } from "electron";
import { join } from "node:path";
import type { Garden } from "../core/garden.ts";
import { GARDEN_ITEMS, itemWithId } from "../core/gardenCatalog.ts";
import { bridgeId, ISLANDS, isKnownIsland } from "../core/gardenGrid.ts";
import { hourOf, isSeason, shownSeason } from "../core/gardenSky.ts";
import type { Season } from "../core/gardenSky.ts";
import { PET_IDS, PETS } from "../core/pets.ts";
import { need } from "../core/rewards.ts";
import type { Profile } from "../core/profile.ts";
import { dayString, wallOf } from "../core/time.ts";
import { visitorWithId } from "../core/gardenVisitors.ts";
import { GARDEN_CHANNEL } from "../shared/gardenApi.ts";
import type { GardenArrival, GardenCommand, GardenData } from "../shared/gardenApi.ts";
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
  /** La serie di giorni di studio di adesso. */
  streak: () => { days: number; isFrozen: boolean };
  /** Una frase del compagno (dal suo file, come sul desktop). */
  phrase: (petId: string) => string;
  /** Quanti focus pieni ci sono. */
  focuses: () => number;
  /** Si può fare la cerimonia d'arrivo? (Non durante un focus: aspetta la prossima entrata.) */
  canCelebrate: () => boolean;
  /** Il pulsante «Album» del giardino. */
  showAlbum: () => void;
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

  let reset = false;
  let arrival: GardenArrival | null = null;
  const openIslands = (): Set<string> => new Set(ISLANDS.filter((id) => profile.isCompanionUnlocked(id)));
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
          need: need(id, profile.firstCompanion, PET_IDS),
        };
      }),
      shown: garden.shownIsland, home: garden.homeIsland, bridges: [...garden.bridges],
      hour: forcedHour ?? hourOf(wallOf(now)), hourForced: forcedHour !== null, day: dayString(wallOf(now)), newCorners: garden.takeNewCorners(),
      season, title: profile.gardenTitle,
      found: GARDEN_ITEMS.filter((x) => garden.isFound(x.id)).length, total: GARDEN_ITEMS.length,
      minutesToNextGift: garden.minutesToNextGift, nextGiftProgress: garden.nextGiftProgress,
      has: GARDEN_ITEMS.filter((x) => garden.has(x.id)).map((x) => x.id),
      streakDays: deps.streak().days, streakFrozen: deps.streak().isFrozen,
      focuses: deps.focuses(),
      ...(reset ? { reset: true } : {}),
      ...(reset && arrival ? { arrival } : {}),
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

  ipcMain.handle(GARDEN_CHANNEL.getData, (event) => {
    if (!trusted(event)) return null;
    reset = true;
    const made = data();
    reset = false;
    return made;
  });
  ipcMain.on(GARDEN_CHANNEL.showIsland, (event, id: unknown) => {
    if (trusted(event) && typeof id === "string" && isKnownIsland(id) && profile.isCompanionUnlocked(id)) garden.showIsland(id);
  });
  const isTile = (col: unknown, row: unknown): boolean => Number.isInteger(col) && Number.isInteger(row);
  const turn = (id: string): boolean => garden.rotate(id);
  ipcMain.handle(GARDEN_CHANNEL.command, (event, command: GardenCommand) => {
    if (!trusted(event) || typeof command !== "object" || command === null) return false;
    switch (command.name) {
      case "place":
        return isTile(command.col, command.row) && garden.place(command.item, { col: command.col, row: command.row }, command.turned === true, command.island) !== null;
      case "placeSomewhere":
        return garden.placeSomewhere(command.item, command.island) !== null;
      case "move":
        return isTile(command.col, command.row) && garden.move(command.id, { col: command.col, row: command.row }, command.turned === true, command.island);
      case "rotate":
        return turn(command.id);
      case "remove":
        garden.remove(command.id);
        return true;
      case "companion":
        if (!isTile(command.col, command.row)) return false;
        garden.setCompanionTile(command.pet, { col: command.col, row: command.row });
        return true;
      default:
        return false;
    }
  });
  ipcMain.handle(GARDEN_CHANNEL.phrase, (event, petId: unknown) => (trusted(event) && typeof petId === "string" && isKnownIsland(petId) ? deps.phrase(petId) : ""));
  ipcMain.on(GARDEN_CHANNEL.contextMenu, (event, id: unknown) => {
    if (!trusted(event) || typeof id !== "string" || !window) return;
    const placement = garden.placement(id);
    if (!placement || !itemWithId(placement.item)) return;
    const message = (text: string): void => { if (window && !window.isDestroyed()) window.webContents.send(GARDEN_CHANNEL.message, text); };
    Menu.buildFromTemplate([
      { label: "Gira", click: () => { if (!turn(id)) message("Girata non ci sta: c'è qualcosa accanto."); } },
      { label: "Togli dal giardino", click: () => garden.remove(id) },
    ]).popup({ window });
  });
  // la cerimonia d'arrivo è finita: si salva solo quello che era davvero da fare (i ponti fra isole aperte non ancora costruiti, le isole da accogliere)
  ipcMain.handle(GARDEN_CHANNEL.finishArrival, (event, done: GardenArrival) => {
    if (!trusted(event) || typeof done !== "object" || done === null) return [];
    const open = openIslands();
    const pendingBridges = garden.pendingBridges(open).filter((b) => Array.isArray(done.bridges) && done.bridges.includes(bridgeId(b)));
    const welcomes = garden.pendingWelcomes(open).filter((id) => Array.isArray(done.welcomed) && done.welcomed.includes(id));
    if (pendingBridges.length === 0 && welcomes.length === 0) return [];
    return garden.buildBridges(pendingBridges, welcomes);
  });
  ipcMain.on(GARDEN_CHANNEL.showAlbum, (event) => { if (trusted(event)) deps.showAlbum(); });
  ipcMain.handle(GARDEN_CHANNEL.greetGuest, (event, id: unknown, reason: unknown) => {
    if (!trusted(event) || typeof id !== "string" || !visitorWithId(id) || typeof reason !== "string") return { isFirst: false, gift: null };
    const welcome = garden.welcomeGuest(id, dayString(wallOf(Date.now())), reason.slice(0, 80));
    return { isFirst: welcome.isFirst, gift: welcome.gift ? itemWithId(welcome.gift.item)?.name ?? welcome.gift.item : null };
  });
  ipcMain.handle(GARDEN_CHANNEL.noteScene, (event, pet: unknown, item: unknown) => {
    if (!trusted(event) || typeof pet !== "string" || typeof item !== "string" || !isKnownIsland(pet)) return false;
    return garden.noteScene(pet, item);
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
      // la prima entrata dopo uno sblocco: i ponti da costruire e i compagni da accogliere (la pagina fa la cerimonia, poi li fa salvare)
      arrival = null;
      if (deps.canCelebrate() && profile.introSeen) {
        const open = openIslands();
        garden.settleBridges(open);
        const bridges = garden.pendingBridges(open).map(bridgeId), welcomed = garden.pendingWelcomes(open);
        if (bridges.length > 0 || welcomed.length > 0) arrival = { bridges, welcomed };
      }
      if (window && !window.isDestroyed()) {
        reset = true;
        push();
        reset = false;
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
          // la pagina disegna solo quando cambia qualcosa: non serve rallentarla in sottofondo, e coperta dalla finestra trasparente del compagno
          // (sempre sopra, grande quanto lo schermo) potrebbe risultare nascosta e smettere di disegnare
          contextIsolation: true, sandbox: true, nodeIntegration: false, backgroundThrottling: false,
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
