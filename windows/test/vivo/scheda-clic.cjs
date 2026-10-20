// Clic veri sulla scheda: Esc, Frasi, Cammina, durate, ferma e riprendi, note, clic fuori, pagina dopo lo stop.
module.exports = async ({ js, sleep, shot, timer, settings, mouse, key }) => {
  const state = async () => JSON.parse(await js("JSON.stringify(window.__ff.state())"));
  const rect = async (label) => JSON.parse(await js(`(() => { const e = [...document.querySelectorAll('.card-root [aria-label]')].find(b => b.getAttribute('aria-label') === ${JSON.stringify(label)}); if (!e) return 'null'; const r = e.getBoundingClientRect(); return JSON.stringify({x: r.left + r.width / 2, y: r.top + r.height / 2}); })()`));
  const click = async (label) => { const r = await rect(label); if (!r) { console.log("non trovato:", label); return false; } mouse("mouseMove", r.x, r.y); await sleep(60); mouse("mouseDown", r.x, r.y); await sleep(40); mouse("mouseUp", r.x, r.y); await sleep(250); return true; };
  await sleep(1500);
  const svc = timer();
  await js("window.__ff.openCard()");
  await sleep(600);
  // Esc chiude
  key("Escape"); await sleep(300);
  console.log("dopo Esc aperta?", await js("window.__ff.cardOpen()"));
  // tocco su «Frasi»: il valore cambia
  await js("window.__ff.openCard()"); await sleep(600);
  console.log("Frasi prima:", settings.phraseFrequency);
  await click("Frasi");
  console.log("Frasi dopo:", settings.phraseFrequency);
  // interruttore del movimento
  console.log("movimento prima:", settings.movement);
  await click("Cammina per lo schermo");
  console.log("movimento dopo:", settings.movement);
  // clic sul fondo (fuori dalla scheda) la chiude
  mouse("mouseDown", 100, 100); await sleep(50); mouse("mouseUp", 100, 100); await sleep(300);
  console.log("dopo il clic fuori aperta?", await js("window.__ff.cardOpen()"));
  // Focus 50 dalla scheda
  await js("window.__ff.openCard()"); await sleep(600);
  await click("Focus di 50 minuti");
  await sleep(500);
  // Dalla scheda si passa prima da «Cosa studi adesso?»: si scrive una materia e si preme Invio.
  console.log("finestra della materia aperta?", await js("window.__ff.modalOpen()"));
  await js("(() => { document.querySelector('.modal input').value = 'Anatomia'; })()");
  key("Enter"); await sleep(500);
  console.log("dopo «50 minuti»:", JSON.stringify({ aperta: await js("window.__ff.cardOpen()"), fase: svc.snapshot().phase, minuti: svc.snapshot().focusMinutes, remaining: svc.snapshot().remainingText }));
  // riapro: ora è la pagina del focus; fermo e riprendo
  await js("window.__ff.openCard()"); await sleep(600);
  await click("Ferma");
  console.log("fermo:", svc.snapshot().isPaused);
  await click("Riprendi");
  console.log("ripreso:", !svc.snapshot().isPaused);
  // una nota dal foglietto
  const note = await rect("Scrivi una nota");
  mouse("mouseDown", note.x, note.y); await sleep(40); mouse("mouseUp", note.x, note.y); await sleep(100);
  await js("(() => { const i = document.querySelector('.postit-input'); i.focus(); i.value = 'chiedere al prof'; })()");
  key("Enter"); await sleep(400);
  console.log("note:", JSON.stringify(svc.snapshot().notes));
  svc.run(() => svc.engine.stop());
  await sleep(300);
  console.log("pagina dopo lo stop:", await js("document.querySelector('.card') && document.querySelector('.card').className"));
  await js("window.__ff.closeCard()");
};
