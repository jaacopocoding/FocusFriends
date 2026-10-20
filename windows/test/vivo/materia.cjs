// «Cosa studi adesso?»: indietro, Esc, Invio, materia recente, senza materia.
module.exports = async ({ js, sleep, shot, mouse, key, settings, timer }) => {
  const rect = async (selector) => JSON.parse(await js(`(() => { const e = document.querySelector(${JSON.stringify(selector)}); if (!e) return 'null'; const r = e.getBoundingClientRect(); return JSON.stringify({x: r.left + r.width / 2, y: r.top + r.height / 2}); })()`));
  const click = async (selector) => { const r = await rect(selector); if (!r) { console.log("non trovato:", selector); return; } mouse("mouseMove", r.x, r.y); await sleep(60); mouse("mouseDown", r.x, r.y); await sleep(40); mouse("mouseUp", r.x, r.y); await sleep(250); };
  await sleep(1500);
  const svc = timer();
  // un po' di storia: materie e una nota
  const base = Date.now() - 5 * 3600_000;
  svc.log.add({ start: base, seconds: 1500, plannedMinutes: 25, completed: true, subject: "Anatomia" });
  svc.log.add({ start: base + 1800_000, seconds: 1500, plannedMinutes: 25, completed: true, subject: "Fisica" });
  svc.log.add({ start: base + 3600_000, seconds: 1500, plannedMinutes: 25, completed: true, subject: "Chimica organica" });
  const last = svc.log.add({ start: base + 5400_000, seconds: 1500, plannedMinutes: 25, completed: true, subject: "Anatomia" });
  svc.log.setReflection(last.id, "good", "nervi cranici");
  // dalla scheda: «50 minuti» chiede la materia
  await js("window.__ff.openCard()"); await sleep(600);
  await click('.card-root [aria-label="Focus di 50 minuti"]');
  await sleep(600);
  console.log("scheda chiusa?", !(await js("window.__ff.cardOpen()")), "finestra aperta?", await js("window.__ff.modalOpen()"));
  await shot("materia");
  // la freccia: torna alla scheda
  await click('.modal .back');
  await sleep(500);
  console.log("indietro: scheda aperta?", await js("window.__ff.cardOpen()"), "finestra?", await js("window.__ff.modalOpen()"));
  await js("window.__ff.closeCard()"); await sleep(300);
  // Esc annulla
  await js("window.__ff.askFocus(30)"); await sleep(500);
  key("Escape"); await sleep(400);
  console.log("Esc: finestra?", await js("window.__ff.modalOpen()"), "fase", svc.snapshot().phase);
  // scrivo una materia e premo Invio
  await js("window.__ff.askFocus(30)"); await sleep(500);
  await js("(() => { const i = document.querySelector('.modal input'); i.value = '  fisica   quantistica '; })()");
  key("Enter"); await sleep(500);
  console.log("Invio:", svc.snapshot().phase, svc.snapshot().subject, svc.snapshot().focusMinutes);
  svc.run(() => svc.engine.stop());
  // una materia recente
  await js("window.__ff.askFocus(25)"); await sleep(400);
  await click('.modal .subject-chip[aria-label="Chimica organica"]');
  await sleep(400);
  console.log("materia recente:", svc.snapshot().phase, svc.snapshot().subject);
  svc.run(() => svc.engine.stop());
  // «Senza materia»
  await js("window.__ff.askFocus(25)"); await sleep(400);
  await click('.modal .text-button');
  await sleep(300);
  console.log("senza materia:", svc.snapshot().phase, svc.snapshot().subject);
  svc.run(() => svc.engine.stop());
};
