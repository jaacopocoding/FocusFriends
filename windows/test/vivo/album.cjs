// L'album (G6): la copertina, l'apertura (con l'animazione), le pagine che girano, le linguette, un tocco su una figurina.
//   FF_PROFILO='{"version":1,"introSeen":true,"name":"Jacopo","firstCompanion":"gattino","unlocked":["gattino","pianty","porcellino"]}' test/vivo/esegui.sh album.cjs 90
const fs = require("fs");
module.exports = async ({ sleep, albumWindow, garden }) => {
  const out = process.env.FF_SELFTEST_OUT;
  // qualche figurina trovata (una nuova), e una doppia pagina completa (i fiori)
  for (const id of ["tulipani", "funghi", "lavanda", "papaveri", "felci", "girasole", "rosaio", "tiragraffi", "cesto-cuscino", "lampione", "panchina", "amaca"]) garden.drops.found[id] = 1;
  garden.place("lampione", { col: 4, row: 7 }, false, "gattino");
  garden.unseen.add("amaca");
  albumWindow.show();
  for (let i = 0; i < 60 && !(albumWindow.window && !albumWindow.window.isDestroyed()); i += 1) await sleep(50);
  await sleep(2200);
  const wc = () => albumWindow.window.webContents;
  const run = (code) => wc().executeJavaScript(code);
  const shot = async (name) => fs.writeFileSync(`${out}/${name}.png`, (await wc().capturePage()).toPNG());
  const scale = await run("window.innerWidth / 980");
  const click = (x, y) => {
    wc().sendInputEvent({ type: "mouseDown", x: Math.round(x * scale), y: Math.round(y * scale), button: "left", clickCount: 1 });
    wc().sendInputEvent({ type: "mouseUp", x: Math.round(x * scale), y: Math.round(y * scale), button: "left", clickCount: 1 });
  };
  await shot("album-copertina");
  click(490, 340);
  await sleep(650);
  await shot("album-si-apre");
  await sleep(1000);
  await shot("album-aperto");
  console.log("aperto:", JSON.stringify(await run("({ mode: window.__album.mode, spread: window.__album.spread, sezione: window.__album.categoryTitle(window.__album.spread) })")),
    "nuove dopo l'apertura:", [...garden.unseen].length);
  // la freccia avanti: la pagina gira
  const next = { x: 950 - 19, y: 40 + 625 + 7 + 14 };
  click(next.x, next.y);
  await sleep(280);
  await shot("album-gira");
  await sleep(700);
  await shot("album-dopo");
  console.log("dopo la freccia:", await run("window.__album.spread"));
  // la linguetta «Fiori»: la doppia pagina completa, con il sigillo
  await run("window.__album.goToSpread(0)");
  await sleep(900);
  await shot("album-fiori");
  // un tocco su una figurina: la riga in fondo
  click(170, 260);
  await sleep(300);
  console.log("riga:", await run("window.__album.message"));
  await shot("album-riga");
};
