// «Com'è andata?» dopo un focus finito davvero (circa 75 secondi): compare da sola, si sceglie la faccia e si scrive la nota; si chiude da sola quando riparte un timer.
module.exports = async ({ js, sleep, shot, mouse, key, settings, timer, interactions }) => {
  const rect = async (selector) => JSON.parse(await js(`(() => { const e = document.querySelector(${JSON.stringify(selector)}); if (!e) return 'null'; const r = e.getBoundingClientRect(); return JSON.stringify({x: r.left + r.width / 2, y: r.top + r.height / 2}); })()`));
  const click = async (selector) => { const r = await rect(selector); if (!r) { console.log("non trovato:", selector); return; } mouse("mouseMove", r.x, r.y); await sleep(60); mouse("mouseDown", r.x, r.y); await sleep(40); mouse("mouseUp", r.x, r.y); await sleep(250); };
  await sleep(1500);
  const svc = timer();
  // un focus di un minuto, finito davvero: la scheda compare da sola
  svc.run(() => svc.engine.startFocus(1, "Anatomia"));
  await sleep(72000);
  console.log("scheda «com'è andata» comparsa?", await js("window.__ff.reflectionOpen()"), "fase:", svc.snapshot().phase);
  await shot("com-e-andata");
  // clic nel campo: prende la tastiera; scrivo la nota e scelgo una faccia
  await click(".reflection .text-field");
  await js("(() => { const i = document.querySelector('.reflection .text-field'); i.value = '  nervi   cranici '; })()");
  await click('.reflection [aria-label="Così così"]');
  await sleep(600);
  const session = svc.log.sessions.at(-1);
  console.log("sessione:", JSON.stringify({ rating: session.rating, note: session.note, subject: session.subject }));
  console.log("scheda chiusa?", !(await js("window.__ff.reflectionOpen()")));
  console.log("eventi del mouse:", JSON.stringify(interactions.slice(-4)));
  // si chiude da sola quando il timer riparte
  await js("window.__ff.askReflection({ id: 'x', seconds: 1500, subject: 'Prova' })");
  await sleep(300);
  console.log("scheda riaperta:", await js("window.__ff.reflectionOpen()"));
  svc.run(() => svc.engine.startBreak(5));
  await sleep(500);
  console.log("dopo un nuovo timer:", await js("window.__ff.reflectionOpen()"));
  svc.run(() => svc.engine.stop());
};
