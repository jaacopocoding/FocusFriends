// La scheda «Anno» delle statistiche: la mappa dei giorni, il passaggio del mouse, le tre caselle, l'andamento per settimana con la scelta della
// materia, il clic su un giorno (si apre in «Oggi») e l'anno prima, vuoto. Sessioni inventate negli ultimi dieci mesi, con un generatore semplice.
const fs = require("fs");
module.exports = async ({ js, sleep, timer, stats }) => {
  const svc = timer();
  const out = process.env.FF_SELFTEST_OUT;
  const day = 24 * 3600_000;
  const midnight = new Date(); midnight.setHours(0, 0, 0, 0);
  let state = 4242;
  const next = (n) => { state = (Math.imul(state, 1664525) + 1013904223) >>> 0; return (state >>> 8) % n; };
  const subjects = ["Anatomia", "Chimica", "Fisiologia", "Fisica", undefined];
  for (let d = 300; d >= 0; d -= 1) {
    const dow = new Date(midnight.getTime() - d * day).getDay();
    if (next(10) >= (dow === 0 || dow === 6 ? 4 : 8)) continue;
    for (let k = 0, n = 1 + next(3); k < n; k += 1) {
      const minutes = 15 + next(70);
      svc.log.add({ start: midnight.getTime() - d * day + (8 + 2 * k) * 3600_000, seconds: minutes * 60, plannedMinutes: minutes, completed: true, subject: subjects[next(5)] });
    }
  }
  console.log("sessioni inventate:", svc.log.sessions.length);
  const wait = async () => { for (let i = 0; i < 40 && !(stats.window && !stats.window.isDestroyed()); i += 1) await sleep(100); await sleep(900); };
  const cap = async (name) => { const image = await stats.window.webContents.capturePage(); fs.writeFileSync(`${out}/${name}.png`, image.toPNG()); };
  const run = (code) => stats.window.webContents.executeJavaScript(code);
  const text = (selector) => run(`(document.querySelector(${JSON.stringify(selector)}) || {}).textContent || null`);
  const rectOf = async (selector) => JSON.parse(await run(`(() => { const e = document.querySelector(${JSON.stringify(selector)}); if (!e) return 'null'; const r = e.getBoundingClientRect(); return JSON.stringify({ x: Math.round(r.left + r.width / 2), y: Math.round(r.top + r.height / 2) }); })()`));
  // Il mouse vero della finestra non è sempre «sotto il cursore» (la finestra può non avere il fuoco): se il suggerimento non cambia, si simula l'evento nella pagina.
  const move = async (selector) => {
    const r = await rectOf(selector);
    if (!r) { console.log("non trovato:", selector); return; }
    const before = await text(".year-tip");
    stats.window.webContents.sendInputEvent({ type: "mouseMove", x: r.x, y: r.y });
    await sleep(300);
    if ((await text(".year-tip")) === before) {
      await run(`(() => { const e = document.querySelector(${JSON.stringify(selector)}); e.dispatchEvent(new MouseEvent("mouseover", { bubbles: true })); e.dispatchEvent(new MouseEvent("mouseenter")); })()`);
      await sleep(150);
    }
  };
  const click = async (selector) => { const r = await rectOf(selector); if (!r) { console.log("non trovato:", selector); return false; } for (const type of ["mouseMove", "mouseDown", "mouseUp"]) { stats.window.webContents.sendInputEvent({ type, x: r.x, y: r.y, button: "left", clickCount: 1 }); await sleep(60); } await sleep(500); return true; };

  stats.show("year");
  await wait();
  console.log("schede:", await run("[...document.querySelectorAll('.tab')].map((t) => t.textContent + (t.classList.contains('on') ? '*' : '')).join(' ')"));
  console.log("titolo:", await text(".period-title"), "| «avanti» spento:", await run("document.querySelector('.arrow[aria-label=\"Periodo successivo\"]').hasAttribute('disabled')"));
  console.log("colonne:", await run("document.querySelector('.year-grid').style.gridTemplateColumns"), "| giorni:", await run("document.querySelectorAll('.year-grid .cell').length"),
    "| futuri tratteggiati:", await run("document.querySelectorAll('.year-grid .cell.future').length"), "| oggi:", await run("document.querySelectorAll('.year-grid .cell.today').length"));
  console.log("livelli:", await run("JSON.stringify([0,1,2,3,4].map((n) => document.querySelectorAll('.year-grid .cell.l' + n).length))"));
  console.log("mesi:", await run("[...document.querySelectorAll('.year-months span')].map((s) => s.textContent).join(' ')"));
  console.log("senza passaggio:", await text(".year-tip"));
  await cap("anno-1-alto");
  await move(".year-grid .cell.l3");
  console.log("sopra un giorno:", await text(".year-tip"));
  await cap("anno-2-giorno");
  console.log("caselle:", await run("[...document.querySelectorAll('.year-tile')].map((t) => t.querySelector('.year-tile-value').textContent + ' (' + t.querySelector('.year-tile-caption').textContent + ')').join(' | ')"));
  console.log("andamento:", await text(".trend-caption"), "| materie:", await run("[...document.querySelectorAll('.trend-chip')].map((c) => c.textContent + (c.classList.contains('on') ? '*' : '')).join(' ')"),
    "| barre:", await run("document.querySelectorAll('.trend-slot').length"), "| mesi sotto le barre:", await run("[...document.querySelectorAll('.trend-axis span')].map((s) => s.textContent).join(' ')"));
  await run("document.querySelector('.page').scrollTop = 10000"); await sleep(200);
  await move(".trend-slot:nth-child(30)");
  console.log("sopra una settimana:", await text(".year-tip"));
  await cap("anno-3-basso");
  const before = await text(".trend-caption");
  console.log("scelgo «Chimica»:", await click(".trend-chip:nth-child(3)"));
  console.log("materie:", await run("[...document.querySelectorAll('.trend-chip')].map((c) => c.textContent + (c.classList.contains('on') ? '*' : '')).join(' ')"), "| didascalia prima/dopo:", before, "→", await text(".trend-caption"));
  await run("document.querySelector('.page').scrollTop = 10000"); await sleep(200);
  await cap("anno-4-materia");
  console.log("torno a «Tutte»:", await click(".trend-chip:nth-child(1)"), "→", await text(".trend-caption"));
  await run("document.querySelector('.page').scrollTop = 0"); await sleep(200);
  console.log("clic su un giorno:", await click(".year-grid .cell.l2"));
  console.log("ora la scheda è:", await run("[...document.querySelectorAll('.tab')].filter((t) => t.classList.contains('on')).map((t) => t.textContent).join()"), "| titolo:", await text(".period-title"));
  await cap("anno-5-giorno-aperto");
  stats.show("year"); await sleep(800);
  await click(".arrow[aria-label=\"Periodo precedente\"]");
  console.log("anno prima:", await text(".period-title"), "| contenuto:", await text(".big"), "| mappa presente:", await run("document.querySelector('.year-grid') !== null"));
  await cap("anno-6-anno-prima");
  stats.window.close();
};
