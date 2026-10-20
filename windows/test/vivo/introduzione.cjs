// La scheda «Come ti chiami e chi ti fa compagnia»: nome, primo compagno, profilo scritto (serve FF_INTRO=1 nel lancio).
const fs = require("fs"), path = require("path");
module.exports = async ({ js, sleep, shot, mouse, settings, timer, interactions }) => {
  const rect = async (selector) => JSON.parse(await js(`(() => { const e = document.querySelector(${JSON.stringify(selector)}); if (!e) return 'null'; const r = e.getBoundingClientRect(); return JSON.stringify({x: r.left + r.width / 2, y: r.top + r.height / 2}); })()`));
  const click = async (selector) => { const r = await rect(selector); if (!r) { console.log("non trovato:", selector); return; } mouse("mouseMove", r.x, r.y); await sleep(60); mouse("mouseDown", r.x, r.y); await sleep(40); mouse("mouseUp", r.x, r.y); await sleep(250); };
  await sleep(2500);
  console.log("intro aperta?", await js("window.__ff.modalOpen()"));
  await shot("intro");
  await js("(() => { const i = document.querySelector('.modal input'); i.focus(); i.value = '  Marco   Rossi '; })()");
  await click('.companion-choice[aria-label="Gattino"]');
  await shot("intro-gattino");
  await click(".pill-action");
  await sleep(800);
  const profile = JSON.parse(fs.readFileSync(path.join(process.env.FF_DATA_DIR, "profilo.json"), "utf8"));
  console.log("profilo:", JSON.stringify(profile));
  console.log("compagno:", settings.pet, "chiusa?", !(await js("window.__ff.modalOpen()")));
};
