// La finestra trasparente che copre l'area di lavoro dello schermo (senza la barra delle applicazioni): il compagno, il
// fumetto e il resto sono elementi della sua pagina. I clic passano alle finestre sotto, tranne dove la pagina chiede di
// riceverli (sopra un pixel del compagno): `setIgnoreMouseEvents(true, { forward: true })` continua a far arrivare alla
// pagina i movimenti del mouse, così lei sa quando riaccendere i clic.

import { BrowserWindow, screen } from "electron";
import type { Display } from "electron";
import { join } from "node:path";
import { SCHEME } from "./protocol.ts";

export function createOverlay(display: Display, appPath: string): BrowserWindow {
  const area = display.workArea;
  const window = new BrowserWindow({
    x: area.x, y: area.y, width: area.width, height: area.height,
    transparent: true, frame: false, hasShadow: false, backgroundColor: "#00000000",
    resizable: false, movable: false, minimizable: false, maximizable: false, fullscreenable: false,
    focusable: false, skipTaskbar: true, show: false, alwaysOnTop: true,
    webPreferences: {
      preload: join(appPath, "dist", "preload", "preload.cjs"),
      contextIsolation: true, sandbox: true, nodeIntegration: false,
      // I timer e le animazioni non devono rallentare quando la finestra non è in primo piano.
      backgroundThrottling: false,
      // I suoni (fine focus, sottofondo) partono anche senza che l'utente tocchi la pagina.
      autoplayPolicy: "no-user-gesture-required",
    },
  });
  window.setAlwaysOnTop(true, "screen-saver");
  window.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true, skipTransformProcessType: true });
  window.setIgnoreMouseEvents(true, { forward: true });
  void window.loadURL(`${SCHEME}://app/index.html`);
  window.once("ready-to-show", () => window.showInactive());
  return window;
}

/** Adatta la finestra all'area di lavoro (cambia la barra delle applicazioni, la risoluzione, la scala…). */
export function fitToWorkArea(window: BrowserWindow, display: Display): void {
  const area = display.workArea;
  const current = window.getBounds();
  if (current.x !== area.x || current.y !== area.y || current.width !== area.width || current.height !== area.height) {
    window.setBounds(area);
  }
}

export function primaryDisplay(): Display {
  return screen.getPrimaryDisplay();
}
