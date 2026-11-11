// Il giro guidato: dopo la scheda della prima apertura il compagno chiama («Cliccami!!!»), un clic su di lui apre la scheda e il giro passa
// le sue parti una alla volta (il velo, il fumetto, l'immagine per giardino, statistiche e album); «Salta» lo chiude. Serve FF_INTRO=1 nel lancio.
module.exports = async ({ js, sleep, shot, mouse }) => {
  const rect = async (selector) => JSON.parse(await js(`(() => { const e = document.querySelector(${JSON.stringify(selector)}); if (!e) return 'null'; const r = e.getBoundingClientRect(); return JSON.stringify({x: r.left + r.width / 2, y: r.top + r.height / 2}); })()`));
  const click = async (selector) => { const r = await rect(selector); if (!r) { console.log("non trovato:", selector); return; } mouse("mouseMove", r.x, r.y); await sleep(60); mouse("mouseDown", r.x, r.y); await sleep(40); mouse("mouseUp", r.x, r.y); await sleep(300); };
  await sleep(2500);
  console.log("intro aperta?", await js("window.__ff.modalOpen()"));
  await shot("giro-0-intro");
  await click(".pill-action");
  await sleep(1500);
  console.log("dopo l'intro:", await js("JSON.stringify(window.__ff.tour())"), "· fumetto:", await js("document.querySelector('.bubble')?.textContent ?? '(nessuno)'"));
  await shot("giro-1-cliccami");
  // un clic sul compagno (sul suo centro, dove ha i pixel)
  const pet = JSON.parse(await js("JSON.stringify(window.__ff.state())"));
  const px = pet.left + pet.width / 2, py = pet.top + pet.height * 0.6;
  console.log("sopra il compagno?", await js(`window.__ff.hit(${px}, ${py})`));
  mouse("mouseMove", px, py); await sleep(80); mouse("mouseDown", px, py); await sleep(40); mouse("mouseUp", px, py);
  await sleep(900);
  console.log("scheda aperta?", await js("window.__ff.cardOpen()"), JSON.stringify(await js("JSON.stringify(window.__ff.tour())")));
  for (let i = 1; i <= 8; i += 1) {
    const text = await js("document.querySelector('.tour-tip .tour-text')?.textContent ?? '(nessun fumetto)'");
    const peek = await js("document.querySelector('.tour-peek')?.getAttribute('src') ?? ''");
    const where = JSON.parse(await js("JSON.stringify(window.__ff.state())"));
    console.log(`passo ${i}:`, text, peek ? `· immagine ${peek.split("/").pop()}` : "", `· compagno a x=${Math.round(where.left)}`);
    await shot(`giro-passo-${i}`);
    await click(".tour-next");
    await sleep(400);
  }
  console.log("finito:", await js("JSON.stringify(window.__ff.tour())"), "· scheda aperta?", await js("window.__ff.cardOpen()"),
    "· fumetto:", await js("document.querySelector('.bubble')?.textContent ?? '(nessuno)'"));
  // di nuovo, e «Salta»
  await js("window.__ff.closeCard()"); await sleep(300);
  await js("window.__ff.startTour()"); await sleep(600);
  await js("window.__ff.openCard()"); await sleep(800);
  await click(".tour-skip");
  console.log("dopo «Salta»:", await js("JSON.stringify(window.__ff.tour())"), "· scheda aperta?", await js("window.__ff.cardOpen()"),
    "· fumetto:", await js("document.querySelector('.bubble')?.textContent ?? '(nessuno)'"));
};
