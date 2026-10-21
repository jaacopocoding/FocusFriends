// Le frasi «di contesto» (dura circa 2 minuti): il saluto dell'avvio alla prima frase spontanea, il saluto al risveglio (e quando tace),
// e il traguardo a fine focus (tre giorni di fila), detto dopo la frase di fine focus senza coprirla.
module.exports = async ({ js, sleep, shot, timer, settings, remarks }) => {
  const svc = timer();
  const bubble = () => js("(document.querySelector('.bubble .text') || document.querySelector('.bubble') || {}).textContent || null");
  // Passando da «Mai» a un'altra frequenza e ritorno il fumetto sparisce (e le frasi spontanee non partono).
  const clear = async () => { settings.phraseFrequency = "rarely"; await sleep(100); settings.phraseFrequency = "never"; await sleep(500); };
  const waitForBubble = async (seconds) => {
    for (let i = 0; i < seconds * 2; i += 1) { const text = await bubble(); if (text) return text; await sleep(500); }
    return null;
  };

  await sleep(1500);
  settings.phraseFrequency = "never";
  await clear();

  // 1) «Fai parlare»: la prima frase è il saluto dell'avvio, la seconda una del mazzo
  await js("window.__ff.say()");
  await sleep(600);
  console.log("1ª frase:", await bubble());
  await shot("1-saluto");
  await clear();
  await js("window.__ff.say()");
  await sleep(600);
  console.log("2ª frase (dal mazzo):", await bubble());
  await clear();

  // 2) il risveglio: con «Mai» tace, con meno di un'ora tace, altrimenti «Rieccoti!…» dopo 5 secondi
  remarks.wake(7200);
  await sleep(7500);
  console.log("risveglio con «Mai» (deve essere vuoto):", await bubble());
  settings.phraseFrequency = "rarely";
  await clear();
  settings.phraseFrequency = "rarely";
  remarks.wake(1800);
  await sleep(7500);
  console.log("risveglio dopo mezz'ora (deve essere vuoto):", await bubble());
  remarks.wake(7200);
  console.log("risveglio dopo due ore, subito:", await bubble());
  console.log("…e dopo 6 secondi:", await waitForBubble(8));
  await shot("2-risveglio");
  await clear();

  // 3) il traguardo: due giorni di fila già fatti, un focus di 1 minuto oggi → «Tre giorni di fila!»
  const day = 24 * 3600_000;
  svc.log.add({ start: Date.now() - 2 * day, seconds: 3000, plannedMinutes: 50, completed: true, subject: "Anatomia" });
  svc.log.add({ start: Date.now() - day, seconds: 3000, plannedMinutes: 50, completed: true, subject: "Anatomia" });
  svc.run(() => svc.engine.startFocus(1, "Anatomia"));
  await sleep(2000);
  remarks.wake(7200);
  await sleep(7500);
  console.log("risveglio durante un focus (deve essere vuoto):", await bubble());
  await sleep(52000);
  console.log("fase prima della fine:", svc.snapshot().phase);
  const seen = [];
  for (let i = 0; i < 70; i += 1) {
    const text = await bubble();
    if (text && seen[seen.length - 1] !== text) { seen.push(text); console.log(`  +${(i * 0.5).toFixed(1)} s dopo:`, text); if (/giorni di fila/.test(text)) await shot("3-traguardo"); }
    await sleep(500);
  }
  console.log("frasi dette dopo il focus, nell'ordine:", JSON.stringify(seen));
  console.log("«Tre giorni di fila!» detta:", seen.includes("Tre giorni di fila!"), "| dopo la frase di fine focus, non sopra:", seen.length >= 2 && seen[seen.length - 1] === "Tre giorni di fila!" || seen.indexOf("Tre giorni di fila!") > 0);
  svc.run(() => svc.engine.stop());
};
