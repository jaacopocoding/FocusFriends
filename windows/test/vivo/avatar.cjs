// La riga «Avatar» della scheda e la sua pagina (il palco che scorre, le sagome di chi non c'è ancora, «Studia con …»). Serve un profilo
// con qualche compagno ancora bloccato:
//   FF_PROFILO='{"version":1,"introSeen":true,"name":"Mia","firstCompanion":"gattino","unlocked":["gattino","pianty"]}' \
//   FF_IMPOSTAZIONI='{"pet":"gattino"}' test/vivo/esegui.sh avatar
module.exports = async ({ js, sleep, shot, mouse, settings }) => {
  const rect = async (selector) => JSON.parse(await js(`(() => { const e = document.querySelector(${JSON.stringify(selector)}); if (!e) return 'null'; const r = e.getBoundingClientRect(); return JSON.stringify({x: r.left + r.width / 2, y: r.top + r.height / 2, left: r.left, top: r.top, width: r.width}); })()`));
  const click = async (selector) => { const r = await rect(selector); if (!r) { console.log("non trovato:", selector); return; } mouse("mouseMove", r.x, r.y); await sleep(60); mouse("mouseDown", r.x, r.y); await sleep(40); mouse("mouseUp", r.x, r.y); await sleep(350); };
  const text = (selector) => js(`document.querySelector(${JSON.stringify(selector)})?.textContent ?? null`);
  await sleep(1500);
  await js("window.__ff.openCard()");
  await sleep(900);
  console.log("riga:", await js("document.querySelector('.avatar-row')?.getAttribute('aria-label') ?? null"), "· sotto:", await text(".avatar-next-text"));
  console.log("vecchia fila dei nomi?", await js("!!document.querySelector('.companions')"));
  await shot("scheda");

  await click(".avatar-row");
  await sleep(600);
  console.log("il palco riceve i clic?", await js("(() => { const r = document.querySelector('.avatar-stage').getBoundingClientRect(); return document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2)?.className ?? null; })()"));
  console.log("pagina:", await text(".page-title"), "·", await text(".avatar-total"), "· nome:", await text(".avatar-name"), "·", await text(".avatar-island"), "·", await text(".avatar-info"));
  await shot("pagina-gattino");

  await click(".avatar-arrow.right");
  await sleep(900);
  console.log("dopo la freccia:", await text(".avatar-name"), "·", await text(".avatar-island"), "· pulsante:", await text(".avatar-choose"));
  await shot("pagina-pianty");

  // un trascinamento verso sinistra porta al vicino successivo: una sagoma senza nome. Il `mouse` delle prove non tiene premuto il tasto
  // mentre si muove, quindi il dito si simula con eventi del puntatore dentro la pagina.
  await js(`(async () => {
    const c = document.querySelector('.avatar-stage'); const r = c.getBoundingClientRect(); const y = r.top + r.height / 2;
    const at = (type, x) => c.dispatchEvent(new PointerEvent(type, { pointerId: 7, button: 0, buttons: type === 'pointerup' ? 0 : 1, clientX: x, clientY: y, bubbles: true }));
    at('pointerdown', r.left + r.width / 2 + 60);
    for (let i = 1; i <= 8; i++) { at('pointermove', r.left + r.width / 2 + 60 - i * 12); await new Promise((ok) => setTimeout(ok, 25)); }
    at('pointerup', r.left + r.width / 2 - 36);
  })()`);
  await sleep(1000);
  console.log("dopo il trascinamento:", await text(".avatar-name"), "·", await text(".avatar-island"), "·", await text(".avatar-remaining"), "·", await text(".avatar-promise"));
  const leaks = await js("['Porcellino','Ciccio','Riccio','Tartaruga'].filter((n) => document.querySelector('.card-root').textContent.includes(n))");
  console.log("nomi di chi non c'è nella pagina:", JSON.stringify(leaks));
  await shot("pagina-sagoma");

  // «Studia con Pianty» cambia compagno
  await click(".avatar-arrow.left");
  await sleep(900);
  await click(".avatar-choose");
  await sleep(1200);
  console.log("compagno:", settings.pet, "· info:", await text(".avatar-info"));
  await click(".page-header .back");
  await sleep(500);
  console.log("tornata alla scheda:", await js("!!document.querySelector('.avatar-row')"));
  await shot("scheda-dopo");
};
