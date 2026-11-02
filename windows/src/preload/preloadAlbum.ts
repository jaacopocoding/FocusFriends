// Il ponte sicuro della finestra dell'album.

import { contextBridge, ipcRenderer } from "electron";
import { ALBUM_CHANNEL } from "../shared/albumApi.ts";
import type { AlbumApi, AlbumData } from "../shared/albumApi.ts";

const api: AlbumApi = {
  getData: () => ipcRenderer.invoke(ALBUM_CHANNEL.getData) as Promise<AlbumData>,
  onData: (callback) => {
    ipcRenderer.on(ALBUM_CHANNEL.data, (_event, data: AlbumData) => callback(data));
  },
  markSeen: () => ipcRenderer.send(ALBUM_CHANNEL.markSeen),
  setSpread: (index) => ipcRenderer.send(ALBUM_CHANNEL.setSpread, index),
  back: () => ipcRenderer.send(ALBUM_CHANNEL.back),
};

contextBridge.exposeInMainWorld("focusfriendsAlbum", api);
