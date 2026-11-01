// Il ponte sicuro della finestra del giardino.

import { contextBridge, ipcRenderer } from "electron";
import { GARDEN_CHANNEL } from "../shared/gardenApi.ts";
import type { GardenApi, GardenData, GardenWelcome } from "../shared/gardenApi.ts";

const api: GardenApi = {
  getData: () => ipcRenderer.invoke(GARDEN_CHANNEL.getData) as Promise<GardenData>,
  onData: (callback) => {
    ipcRenderer.on(GARDEN_CHANNEL.data, (_event, data: GardenData) => callback(data));
  },
  showIsland: (id) => ipcRenderer.send(GARDEN_CHANNEL.showIsland, id),
  back: () => ipcRenderer.send(GARDEN_CHANNEL.back),
  command: (command) => ipcRenderer.invoke(GARDEN_CHANNEL.command, command) as Promise<boolean>,
  phrase: (petId) => ipcRenderer.invoke(GARDEN_CHANNEL.phrase, petId) as Promise<string>,
  contextMenu: (id) => ipcRenderer.send(GARDEN_CHANNEL.contextMenu, id),
  finishArrival: (arrival) => ipcRenderer.invoke(GARDEN_CHANNEL.finishArrival, arrival) as Promise<GardenWelcome[]>,
  onMessage: (callback) => {
    ipcRenderer.on(GARDEN_CHANNEL.message, (_event, text: string) => callback(text));
  },
};

contextBridge.exposeInMainWorld("focusfriendsGarden", api);
