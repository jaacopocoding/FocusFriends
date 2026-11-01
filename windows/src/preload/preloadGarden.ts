// Il ponte sicuro della finestra del giardino.

import { contextBridge, ipcRenderer } from "electron";
import { GARDEN_CHANNEL } from "../shared/gardenApi.ts";
import type { GardenApi, GardenData } from "../shared/gardenApi.ts";

const api: GardenApi = {
  getData: () => ipcRenderer.invoke(GARDEN_CHANNEL.getData) as Promise<GardenData>,
  onData: (callback) => {
    ipcRenderer.on(GARDEN_CHANNEL.data, (_event, data: GardenData) => callback(data));
  },
  showIsland: (id) => ipcRenderer.send(GARDEN_CHANNEL.showIsland, id),
  back: () => ipcRenderer.send(GARDEN_CHANNEL.back),
};

contextBridge.exposeInMainWorld("focusfriendsGarden", api);
