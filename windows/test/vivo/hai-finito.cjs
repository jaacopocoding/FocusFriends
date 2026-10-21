// «Hai finito «…»?» a fine focus (dura circa 2 minuti e mezzo): due focus da 1 minuto partiti da una voce di «Da fare», con il comando che manda la scheda.
// 1) con «Chiedi com'è andata» acceso: la scheda ha le facce e la domanda; «Fatta» segna la voce e la scheda si accorcia;
// 2) con «Chiedi com'è andata» spento: la scheda ha solo la domanda; «Non ancora» la chiude e la voce resta da fare.
const fs = require("fs"), path = require("path");

module.exports = async ({ js, sleep, win, timer, card, settings }) => {
  const out = process.env.FF_SELFTEST_OUT;
  const svc = timer();
  const shot = async (name, selector) => {
    const r = JSON.parse(await js(`(() => { const e = document.querySelector(${JSON.stringify(selector)}); if (!e) return 'null'; const b = e.getBoundingClientRect(); return JSON.stringify({ x: Math.round(b.left), y: Math.round(b.top), width: Math.round(b.width), height: Math.round(b.height) }); })()`));
    if (!r) { console.log("niente da fotografare:", name); return; }
    const image = await win.webContents.capturePage({ x: Math.max(r.x - 10, 0), y: Math.max(r.y - 10, 0), width: r.width + 20, height: r.height + 20 });
    fs.writeFileSync(path.join(out, `${name}.png`), image.toPNG());
  };
  const click = (label) => js(`(() => { const e = [...document.querySelectorAll('[aria-label]')].find((x) => x.getAttribute('aria-label') === ${JSON.stringify(label)}); if (!e) return false; e.click(); return true; })()`);
  const items = () => JSON.parse(fs.readFileSync(path.join(process.env.FF_DATA_DIR, "dafare.json"), "utf8")).items;
  const state = () => js("JSON.stringify({ aperta: window.__ff.reflectionOpen(), domanda: (document.querySelector('.reflection-todo-question') || {}).textContent || null, facce: document.querySelectorAll('.reflection .face-button').length, titolo: (document.querySelector('.reflection .dialog-title') || {}).textContent || null, altezza: Math.round((document.querySelector('.reflection') || { offsetHeight: 0 }).offsetHeight) })").then(JSON.parse);
  const bubble = () => js("(document.querySelector('.bubble .text') || document.querySelector('.bubble') || {}).textContent");

  await sleep(1500);
  settings.phraseFrequency = "never";
  card.command({ name: "todoAdd", text: "Riassunto del capitolo 7", due: null, subject: "Anatomia" });
  card.command({ name: "todoAdd", text: "Esercizi di analisi 4–6", due: null, subject: "Analisi" });
  const [first, second] = items();
  console.log("voci:", items().map((i) => i.text).join(" | "));

  // 1) facce + domanda
  settings.askHowItWent = true;
  card.command({ name: "startFocus", minutes: 1, subject: "Anatomia", todoId: first.id });
  await sleep(1000);
  console.log("focus partito:", JSON.stringify({ fase: svc.snapshot().phase, materia: svc.snapshot().subject }));
  await sleep(72000);
  const a = await state();
  console.log("a fine focus:", JSON.stringify(a));
  await shot("1-facce-e-domanda", ".reflection");
  console.log("«Fatta»:", await click("Fatta"));
  await sleep(700);
  const b = await state();
  console.log("dopo «Fatta»:", JSON.stringify(b), "| più bassa di prima:", b.altezza < a.altezza, "| domanda sparita:", b.domanda === null);
  console.log("la voce è fatta nel file:", items().find((i) => i.id === first.id).doneAt !== undefined, "| l'altra no:", items().find((i) => i.id === second.id).doneAt === undefined);
  console.log("fumetto:", await bubble());
  await shot("2-dopo-fatta", ".reflection");
  svc.run(() => svc.engine.stop());
  await sleep(600);
  console.log("scheda chiusa dal nuovo timer/stop:", !(await js("window.__ff.reflectionOpen()")));

  // 2) solo la domanda
  settings.askHowItWent = false;
  card.command({ name: "startFocus", minutes: 1, subject: "Analisi", todoId: second.id });
  await sleep(73000);
  const c = await state();
  console.log("a fine focus (senza «Com'è andata»):", JSON.stringify(c));
  await shot("3-solo-domanda", ".reflection");
  console.log("«Non ancora»:", await click("Non ancora"));
  await sleep(600);
  console.log("scheda chiusa:", !(await js("window.__ff.reflectionOpen()")), "| la voce resta da fare:", items().find((i) => i.id === second.id).doneAt === undefined);
  svc.run(() => svc.engine.stop());
};
