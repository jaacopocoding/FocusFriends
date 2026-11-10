// L'album, la sezione «Scene»: alcune scene viste (le altre sono sagome con l'indizio), la linguetta «Scene» e un tocco su una scena da vedere.
//   FF_PROFILO='{"version":1,"introSeen":true,"firstCompanion":"gattino","unlocked":["pianty","porcellino","ciccio","gattino"]}' test/vivo/esegui.sh album-scene.cjs 90
const fs = require("fs");
module.exports = async ({ sleep, albumWindow, garden }) => {
  const out = process.env.FF_SELFTEST_OUT;
  for (const [pet, item] of [["gattino", "amaca"], ["gattino", "cesto-cuscino"], ["pianty", "sdraio"], ["porcellino", "tunnel"], ["porcellino", "picnic"],
    ["porcellino", "cesto-carote"], ["porcellino", "altalena"], ["ciccio", "bagnetto"]]) garden.noteScene(pet, item);
  albumWindow.show();
  for (let i = 0; i < 60 && !(albumWindow.window && !albumWindow.window.isDestroyed()); i += 1) await sleep(50);
  await sleep(2200);
  const wc = () => albumWindow.window.webContents;
  const run = (code) => wc().executeJavaScript(code);
  const shot = async (name) => fs.writeFileSync(`${out}/${name}.png`, (await wc().capturePage()).toPNG());
  await run("window.__album.open()");
  await sleep(1800);
  // la prima doppia pagina della sezione «Scene» (dopo le sei delle figurine)
  await run("window.__album.goToSpread(6)");
  await sleep(1200);
  await shot("scene-0");
  console.log("sezione:", await run("window.__album.categoryTitle(window.__album.spread)"));
  await run("window.__album.goToSpread(window.__album.spread + 1)");
  await sleep(1200);
  await shot("scene-1");
  await run("window.__album.goToSpread(window.__album.spread + 1)");
  await sleep(1200);
  await shot("scene-2");
};
