// Le statistiche: periodi, modifica di una sessione, esporta CSV, elimina, cancella tutto.
const fs = require("fs");
module.exports = async ({ js, sleep, timer, stats, settings }) => {
  const svc = timer();
  const out = process.env.FF_SELFTEST_OUT;
  const day = 24 * 3600_000;
  const now = Date.now();
  const midnight = new Date(); midnight.setHours(0, 0, 0, 0);
  const at = (daysAgo, hour, minute = 0) => midnight.getTime() - daysAgo * day + (hour * 60 + minute) * 60_000;
  const add = (daysAgo, hour, minutes, subject, extra = {}) => {
    const s = svc.log.add({ start: at(daysAgo, hour), seconds: minutes * 60, plannedMinutes: minutes, completed: extra.completed ?? true, subject, notes: extra.notes });
    if (s && (extra.rating || extra.note)) svc.log.setReflection(s.id, extra.rating ?? null, extra.note ?? null);
  };
  // oggi (le ore sono prima di adesso, qualunque ora sia: per le prove va bene anche se è mattina presto)
  const h = Math.max(new Date().getHours() - 1, 0);
  add(0, Math.max(h - 3, 0), 50, "Anatomia", { rating: "good", note: "nervi cranici", notes: ["rivedere il VII paio", "esercizio 4"] });
  add(0, Math.max(h - 1, 0), 25, "Fisica", { rating: "soso" });
  add(0, h, 12, "Fisica", { completed: false });
  for (let d = 1; d <= 9; d += 1) {
    add(d, 9, 50, ["Anatomia", "Fisica", "Chimica organica"][d % 3], { rating: ["good", "soso", "poor"][d % 3] });
    if (d % 2 === 0) add(d, 15, 30, "Storia dell'arte");
    if (d % 4 === 0) add(d, 18, 40, undefined, { rating: "good" });
  }
  for (let d = 11; d <= 20; d += 3) add(d, 10, 45, "Biochimica");
  const wait = async () => { for (let i = 0; i < 40 && !(stats.window && !stats.window.isDestroyed()); i += 1) await sleep(100); await sleep(900); };
  const cap = async (name) => { const image = await stats.window.webContents.capturePage(); fs.writeFileSync(`${out}/${name}.png`, image.toPNG()); };
  const run = (code) => stats.window.webContents.executeJavaScript(code);
  stats.show("day");
  await wait();
  await cap("stats-oggi");
  await run("document.querySelector('.tab[data-kind=\"week\"]').click()"); await sleep(400);
  await cap("stats-settimana");
  await run("document.querySelector('.tab[data-kind=\"month\"]').click()"); await sleep(400);
  await cap("stats-mese");
  await run("document.querySelector('.tab[data-kind=\"week\"]').click()"); await sleep(300);
  await run("document.querySelector('.diary-toggle').click()"); await sleep(500);
  await cap("stats-diario-settimana");
  await run("document.querySelector('.tab[data-kind=\"day\"]').click()"); await sleep(300);
  await run("document.querySelector('.diary-toggle').click()"); await sleep(500);
  await cap("stats-diario-giorno");
  // modifica di una sessione
  await run("document.querySelector('.session').click()"); await sleep(400);
  await cap("stats-modifica");
  console.log("titolo:", stats.window.getTitle(), "giorno prima disabilitato?", await run("document.querySelector('.arrow.dim') !== null"));
  // cambio il voto e la nota, e salvo per tutte le sessioni «Anatomia»
  await run(`(() => { document.querySelector('.edit .field').value = 'Anatomia umana'; document.querySelector('#everywhere').checked = true; document.querySelectorAll('.rating-option')[3].click(); document.querySelectorAll('.edit .field')[1].value = 'ripassato tutto'; document.querySelector('.pill-action').click(); })()`);
  await sleep(600);
  const subjects = [...new Set(svc.log.sessions.map((s) => s.subject))];
  console.log("materie dopo la modifica:", JSON.stringify(subjects));
  const edited = svc.log.sessions.find((s) => s.note === "ripassato tutto");
  console.log("sessione modificata:", JSON.stringify({ rating: edited && edited.rating, subject: edited && edited.subject }));
  // esporta CSV
  const target = `${out}/esportato.csv`;
  process.env.FF_SELFTEST_SAVE = target;
  await run("document.querySelectorAll('.bottom .link')[1].click()"); await sleep(700);
  const csv = fs.readFileSync(target, "utf8");
  console.log("csv:", csv.split("\n")[0], "righe:", csv.trim().split("\n").length);
  // elimino una sessione dal diario
  const before = svc.log.sessions.length;
  await run("document.querySelector('.session').click()"); await sleep(300);
  await run("document.querySelector('.danger-text').click()"); await sleep(500);
  console.log("sessioni:", before, "->", svc.log.sessions.length);
  // «‹ Menu»: la finestra si chiude
  await run("document.querySelector('.back-pill').click()"); await sleep(500);
  console.log("finestra chiusa?", !stats.window);
  // riapro e cancello tutto
  stats.show("day"); await wait();
  process.env.FF_SELFTEST_CONFIRM = "1";
  await run("document.querySelectorAll('.bottom .link')[0].click()"); await sleep(800);
  console.log("dopo «Cancella tutto»:", svc.log.sessions.length, "sessioni; testo:", await run("document.querySelector('.big').textContent"));
  await cap("stats-vuote");
};
