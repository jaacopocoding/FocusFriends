// La scheda ancorata all'icona nell'area di notifica (barra in basso e in alto).
module.exports = async ({ js, sleep, shot, win }) => {
  await sleep(1500);
  // come se l'icona stesse nella barra delle applicazioni in basso a destra (sotto l'area di lavoro)
  win.webContents.send("card:toggle", { anchor: { x: 1600, y: 975, width: 24, height: 24 }, toggle: true });
  await sleep(800);
  await shot("giu");
  win.webContents.send("card:toggle", { anchor: { x: 1600, y: 975, width: 24, height: 24 }, toggle: true });
  await sleep(500);
  console.log("richiusa:", !(await js("window.__ff.cardOpen()")));
  // come se stesse in alto (barra dei menu del Mac)
  win.webContents.send("card:toggle", { anchor: { x: 1500, y: -24, width: 24, height: 24 }, toggle: true });
  await sleep(800);
  await shot("su");
};
