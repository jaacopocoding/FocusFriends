// L'isola della Tartaruga: la casa, le sette cose, gli angoli (il rifugio e l'orto delle fragole), di giorno, di sera e con tutte le isole.
//   FF_PROFILO='{"version":1,"introSeen":true,"firstCompanion":"tartaruga","unlocked":["pianty","porcellino","ciccio","gattino","riccio","tartaruga"]}' test/vivo/esegui.sh giardino-tartaruga.cjs 90
const fs = require("fs");
module.exports = async ({ sleep, gardenWindow, garden, settings }) => {
  const out = process.env.FF_SELFTEST_OUT;
  settings["values"]["gardenHour"] = 15;
  settings["values"]["gardenSeason"] = "summer";
  const place = (list) => { for (const [id, col, row] of list) { garden.drops.found[id] = 1; garden.place(id, { col, row }, false, "tartaruga"); } };
  place([["rifugio-paglia", 6, 3], ["sasso-sole", 7, 4], ["lanterna-carta", 5, 3], ["aiuola-fragole", 3, 4], ["lattuga", 4, 4], ["laghetto", 3, 5], ["bandiera-traguardo", 7, 6]]);
  console.log("angoli:", JSON.stringify(garden.takeNewCorners()));
  gardenWindow.show();
  for (let i = 0; i < 60 && !(gardenWindow.window && !gardenWindow.window.isDestroyed()); i += 1) await sleep(50);
  const wc = () => gardenWindow.window.webContents;
  const run = (code) => wc().executeJavaScript(code);
  const shot = async (name) => fs.writeFileSync(`${out}/${name}.png`, (await wc().capturePage()).toPNG());
  await sleep(3000);
  console.log("isola:", await run("window.__garden.data.shown"), "figurine:", await run("window.__garden.data.total"));
  await shot("tartaruga-isola");
  // la sera, sulla stessa isola (la vista del mondo, dopo, rende viva l'isola al centro)
  settings["values"]["gardenHour"] = 21.5;
  gardenWindow.show();
  await sleep(2500);
  await shot("tartaruga-sera");
  await run("window.__garden.worldView()");
  await sleep(1500);
  await shot("tartaruga-mondo");
};
