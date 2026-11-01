// Il giardino (G3): i comandi, la cassetta «Da mettere», trascinare una cosa sull'isola (tessere verdi e rosse), girarla con R, toglierla,
// girare una copia con due tocchi, far parlare il compagno, ingrandire con la rotellina. Il mouse è simulato sulla finestra del giardino.
//   FF_PROFILO='{"version":1,"introSeen":true,"firstCompanion":"gattino","unlocked":["pianty","porcellino","ciccio","gattino","riccio"]}' test/vivo/esegui.sh giardino-mosse.cjs 150
const fs = require("fs");
module.exports = async ({ sleep, gardenWindow, garden, settings }) => {
  const out = process.env.FF_SELFTEST_OUT;
  settings["values"]["gardenHour"] = 14;
  settings["values"]["gardenSeason"] = "autumn";
  // qualche figurina trovata, e qualche copia già sull'isola di casa
  for (const id of ["tavolino", "sdraio", "lampione", "panchina", "cancelletto", "amaca", "casetta-gatto", "tiragraffi", "girasole", "funghi", "felci", "picnic"]) garden.drops.found[id] = 1;
  garden.place("tavolino", { col: 6, row: 7 }, false, "gattino");
  garden.place("panchina", { col: 7, row: 2 }, false, "gattino");
  gardenWindow.show();
  for (let i = 0; i < 60 && !(gardenWindow.window && !gardenWindow.window.isDestroyed()); i += 1) await sleep(100);
  await sleep(2500);
  const wc = () => gardenWindow.window.webContents;
  const run = (code) => wc().executeJavaScript(code);
  const shot = async (name) => { await sleep(350); fs.writeFileSync(`${out}/${name}.png`, (await wc().capturePage()).toPNG()); };
  const scale = await run("document.getElementById('scene').clientWidth / 1000");
  const mouse = (type, x, y, extra = {}) => wc().sendInputEvent({ type, x: Math.round(x), y: Math.round(y), button: "left", clickCount: 1, ...extra });
  const drag = async (from, to, steps = 12, before) => {
    mouse("mouseDown", from.x, from.y);
    for (let i = 1; i <= steps; i += 1) { mouse("mouseMove", from.x + (to.x - from.x) * i / steps, from.y + (to.y - from.y) * i / steps, { modifiers: ["leftButtonDown"] }); await sleep(25); }
    await sleep(60);
    if (before) await before();
    const c = await run("JSON.stringify(window.__garden.carry)");
    mouse("mouseUp", to.x, to.y);
    await sleep(400);
    console.log("  trascinamento:", c, "riga:", await run("window.__garden.message"));
  };
  const state = async () => JSON.parse(await run("JSON.stringify((() => { const d = window.__garden.data; const i = d.islands.find((x) => x.id === d.shown); return { shown: d.shown, copie: i.placements.map((p) => [p.item, p.col, p.row, p.turned]), cassetta: window.__garden.trayOpen }; })())"));
  /** Il punto da prendere perché i piedi cadano sulla tessera (i piedi stanno un po' sotto il centro). */
  const tile = async (col, row) => {
    const p = await run(`window.__garden.tileOnScreen(${col}, ${row})`);
    const camera = await run("window.__garden.camera");
    return { x: p.x, y: p.y + 62.52 * camera.zoom / 2 * 0.22 * scale };
  };
  await shot("mosse-comandi");
  console.log("all'inizio:", JSON.stringify(await state()));

  // la pillola apre la cassetta; una cella si porta in vista (la cassetta scorre) e se ne prende il centro
  const openTray = async () => {
    if (!(await state()).cassetta) { mouse("mouseDown", 60 * scale, 569 * scale); mouse("mouseUp", 60 * scale, 569 * scale); await sleep(400); }
  };
  const cell = async (name) => {
    await openTray();
    for (let i = 0; i < 30 && !(await run(`[...document.querySelectorAll('.tray-cell')].some((x) => x.title === ${JSON.stringify(name)})`)); i += 1) await sleep(100);
    return run(`(() => { const c = [...document.querySelectorAll('.tray-cell')].find((x) => x.title === ${JSON.stringify(name)}); c.scrollIntoView({ inline: "nearest" }); const r = c.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; })()`);
  };
  await openTray();
  await shot("mosse-cassetta");
  console.log("cassetta aperta:", (await state()).cassetta);
  console.log("nella cassetta:", (await run("[...document.querySelectorAll('.tray-cell')].map((c) => c.title)")).join(", "));

  // il lampione su una tessera libera: verde, poi si lascia
  await drag(await cell("Lampione"), await tile(4, 7), 14, async () => shot("mosse-verde"));
  console.log("dopo il lampione:", JSON.stringify(await state()));
  // la sdraio sulla casa: rossa, e la riga che lo dice
  await drag(await cell("Sdraio"), await tile(1, 1), 14, async () => shot("mosse-rossa"));
  await shot("mosse-riga");
  console.log("dopo la sdraio sulla casa:", JSON.stringify(await state()));
  // un tocco su una cella: la cosa va da sola su una tessera libera
  const funghi = await cell("Funghi");
  mouse("mouseDown", funghi.x, funghi.y); mouse("mouseUp", funghi.x, funghi.y);
  await sleep(500);
  console.log("dopo un tocco sui funghi:", JSON.stringify(await state()));

  // l'amaca (due tessere) girata con R mentre si trascina
  await drag(await cell("Amaca"), await tile(3, 3), 14, async () => {
    wc().sendInputEvent({ type: "keyDown", keyCode: "R" }); wc().sendInputEvent({ type: "char", keyCode: "r" }); wc().sendInputEvent({ type: "keyUp", keyCode: "R" });
    await sleep(200);
    await shot("mosse-girata");
  });
  console.log("dopo l'amaca girata:", JSON.stringify(await state()));
  // la staccionata: tre pezzi di fila si uniscono
  for (const [col, row] of [[4, 6], [5, 6], [6, 6]]) await drag(await cell("Cancelletto"), await tile(col, row), 10);
  await shot("mosse-staccionata");
  console.log("dopo la staccionata:", JSON.stringify(await state()));

  // il tavolino spostato nella zona in basso a sinistra: tolto
  const table = await tile(6, 7);
  await drag({ x: table.x, y: table.y - 15 * scale }, { x: 120 * scale, y: 558 * scale }, 16, async () => shot("mosse-togli"));
  console.log("dopo aver tolto il tavolino:", JSON.stringify(await state()));

  // due tocchi sul lampione: girato
  const bench = await tile(4, 7);
  const up = { x: bench.x, y: bench.y - 20 * scale };
  mouse("mouseDown", up.x, up.y); mouse("mouseUp", up.x, up.y);
  mouse("mouseDown", up.x, up.y, { clickCount: 2 }); mouse("mouseUp", up.x, up.y, { clickCount: 2 });
  await sleep(500);
  console.log("dopo i due tocchi sul lampione:", JSON.stringify(await state()));

  // un tocco sul compagno: parla
  const pet = await run("(() => { const d = window.__garden.data; const i = d.islands.find((x) => x.id === d.shown); return i.companion; })()");
  const at = await tile(pet.col, pet.row);
  mouse("mouseDown", at.x, at.y - 25 * scale); mouse("mouseUp", at.x, at.y - 25 * scale);
  await sleep(600);
  await shot("mosse-fumetto");
  console.log("fumetto:", await run("document.querySelector('.bubble')?.textContent ?? null"));

  // la rotellina ingrandisce attorno al mouse
  const before = await run("window.__garden.camera.zoom");
  await run("window.__wheel = []; document.getElementById('scene').addEventListener('wheel', (e) => window.__wheel.push([e.deltaX, e.deltaY, e.deltaMode, e.ctrlKey]))");
  for (let i = 0; i < 3; i += 1) { wc().sendInputEvent({ type: "mouseWheel", x: Math.round(500 * scale), y: Math.round(300 * scale), deltaX: 0, deltaY: 120, wheelTicksY: 1, canScroll: true }); await sleep(80); }
  console.log("eventi della rotellina:", JSON.stringify(await run("window.__wheel")));
  await sleep(300);
  console.log("zoom prima e dopo la rotellina:", before, await run("window.__garden.camera.zoom"));
  await shot("mosse-fine");
};
