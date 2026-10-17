// Il ponte sicuro: la pagina non ha Node né Electron, solo queste funzioni.

import { contextBridge, ipcRenderer } from "electron";
import { CHANNEL } from "../shared/api.ts";
import type { FocusFriendsApi, SettingsSnapshot } from "../shared/api.ts";

const api: FocusFriendsApi = {
  getSettings: () => ipcRenderer.invoke(CHANNEL.getSettings) as Promise<SettingsSnapshot>,
  onSettingsChanged: (callback) => {
    ipcRenderer.on(CHANNEL.settingsChanged, (_event, settings: SettingsSnapshot) => callback(settings));
  },
  setInteractive: (interactive) => ipcRenderer.send(CHANNEL.setInteractive, interactive),
  nextPhrase: (petId) => ipcRenderer.invoke(CHANNEL.nextPhrase, petId) as Promise<string>,
  onVisibilityChanged: (callback) => {
    ipcRenderer.on(CHANNEL.visibilityChanged, (_event, visible: boolean) => callback(visible));
  },
  selfTest: process.env["FF_SELFTEST"] !== undefined,
};

contextBridge.exposeInMainWorld("focusfriends", api);
