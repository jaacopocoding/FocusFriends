// Il giardino (G2): la finestra, le isole con le loro cose, la vista di tutte le isole, la sera, l'inverno.
// Il giardino si riempie qui, con le cose di ogni isola; il profilo ha già tutti i compagni (lo si dà con FF_PROFILO).
//   FF_PROFILO='{"version":1,"introSeen":true,"firstCompanion":"gattino","unlocked":["pianty","porcellino","ciccio","gattino","riccio"]}' test/vivo/esegui.sh giardino.cjs 120
const fs = require("fs");
module.exports = async ({ sleep, gardenWindow, garden, settings }) => {
  const out = process.env.FF_SELFTEST_OUT;
  // qualche cosa per isola (le stesse tessere ogni volta)
  const place = (island, list) => {
    for (const [id, col, row, turned] of list) {
      garden.drops.found[id] = 1;
      garden.place(id, { col, row }, turned === true, island);
    }
  };
  place("gattino", [["casetta-gatto", 6, 2], ["tiragraffi", 7, 3], ["cesto-cuscino", 6, 4], ["lampione", 2, 6], ["panchina", 3, 7], ["margherite", 8, 8],
    ["tulipani", 9, 7], ["cancelletto", 0, 8], ["cancelletto", 0, 9], ["cancelletto", 1, 9], ["cancelletto", 2, 9], ["amaca", 7, 9], ["candela-cesto", 5, 2]]);
  place("porcellino", [["casetta-porcellino", 6, 2], ["tunnel", 7, 3], ["cesto-carote", 4, 7], ["braciere", 8, 7], ["girasole", 2, 7], ["bandierine", 9, 4]]);
  place("pianty", [["aiuola", 6, 6], ["annaffiatoio", 7, 6], ["lavanda", 5, 7], ["arco-rose", 8, 2], ["alberello-lucine", 2, 7]]);
  place("ciccio", [["bagnetto", 6, 6], ["casetta-uccelli", 7, 3], ["altalena-uccelli", 4, 8], ["lanterna-voliera", 2, 6]]);
  place("riccio", [["tana-foglie", 6, 2], ["zucca-lanterna", 7, 6], ["carriola-ghiande", 3, 7], ["hotel-insetti", 8, 8]]);
  const shot = async (name) => {
    await sleep(500);
    const image = await gardenWindow.window.webContents.capturePage();
    fs.writeFileSync(`${out}/${name}.png`, image.toPNG());
  };
  const run = (code) => gardenWindow.window.webContents.executeJavaScript(code);
  // le stesse schermate di tools/banchi/render-giardino.sh (il Mac, sugli stessi dati): l'ora e la stagione con le chiavi nascoste delle impostazioni
  const at = (hour, season) => { settings["values"]["gardenHour"] = hour; settings["values"]["gardenSeason"] = season; };
  at(14, "autumn");
  gardenWindow.show();
  for (let i = 0; i < 60 && !(gardenWindow.window && !gardenWindow.window.isDestroyed()); i += 1) await sleep(100);
  await sleep(2500);
  console.log("dati:", JSON.stringify(await run("(() => { const g = window.__garden; return { shown: g.data.shown, season: g.data.season, hour: g.data.hour, islands: g.data.islands.map((i) => [i.id, i.size, i.open, i.placements.length]), camera: g.camera, frames: g.frames }; })()")));
  await shot("casa");
  await run("window.__garden.worldView()");
  await shot("mondo");
  await run("(() => { const g = window.__garden; g.setCamera({ zoom: 0.8, panX: g.camera.panX - 180, panY: g.camera.panY - 160 }); })()");
  console.log("isola mostrata dopo lo spostamento:", await run("window.__garden.data.shown"));
  for (const [name, hour, season] of [["sera", 20.5, "autumn"], ["inverno", 12, "winter"]]) {
    at(hour, season);
    gardenWindow.show();
    await run("window.__garden.resetCamera()");
    await sleep(1500);
    await shot(name);
  }
  // quanto costa un fotogramma mentre ci si sposta
  const timing = await run(`(async () => {
    const g = window.__garden; const start = performance.now(); const before = g.frames;
    for (let i = 0; i < 60; i++) { g.setCamera({ ...g.camera, panX: g.camera.panX + 3 }); await new Promise((r) => requestAnimationFrame(r)); }
    return { ms: (performance.now() - start) / 60, frames: g.frames - before };
  })()`);
  console.log("spostamento: ms per fotogramma", JSON.stringify(timing));
};
