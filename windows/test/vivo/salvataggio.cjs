// Quali focus finiscono nelle statistiche: sotto il minuto no, finiti o interrotti dopo un minuto sì (dura circa 2 minuti).
const fs = require("fs");
module.exports = async ({ js, sleep, timer, stats, shot }) => {
  const out = process.env.FF_SELFTEST_OUT;
  const file = `${process.env.FF_DATA_DIR}/sessioni.json`;
  const svc = timer();
  const saved = () => { try { return JSON.parse(fs.readFileSync(file, "utf8")).sessions.map((s) => ({ materia: s.subject ?? null, secondi: s.seconds, previsti: s.plannedMinutes, completo: s.completed, compagno: s.pet ?? null, inizioLocale: s.localStart })); } catch { return "nessun file"; } };
  await sleep(1800);

  // 1. un focus interrotto dopo 20 secondi: sotto il minuto non si registra
  svc.run(() => svc.engine.startFocus(5, "Troppo corto"));
  await sleep(20000);
  svc.run(() => svc.engine.stop());
  await sleep(1500);
  console.log("1) interrotto a 20 s ->", JSON.stringify(saved()), "(deve essere vuoto)");

  // 2. un focus da 1 minuto lasciato finire: completo
  svc.run(() => svc.engine.startFocus(1, "Finito"));
  console.log("   focus da 1 minuto avviato, aspetto la fine e i 10 secondi del «+5»...");
  await sleep(74000);
  console.log("2) finito da solo ->", JSON.stringify(saved()), "| fase ora:", svc.snapshot().phase);

  // 3. un focus interrotto dopo il minuto: registrato come interrotto
  svc.run(() => svc.engine.stop());       // chiude la pausa che è partita da sola
  await sleep(1000);
  svc.run(() => svc.engine.startFocus(5, "Interrotto"));
  await sleep(64000);
  svc.run(() => svc.engine.stop());
  await sleep(1500);
  const after = saved();
  console.log("3) interrotto a 64 s ->", JSON.stringify(after));

  // 4. le statistiche vere (la finestra), con quello che ha scritto il timer
  stats.show("day");
  for (let i = 0; i < 40 && !(stats.window && !stats.window.isDestroyed()); i += 1) await sleep(100);
  await sleep(1500);
  const text = await stats.window.webContents.executeJavaScript("document.body.innerText");
  console.log("4) statistiche (Oggi), testo visibile:\n" + text.split("\n").map((l) => l.trim()).filter(Boolean).join(" | "));
  const image = await stats.window.webContents.capturePage();
  fs.writeFileSync(`${out}/statistiche-oggi.png`, image.toPNG());
};
