// Compagni bloccati e sbloccati, nome, titolo della finestra delle statistiche, annunci.
const fs = require("fs"), path = require("path");
module.exports = async ({ js, sleep, shot, mouse, timer, settings, card, stats }) => {
  const rect = async (selector) => JSON.parse(await js(`(() => { const e = document.querySelector(${JSON.stringify(selector)}); if (!e) return 'null'; const r = e.getBoundingClientRect(); return JSON.stringify({x: r.left + r.width / 2, y: r.top + r.height / 2}); })()`));
  const click = async (selector) => { const r = await rect(selector); if (!r) { console.log("non trovato:", selector); return; } mouse("mouseMove", r.x, r.y); await sleep(60); mouse("mouseDown", r.x, r.y); await sleep(40); mouse("mouseUp", r.x, r.y); await sleep(250); };
  const data = async () => js("window.focusfriends.getCardData().then(d => JSON.stringify({ locks: d.companions.map(c => [c.id, c.lock]), name: d.userName }))").then(JSON.parse);
  const profilePath = path.join(process.env.FF_DATA_DIR, "profilo.json");
  const svc = timer();
  await sleep(1500);
  console.log("all'inizio:", JSON.stringify(await data()));
  await js("window.__ff.openCard()"); await sleep(700);
  await shot("bloccati");
  await click('.companion[aria-label^="Porcellino, bloccato"]');
  console.log("suggerimento:", await js("document.querySelector('.lock-hint').textContent"));
  card.command({ name: "selectPet", id: "ciccio" });
  console.log("scelto Ciccio (bloccato): compagno ora", settings.pet);
  await js("window.__ff.closeCard()"); await sleep(300);
  // il nome
  await js("window.__ff.askName()"); await sleep(600);
  console.log("campo nome:", await js("document.querySelector('.modal input').value"));
  await js("(() => { document.querySelector('.modal input').value = '  Giulia '; })()");
  await click(".modal .pill-action"); await sleep(500);
  const p = JSON.parse(fs.readFileSync(profilePath, "utf8"));
  console.log("nome nel profilo:", p.name);
  stats.show("day"); await sleep(1500);
  console.log("titolo della finestra:", stats.window.getTitle());
  stats.window.close(); await sleep(300);
  await js("window.__ff.openCard()"); await sleep(600);
  console.log("saluto:", await js("document.querySelector('.greeting').textContent"));
  await js("window.__ff.closeCard()"); await sleep(300);
  // nome vuoto: lo toglie
  await js("window.__ff.askName()"); await sleep(500);
  await js("(() => { document.querySelector('.modal input').value = ''; })()");
  await click(".modal .pill-action"); await sleep(400);
  console.log("senza nome:", JSON.stringify(JSON.parse(fs.readFileSync(profilePath, "utf8")).name ?? null));
  // lo studio basta per il secondo compagno: annuncio
  svc.log.add({ start: Date.now() - 7 * 24 * 3600_000, seconds: 20 * 3000, plannedMinutes: 50, completed: true, subject: "Anatomia" });
  card.evaluateCompanionRewards(true);
  console.log("sbloccato subito:", JSON.stringify(JSON.parse(fs.readFileSync(profilePath, "utf8")).unlocked));
  await sleep(9800);
  console.log("annuncio:", await js("(document.querySelector('.bubble .text') || {}).textContent"));
  await shot("annuncio");
  card.command({ name: "selectPet", id: "porcellino" });
  await sleep(600);
  console.log("scelto Porcellino:", settings.pet);
  // modalità sviluppatore
  console.log("prima:", JSON.stringify((await data()).locks.filter((l) => l[1]).map((l) => l[0])));
  settings.developerMode = true;
  console.log("sviluppatore:", JSON.stringify((await data()).locks.filter((l) => l[1]).map((l) => l[0])), "profilo intatto:", JSON.stringify(JSON.parse(fs.readFileSync(profilePath, "utf8")).unlocked));
  card.command({ name: "selectPet", id: "gattino" });
  await sleep(500);
  console.log("scelto Gattino in modalità sviluppatore:", settings.pet);
};
