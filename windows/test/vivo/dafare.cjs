// «Da fare»: la pagina vuota, una voce scritta nella scheda (con scadenza e materia), il calendario, la lista, una riga sotto il
// mouse, le voci fatte, «Inizia un focus» con la materia già scritta e il fumetto del compagno. Schermate della sola scheda.
const fs = require("fs"), path = require("path");

module.exports = async ({ js, sleep, mouse, key, timer, card, win, settings }) => {
  const out = process.env.FF_SELFTEST_OUT;
  // Niente frasi spontanee: il promemoria lo si chiede alla fine, e non deve averlo già detto il compagno da solo.
  settings.phraseFrequency = "never";
  const svc = timer();
  const day = (offset) => {
    const d = new Date();
    d.setHours(12, 0, 0, 0);
    d.setDate(d.getDate() + offset);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  };
  const click = (label, index = 0) => js(`(() => {
    const all = [...document.querySelectorAll('[aria-label]')].filter((e) => e.getAttribute('aria-label') === ${JSON.stringify(label)});
    const target = all[${index}];
    if (!target) return false;
    target.click();
    return true;
  })()`);
  const rect = async (selector, index = 0) => JSON.parse(await js(`(() => {
    const e = document.querySelectorAll(${JSON.stringify(selector)})[${index}];
    if (!e) return 'null';
    const r = e.getBoundingClientRect();
    return JSON.stringify({ x: Math.round(r.left), y: Math.round(r.top), width: Math.round(r.width), height: Math.round(r.height) });
  })()`));
  /** Una schermata della sola scheda (con un po' di margine). */
  const shotCard = async (name, selector = ".card-root") => {
    const r = await rect(selector);
    if (!r) { console.log("niente da fotografare:", name); return; }
    const box = { x: Math.max(r.x - 10, 0), y: Math.max(r.y - 10, 0), width: r.width + 20, height: r.height + 20 };
    const image = await win.webContents.capturePage(box);
    fs.writeFileSync(path.join(out, `${name}.png`), image.toPNG());
  };

  // Le materie recenti vengono dalle sessioni: ne scrivo quattro (finte) nella cartella di prova.
  const now = Date.now();
  for (const [i, subject] of ["Fisiologia", "Anatomia", "Analisi", "Fisica"].entries()) {
    svc.log.add({ start: now - (5 - i) * 3_600_000, seconds: 3000, plannedMinutes: 50, completed: true, subject });
  }
  await sleep(1500);

  await js("window.__ff.openCard()");
  await sleep(700);
  console.log("riga «Da fare» trovata:", await click("Da fare"));
  await sleep(500);
  await shotCard("1-vuota");

  // «+»: la pagina «Nuova cosa» (il campo del nome è già attivo).
  console.log("«+» trovato:", await click("Nuova cosa"));
  await sleep(400);
  console.log("titolo:", await js("document.querySelector('.page-title').textContent"), "| campo del nome attivo:", await js("document.activeElement && document.activeElement.className"));
  console.log("«Aggiungi» spento con il nome vuoto:", await js("document.querySelector('.todo-save').classList.contains('off')"));
  await shotCard("2-nuova-vuota");
  await js(`(() => { const i = document.querySelector('.todo-name'); i.focus(); i.value = 'Rileggere gli appunti di chimica'; i.dispatchEvent(new Event('input', { bubbles: true })); })()`);
  await click("Domani");
  await sleep(200);
  await click("Fisica");
  await sleep(200);
  console.log("materia dal chip:", await js("document.querySelector('.todo-subject-input').value"), "| «Aggiungi» acceso:", await js("!document.querySelector('.todo-save').classList.contains('off')"));
  await shotCard("3-nuova-compilata");
  await click("Scegli…");
  await sleep(300);
  await shotCard("4-calendario");
  await click("Scegli…");
  await sleep(200);
  // Esc in un campo: si torna alla lista senza salvare (e la scheda resta aperta).
  key("Escape");
  await sleep(400);
  console.log("dopo Esc: lista?", await js("document.querySelector('.todo-plus') !== null"), "| scheda aperta?", await js("window.__ff.cardOpen()"), "| voci:", await js("document.querySelectorAll('.todo-row').length"));
  await click("Nuova cosa");
  await sleep(300);
  console.log("il modulo riparte vuoto:", await js("document.querySelector('.todo-name').value === ''"));
  await js(`(() => { const i = document.querySelector('.todo-name'); i.focus(); i.value = 'Rileggere gli appunti di chimica'; i.dispatchEvent(new Event('input', { bubbles: true })); })()`);
  await click("Domani");
  await sleep(200);
  await click("Fisica");
  await sleep(200);
  await js(`(() => { const i = document.querySelector('.todo-name'); i.focus(); i.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true })); })()`);
  await sleep(600);
  console.log("dopo Invio: lista?", await js("document.querySelector('.todo-plus') !== null"), "| voci:", await js("[...document.querySelectorAll('.todo-title')].map((e) => e.textContent).join(' | ')"));
  // Il nome vuoto non salva.
  await click("Nuova cosa");
  await sleep(300);
  await click("Aggiungi");
  await sleep(300);
  console.log("nome vuoto: resto nel modulo?", await js("document.querySelector('.todo-name') !== null"));
  await click("Annulla");
  await sleep(300);

  // Altre voci, dal processo principale (come se fossero state scritte prima).
  const add = (text, due, subject = null) => card.command({ name: "todoAdd", text, due, subject });
  add("Consegnare il modulo della borsa", day(-1));
  add("Riassunto del capitolo 7", day(0), "Anatomia");
  add("Prenotare l'esame", day(0), "Fisiologia");
  add("Relazione di laboratorio", day(5), "Fisica");
  add("Cercare un libro per Storia", null);
  add("Scaricare le dispense", null, "Chimica");
  await js("window.__ff.closeCard()");
  await sleep(300);
  await js("window.__ff.openCard()");
  await sleep(600);
  await click("Da fare");
  await sleep(500);
  console.log("gruppi:", await js("[...document.querySelectorAll('.todo-group')].map((e) => e.textContent).join(' | ')"));
  console.log("scadenze:", await js("[...document.querySelectorAll('.todo-due')].map((e) => e.textContent).join(' | ')"));
  await shotCard("4b-lista");

  // Toccare il testo di una voce: si apre «Modifica» già compilato.
  const longTitle = "Preparare almeno due video lezione sulle applicazioni del capitolo di elettronica";
  await js("window.__ff.closeCard()");
  add(longTitle, day(1), "Elettronica");
  await sleep(300);
  await js("window.__ff.openCard()");
  await sleep(500);
  await click("Da fare");
  await sleep(500);
  await shotCard("5-lista-titolo-lungo");
  console.log("titolo lungo: altezza della riga", await js("(() => { const t = [...document.querySelectorAll('.todo-title')].find((e) => e.textContent.startsWith('Preparare almeno')); return Math.round(t.getBoundingClientRect().height); })()"), "px (due righe)");
  console.log("«Modifica» trovato:", await click("Modifica: " + longTitle));
  await sleep(400);
  console.log("modulo:", await js("document.querySelector('.page-title').textContent"), "| nome:", await js("document.querySelector('.todo-name').value.slice(0, 30)"), "| materia:", await js("document.querySelector('.todo-subject-input').value"));
  await shotCard("6-modifica");
  await js(`(() => { const i = document.querySelector('.todo-name'); i.value = 'Preparare due video lezione (versione corta)'; i.dispatchEvent(new Event('input', { bubbles: true })); })()`);
  await click("Salva");
  await sleep(700);
  console.log("dopo «Salva»:", await js("[...document.querySelectorAll('.todo-title')].map((e) => e.textContent).find((t) => t.startsWith('Preparare'))"));

  // Una riga sotto il mouse: compaiono ▶ e ×.
  const row = await rect(".todo-row", 2);
  mouse("mouseMove", row.x + row.width / 2, row.y + row.height / 2);
  await sleep(300);
  console.log("pulsanti a vista sotto il mouse:", await js("getComputedStyle(document.querySelectorAll('.todo-row .todo-actions')[2]).display"));
  await shotCard("7-riga-sotto-il-mouse");

  // L'ultima voce («Scaricare le dispense») è fatta; si vedono le fatte.
  const checks = Number(await js("document.querySelectorAll('[aria-label=\"Segna come fatta\"]').length"));
  await click("Segna come fatta", checks - 1);
  await sleep(500);
  await click("Mostra le fatte");
  await sleep(400);
  await shotCard("8-fatte");
  console.log("dafare.json:\n" + fs.readFileSync(path.join(process.env.FF_DATA_DIR, "dafare.json"), "utf8"));

  // «Inizia un focus» da una voce con la materia: «Cosa studi adesso?» ce l'ha già scritta.
  const withSubject = await rect(".todo-row", 1);
  mouse("mouseMove", withSubject.x + withSubject.width / 2, withSubject.y + withSubject.height / 2);
  await sleep(300);
  console.log("«Inizia un focus» sulla riga:", await js("document.querySelectorAll('.todo-row')[1].querySelector('.todo-title').textContent"));
  await js("document.querySelectorAll('.todo-row')[1].querySelector('.todo-play').click()");
  await sleep(900);
  console.log("scheda chiusa?", !(await js("window.__ff.cardOpen()")), "materia nel campo:", await js("(document.querySelector('.modal input') || {}).value"));
  await shotCard("9-materia-gia-scritta", ".modal");
  key("Escape");
  await sleep(400);

  // Il fumetto: c'è una scadenza di oggi, quindi la prossima frase è il promemoria.
  await js("window.__ff.say()");
  await sleep(1500);
  console.log("fumetto:", await js("(document.querySelector('.bubble .text') || document.querySelector('.bubble') || {}).textContent"));
  await shotCard("10-fumetto", ".bubble");
  await js("window.__ff.say()");
  await sleep(1500);
  console.log("frase dopo (non più il promemoria):", await js("(document.querySelector('.bubble .text') || document.querySelector('.bubble') || {}).textContent"));
};
