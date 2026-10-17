// «Avvia al login»: l'app parte da sola quando si accede a Windows. Solo nell'app installata: da sviluppo registrerebbe il programma
// sbagliato (Electron stesso).

import type { App } from "electron";

export interface LoginItem {
  available: boolean;
  enabled(): boolean;
  set(on: boolean): void;
}

export function loginItem(app: App): LoginItem {
  return {
    available: app.isPackaged,
    enabled: () => app.isPackaged && app.getLoginItemSettings().openAtLogin,
    set: (on) => { if (app.isPackaged) app.setLoginItemSettings({ openAtLogin: on }); },
  };
}
