// Le pagine della scheda: principale, timer, focus (con note), fermo, pausa.
module.exports = async ({ js, sleep, shot, timer, settings }) => {
  await sleep(1500);
  // principale, con un po' di studio registrato e un timer salvato
  const svc = timer();
  settings.addCustomTimer(40, "focus");
  await js("window.__ff.openCard()");
  await sleep(700);
  await shot("a-principale");
  // pagina dei timer
  await js("(() => { [...document.querySelectorAll('.card-root button')].find(b => b.getAttribute('aria-label') === 'Altri timer').click(); })()");
  await sleep(500);
  await shot("b-timer");
  await js("window.__ff.closeCard()");
  await sleep(300);
  // focus
  svc.run(() => svc.engine.startFocus(50, "Anatomia"));
  svc.engine.addNote("rivedere i nervi cranici");
  svc.engine.addNote("esercizio 4");
  await sleep(1500);
  await js("window.__ff.openCard()");
  await sleep(800);
  await shot("c-focus");
  svc.run(() => svc.engine.toggleFocusPause());
  await sleep(1200);
  await shot("d-fermo");
  await js("window.__ff.closeCard()");
  svc.run(() => svc.engine.stop());
  await sleep(300);
  // pausa
  svc.run(() => svc.engine.startBreak(5));
  await sleep(1500);
  await js("window.__ff.openCard()");
  await sleep(800);
  await shot("e-pausa");
  await js("window.__ff.closeCard()");
};
