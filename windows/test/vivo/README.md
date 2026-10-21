# Prove dal vivo

Copioni che provano l'**app vera di Electron** (non solo la logica, che ha già le sue prove in `../*.test.ts`): finestra trasparente, clic,
scheda, finestre di dialogo, suoni, statistiche, schermi, sleep. Ogni copione fa partire l'app con la variabile `FF_SELFTEST`, riceve gli strumenti
descritti in `../../ARCHITECTURE.md` §5.3 (la pagina, il timer, le impostazioni, il mouse e la tastiera simulati, le schermate, le misure) e **scrive quello
che osserva**: sta a una persona leggere il risultato e guardare le schermate. Non sono prove che passano o falliscono da sole.

## Come si lancia

```bash
cd windows
npm install                              # una volta
test/vivo/esegui.sh timer.cjs            # compila, apre l'app, esegue il copione, stampa cosa ha visto
test/vivo/esegui.sh statistiche.cjs 100  # il secondo numero è il tempo massimo in secondi (default 90)
test/vivo/misure.sh riposo               # memoria e processore a riposo
```

Alla fine il programma dice dove sono i risultati: una cartella nuova in `$TMPDIR` (`ff-vivo.XXXXXX`) con le schermate (`*.png` e `*-ridotto.png`,
queste ultime solo se c'è Python con Pillow), `log.txt` (l'uscita dell'app), `build.txt` e `data/`, la cartella dei dati di quella prova
(`sessioni.json`, `profilo.json`, `registro-app.log`…).

**I dati veri non si toccano.** La cartella dei dati sta sempre dentro la cartella dei risultati, che si crea da zero: se esiste già (con `FF_OUT`) il
programma si ferma e non cancella niente. Mai usare la cartella dei dati dell'app per Mac o `%APPDATA%\FocusFriends`.

Sono scritti per il Mac (e Linux); su Windows servono Git Bash o WSL. Sul Mac non c'è `timeout`: un sorvegliante chiude l'app se il copione si pianta.

## Le variabili

| Variabile | A cosa serve |
|---|---|
| `FF_OUT` | la cartella dei risultati (non deve esistere) |
| `FF_IMPOSTAZIONI` | il contenuto di `impostazioni.json` (default `{}`) |
| `FF_PROFILO` | il contenuto di `profilo.json` (default: introduzione già vista) |
| `FF_INTRO=1` | non scrivere `profilo.json`: compare la scheda di benvenuto |
| `FF_APP` | l'app da aprire (default: questa cartella; per un pacchetto, il suo `app.asar`) |
| `FF_FAKE_DISPLAYS` | schermi inventati, un elenco JSON di `{id, primary, bounds, workArea}` (per `schermi.cjs`) |
| `FF_PROVA_MUSICA` | una cartella con qualche file audio (per `musica.cjs`) |

Le variabili `FF_SELFTEST…` le imposta il programma stesso. `FF_NO_LOCK`, `FF_FAKE_DISPLAYS`, `FF_SELFTEST_SAVE` e `FF_SELFTEST_CONFIRM` funzionano solo
perché `FF_SELFTEST` è acceso: in uso normale l'app non le legge.

## I copioni

| Copione | Cosa guarda | Note |
|---|---|---|
| `timer.cjs` | un focus: avvio, +5, ferma e riprendi, stop; posizione, orologio, crescita | misure |
| `focus-finito.cjs` | un focus di 1 minuto che finisce da solo: pausa, frasi, sessione salvata | ≈ 75 s |
| `proroga.cjs` | la scadenza e il «+5 minuti» con un clic vero | ≈ 70 s |
| `scheda.cjs`, `scheda-pagine.cjs` | la scheda aperta e chiusa; le pagine principale, timer, focus, fermo, pausa | schermate |
| `scheda-clic.cjs` | clic e tasti veri sulla scheda: Esc, Frasi, durate, ferma/riprendi, note | |
| `materia.cjs` | «Cosa studi adesso?»: Esc, Invio, materia recente, senza materia | |
| `introduzione.cjs` | la scheda di benvenuto: nome e primo compagno | `FF_INTRO=1` |
| `riflessione.cjs`, `riflessione-saltata.cjs` | «Com'è andata?»: faccia, nota, Salta | la prima ≈ 75 s |
| `sblocchi.cjs` | compagni bloccati e sbloccati, nome, titolo della finestra delle statistiche | |
| `statistiche.cjs` | periodi, modifica, esporta CSV, elimina, «Cancella tutto» | usa le variabili di prova |
| `salvataggio.cjs` | quali focus finiscono nelle statistiche (sotto il minuto no, dopo sì) | ≈ 2 minuti |
| `compagni.cjs` | cambio di compagno, movimento acceso e spento | misure |
| `trascinamento.cjs` | clic che passano sul vuoto, trascinamento in aria | schermate |
| `ancora.cjs` | la scheda ancorata all'icona (barra in basso e in alto) | |
| `schermi.cjs` | due schermi finti: spostamento, trascinamento oltre il bordo, schermo scollegato | `FF_FAKE_DISPLAYS` |
| `audio.cjs`, `audio-guasto.cjs`, `audio-nascosto.cjs` | pioggia, vento, marrone e musica; audio che non parte; compagno nascosto | il volume è basso: suona davvero |
| `musica.cjs` | una cartella di musica: brano dopo brano, cartella che sparisce | `FF_PROVA_MUSICA` |
| `sleep.cjs` | sleep e risveglio simulati con pioggia e musica | |
| `chiusura.cjs` | chiusura con un focus in corso: in `data/sessioni.json` deve restare come interrotto | ≈ 70 s |
| `sicurezza.cjs` | niente navigazione verso il web, niente finestre nuove, niente permessi | |
| `hai-finito.cjs` | «Hai finito «…»?» a fine focus: due focus da 1 minuto partiti da una voce; con le facce e senza; «Fatta» segna la voce, «Non ancora» la lascia | ≈ 2 minuti e mezzo |
| `dafare.cjs` | «Da fare»: pagina vuota, il «+» e «Nuova cosa» (nome, scadenza, materia, calendario, Esc, nome vuoto), «Modifica» toccando una voce con il titolo lungo, riga sotto il mouse, voci fatte, il ▶ che porta al quadrante e fa partire il focus con la materia (e, senza materia, apre «Cosa studi adesso?»), il fumetto del promemoria | schermate della sola scheda |
| `pacchetto.cjs` | l'app impacchettata: compagno, carattere, scheda e brani si caricano dall'asar | `FF_APP=<…>/app.asar` |

Un copione è un file `.cjs` che esporta una funzione `async (strumenti) => { … }`: per scriverne uno nuovo si parte da `timer.cjs`.
**Se l'interfaccia cambia, qualche copione può diventare vecchio**: succede (`scheda-clic.cjs` non conosceva «Cosa studi adesso?»); si aggiorna.
