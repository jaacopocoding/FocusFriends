// Il giardino (G8): la vita sull'isola. Il gattino passeggia e va a dormire nel suo angolo, i fiori ondeggiano, il tè fuma, cadono i petali; la
// mattina passa un ospite (lo si saluta: lascia un regalo); la sera le lucciole e le luci. (Circa un minuto.)
//   FF_PROFILO='{"version":1,"introSeen":true,"firstCompanion":"gattino","unlocked":["pianty","porcellino","ciccio","gattino","riccio"]}' test/vivo/esegui.sh giardino-vita.cjs 150
const fs = require("fs");
module.exports = async ({ sleep, gardenWindow, garden, settings }) => {
  const out = process.env.FF_SELFTEST_OUT;
  settings["values"]["gardenHour"] = 9;
  settings["values"]["gardenSeason"] = "spring";
  const place = (list) => { for (const [id, col, row] of list) { garden.drops.found[id] = 1; garden.place(id, { col, row }, false, "gattino"); } };
  place([["casetta-gatto", 6, 0], ["tiragraffi", 7, 1], ["cesto-cuscino", 6, 2], ["tavolino", 4, 6], ["sdraio", 5, 6], ["tulipani", 6, 7], ["lavanda", 7, 7],
    ["papaveri", 5, 7], ["bandierine", 7, 6]]);
  gardenWindow.show();
  for (let i = 0; i < 60 && !(gardenWindow.window && !gardenWindow.window.isDestroyed()); i += 1) await sleep(50);
  const wc = () => gardenWindow.window.webContents;
  const run = (code) => wc().executeJavaScript(code);
  const shot = async (name) => fs.writeFileSync(`${out}/${name}.png`, (await wc().capturePage()).toPNG());
  await sleep(2500);
  console.log("feste:", JSON.stringify(await run("window.__garden.celebrations")));
  await shot("vita-1");
  const frames0 = await run("window.__garden.frames");
  await sleep(4000);
  console.log("fotogrammi in 4 secondi:", (await run("window.__garden.frames")) - frames0);
  for (let i = 0; i < 6; i += 1) {
    await sleep(4000);
    const state = await run("window.__garden.life");
    console.log(`dopo ${8 + i * 4} s:`, JSON.stringify({ gattino: state.walkers.map((w) => [w.pet, w.to, w.pose]), ospite: state.visitor && [state.visitor.id, state.visitor.to, state.visitor.hint] }));
    if (i === 2) await shot("vita-2");
  }
  await shot("vita-3");
  // l'ospite: lo si saluta
  const greeted = await run("(async () => { await window.__garden.greet(); return window.__garden.message; })()");
  console.log("saluto:", greeted, "ospiti nel diario:", JSON.stringify(garden.guests));
  await sleep(1200);
  await shot("vita-ospite");
  await sleep(3000);
  const after = await run("window.__garden.life");
  console.log("l'ospite dopo il saluto:", JSON.stringify(after.visitor && [after.visitor.id, after.visitor.walking, after.visitor.hint, after.visitor.fade]));
  await shot("vita-ospite-dopo");
  // la sera d'estate
  settings["values"]["gardenHour"] = 21.5;
  settings["values"]["gardenSeason"] = "summer";
  gardenWindow.show();
  await sleep(2500);
  await shot("vita-sera");
  // con il processore: quanto costa un secondo di vita
  const metrics = require("electron").app.getAppMetrics().map((m) => `${m.type} ${m.cpu.percentCPUUsage.toFixed(1)}%`);
  console.log("processore:", metrics.join(", "));
};
