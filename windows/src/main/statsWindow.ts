// La finestra delle statistiche (DashboardController in DashboardWindow.swift): una finestra vera, con la barra del titolo, che si
// crea alla prima richiesta e si distrugge alla chiusura (così non tiene memoria quando non serve). I numeri li calcola la pagina
// a partire dalle sessioni; qui ci sono i comandi che toccano i dati e le finestre di sistema.

import { BrowserWindow, dialog, ipcMain } from "electron";
import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { csv } from "../core/csv.ts";
import type { SessionLog } from "../core/log.ts";
import type { Profile } from "../core/profile.ts";
import type { PeriodKind } from "../core/stats.ts";
import { STATS_CHANNEL } from "../shared/statsApi.ts";
import type { SessionEdit, StatsData } from "../shared/statsApi.ts";
import { SCHEME } from "./protocol.ts";

export interface StatsDeps {
  appPath: string;
  log: () => SessionLog;
  profile: Profile;
  /** «‹ Menu»: si torna alla scheda. */
  onBack(): void;
  /** Dopo «Cancella tutto…»: altro da togliere oltre a sessioni e profilo (il giardino, nella seconda uscita). */
  onDeleteAll(): void;
}

export interface StatsController {
  show(kind?: PeriodKind): void;
  /** Il titolo segue il nome (se cambia). */
  refreshTitle(): void;
  readonly window: BrowserWindow | null;
}

export function createStatsController(deps: StatsDeps): StatsController {
  let window: BrowserWindow | null = null;
  let observed = false;

  const data = (kind: PeriodKind | null): StatsData => ({
    sessions: deps.log().sessions, now: Date.now(), title: deps.profile.statsTitle, kind,
  });
  const push = (): void => {
    if (window && !window.isDestroyed()) window.webContents.send(STATS_CHANNEL.data, data(null));
  };
  /** Solo la nostra finestra può dare questi comandi. */
  const trusted = (event: Electron.IpcMainEvent | Electron.IpcMainInvokeEvent): boolean =>
    window !== null && !window.isDestroyed() && event.sender === window.webContents;

  let pendingKind: PeriodKind | null = null;
  ipcMain.handle(STATS_CHANNEL.getData, (event) => {
    if (!trusted(event)) return null;
    const kind = pendingKind;
    pendingKind = null;
    return data(kind);
  });
  ipcMain.on(STATS_CHANNEL.edit, (event, edit: SessionEdit) => {
    if (!trusted(event)) return;
    const log = deps.log();
    // Per correggere una materia scritta male (o unirne due) in tutte le sessioni in un colpo solo.
    if (edit.everywhere && edit.originalSubject !== null) log.renameSubject(edit.originalSubject, edit.subject);
    else log.setSubject(edit.id, edit.subject);
    log.setReflection(edit.id, edit.rating, edit.note);
    log.setNotes(edit.id, edit.notes);
  });
  ipcMain.on(STATS_CHANNEL.delete, (event, id: string) => {
    if (trusted(event)) deps.log().remove(id);
  });
  ipcMain.on(STATS_CHANNEL.back, (event) => {
    if (!trusted(event)) return;
    window?.close();
    deps.onBack();
  });

  ipcMain.on(STATS_CHANNEL.exportCsv, (event) => {
    if (!trusted(event) || !window) return;
    void (async () => {
      const preset = process.env["FF_SELFTEST_SAVE"];
      let target: string | undefined = preset;
      if (target === undefined) {
        const result = await dialog.showSaveDialog(window!, { defaultPath: "focusfriends-sessioni.csv", filters: [{ name: "CSV", extensions: ["csv"] }] });
        if (result.canceled || !result.filePath) return;
        target = result.filePath;
      }
      try {
        writeFileSync(target, csv(deps.log().sessions), "utf8");
      } catch (error) {
        await dialog.showMessageBox(window!, { type: "error", message: "Non riesco a salvare il file", detail: error instanceof Error ? error.message : String(error) });
      }
    })();
  });

  ipcMain.on(STATS_CHANNEL.deleteAll, (event) => {
    if (!trusted(event) || !window) return;
    void (async () => {
      const count = deps.log().sessions.length;
      const confirmed = process.env["FF_SELFTEST_CONFIRM"] === "1" || (await dialog.showMessageBox(window!, {
        type: "warning", message: "Cancellare tutti i dati?",
        detail: `Verranno cancellate tutte le sessioni di studio (${count}), le copie di sicurezza e il tuo nome. Non si può annullare. Se vuoi tenerle, esportale prima con «Esporta CSV…».`,
        buttons: ["Cancella tutto", "Annulla"], defaultId: 1, cancelId: 1,
      })).response === 0;
      if (!confirmed) return;
      deps.log().deleteAll();
      deps.profile.reset();
      deps.onDeleteAll();
      push();
      window?.setTitle(deps.profile.statsTitle);
    })();
  });

  return {
    get window() { return window; },
    refreshTitle() {
      if (window && !window.isDestroyed()) window.setTitle(deps.profile.statsTitle);
    },
    show(kind = "day") {
      if (!observed) {
        observed = true;
        deps.log().addObserver(push);       // chiusa la finestra non fa niente
      }
      if (window && !window.isDestroyed()) {
        pendingKind = kind;
        window.webContents.send(STATS_CHANNEL.data, data(kind));
        pendingKind = null;
        window.setTitle(deps.profile.statsTitle);
        if (window.isMinimized()) window.restore();
        window.show();
        window.focus();
        return;
      }
      pendingKind = kind;
      const created = new BrowserWindow({
        width: 560, height: 660, useContentSize: true, resizable: false, maximizable: false, fullscreenable: false,
        title: deps.profile.statsTitle, backgroundColor: "#fff6de", autoHideMenuBar: true, show: false,
        webPreferences: {
          preload: join(deps.appPath, "dist", "preload", "preload-stats.cjs"),
          contextIsolation: true, sandbox: true, nodeIntegration: false,
        },
      });
      created.setMenuBarVisibility(false);
      created.once("ready-to-show", () => { created.show(); created.focus(); });
      created.on("closed", () => { if (window === created) window = null; });
      // Il titolo della finestra è quello del profilo (la pagina ha il suo <title>, che non deve scavalcarlo).
      created.on("page-title-updated", (event) => event.preventDefault());
      window = created;
      void created.loadURL(`${SCHEME}://app/stats.html`);
    },
  };
}
