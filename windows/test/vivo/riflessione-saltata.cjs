// «Com'è andata?»: solo la nota, «Salta», e la scheda che si chiude quando riparte un timer.
module.exports = async ({ js, sleep, shot, mouse, key, settings, timer, interactions }) => {
  const rect = async (selector) => JSON.parse(await js(`(() => { const e = document.querySelector(${JSON.stringify(selector)}); if (!e) return 'null'; const r = e.getBoundingClientRect(); return JSON.stringify({x: r.left + r.width / 2, y: r.top + r.height / 2}); })()`));
  const click = async (selector) => { const r = await rect(selector); if (!r) { console.log("non trovato:", selector); return; } mouse("mouseMove", r.x, r.y); await sleep(60); mouse("mouseDown", r.x, r.y); await sleep(40); mouse("mouseUp", r.x, r.y); await sleep(250); };
  await sleep(1500);
  const svc = timer();
  const made = svc.log.add({ start: Date.now() - 3600_000, seconds: 1500, plannedMinutes: 25, completed: true, subject: "Anatomia" });
  await js(`window.__ff.askReflection(${JSON.stringify(made)})`);
  await sleep(500);
  console.log("aperta:", await js("window.__ff.reflectionOpen()"));
  // un clic su «Fatto» con la sola nota: il voto già dato non si cancella
  svc.log.setReflection(made.id, "good", null);
  await click(".reflection .text-field");
  await js("(() => { document.querySelector('.reflection .text-field').value = 'solo la nota'; })()");
  await click(".reflection .pill-action");
  const s1 = svc.log.sessions.find((x) => x.id === made.id);
  console.log("solo nota:", JSON.stringify({ rating: s1.rating, note: s1.note }));
  console.log("eventi:", JSON.stringify(interactions.slice(-3)));
  // Salta non scrive niente
  await js(`window.__ff.askReflection(${JSON.stringify(made)})`);
  await sleep(500);
  await click(".reflection .text-field");
  await js("(() => { document.querySelector('.reflection .text-field').value = 'non salvare'; })()");
  await click(".reflection .text-button");
  const s2 = svc.log.sessions.find((x) => x.id === made.id);
  console.log("dopo Salta:", JSON.stringify({ rating: s2.rating, note: s2.note }));
  // il timer che si ferma la chiude
  await js(`window.__ff.askReflection(${JSON.stringify(made)})`);
  await sleep(300);
  svc.run(() => svc.engine.startFocus(25));
  await sleep(500);
  console.log("dopo un nuovo focus:", await js("window.__ff.reflectionOpen()"));
  svc.run(() => svc.engine.stop());
  await sleep(300);
  console.log("eventi:", JSON.stringify(interactions.slice(-3)));
};
