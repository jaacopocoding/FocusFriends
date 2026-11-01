// Il giardino (G5): il mondo. Si parte con il solo Gattino; poi si sblocca il Porcellino e, all'entrata nel giardino, la cerimonia: la telecamera
// inquadra le due isole, il ponte compare pezzo per pezzo, si salva e arriva il regalo di benvenuto con le stelline. Poi i nomi e i lucchetti
// rimpicciolendo, e un tocco su un'isola chiusa.
//   FF_PROFILO='{"version":1,"introSeen":true,"firstCompanion":"gattino","unlocked":["gattino"]}' test/vivo/esegui.sh giardino-mondo.cjs 120
const fs = require("fs");
module.exports = async ({ sleep, gardenWindow, garden, settings, profile }) => {
  const out = process.env.FF_SELFTEST_OUT;
  settings["values"]["gardenHour"] = 15;
  settings["values"]["gardenSeason"] = "autumn";
  console.log("prima:", JSON.stringify({ ponti: garden.bridges, accolti: garden.welcomed }));
  profile.unlock(["porcellino"]);
  gardenWindow.show();
  for (let i = 0; i < 60 && !(gardenWindow.window && !gardenWindow.window.isDestroyed()); i += 1) await sleep(50);
  const wc = () => gardenWindow.window.webContents;
  const run = (code) => wc().executeJavaScript(code);
  const shot = async (name) => fs.writeFileSync(`${out}/${name}.png`, (await wc().capturePage()).toPNG());
  for (let i = 0; i < 40 && !(await run("window.__garden?.data !== null && window.__garden?.data !== undefined")); i += 1) await sleep(100);
  console.log("cerimonia:", JSON.stringify(await run("window.__garden.ceremony")));
  await sleep(1300);
  await shot("mondo-telecamera");
  await sleep(1000);
  await shot("mondo-ponte");
  await sleep(1800);
  await shot("mondo-regalo");
  console.log("feste:", JSON.stringify(await run("window.__garden.celebrations")), "isola viva:", await run("window.__garden.data.shown"));
  console.log("dopo:", JSON.stringify({ ponti: garden.bridges, accolti: garden.welcomed, porcellino: garden.placementsOn("porcellino").map((p) => p.item) }));
  await sleep(4500);
  // rimpicciolendo, i nomi e i lucchetti delle isole chiuse
  await run("window.__garden.worldView()");
  await sleep(600);
  await shot("mondo-nomi");
  // un tocco sull'isola chiusa del Riccio
  const scale = await run("document.getElementById('scene').clientWidth / 1000");
  const lock = await run("(() => { const locks = [...document.querySelectorAll('.lock')].map((l) => l.getBoundingClientRect()); const r = locks[locks.length - 1]; return { x: r.left + r.width / 2, y: r.top + r.height / 2 + 20 }; })()");
  wc().sendInputEvent({ type: "mouseDown", x: Math.round(lock.x), y: Math.round(lock.y), button: "left", clickCount: 1 });
  wc().sendInputEvent({ type: "mouseUp", x: Math.round(lock.x), y: Math.round(lock.y), button: "left", clickCount: 1 });
  await sleep(400);
  console.log("riga sull'isola chiusa:", await run("window.__garden.message"), "scala", scale);
  await shot("mondo-chiusa");
  // riaprendo, niente cerimonia (è già fatta)
  gardenWindow.show();
  await sleep(500);
  console.log("seconda entrata, cerimonia:", JSON.stringify(await run("window.__garden.ceremony")));
};
