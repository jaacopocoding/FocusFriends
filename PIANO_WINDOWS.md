# FocusFriends per Windows — piano di lavoro

Obiettivo: un'app per Windows **pari a quella per Mac**, in due uscite:

1. **Windows, prima uscita: tutto tranne il giardino** (compagni, timer, scheda, suoni, statistiche, sblocchi).
2. **Windows, seconda uscita: il giardino** (punti, negozio, prato, compagni nel prato).

Questo documento è un piano, non codice. Le stime sono grezze (giorni di lavoro continuo di una persona che sa
quello che fa): servono a dare un ordine di grandezza, non una scadenza.

## 0. Scelte di partenza

| Scelta | Proposta | Perché |
|---|---|---|
| Tecnologia | **Electron** (processo principale e interfaccia in TypeScript, HTML e CSS) | Il passaggio dei clic nelle zone trasparenti è già previsto (`setIgnoreMouseEvents` con `forward`), un solo linguaggio, e per provarlo su Windows basta Node. Pesa di più di Tauri (installer di decine di MB), ma su Windows la memoria a riposo è simile. **Gira anche sul Mac**: quasi tutto si sviluppa e si prova qui, e solo le parti che toccano Windows vanno provate su Windows. |
| Interfaccia | TypeScript con un framework leggero (Svelte), nella finestra di Electron | La scheda del Mac si ricostruisce da una fotografia dello stato (`MenuCardState`): è il modo di lavorare di un'interfaccia reattiva. |
| Dove sta il codice | Cartella `windows/` nello stesso repo; `assets/` condivisi | Le immagini, le frasi e i brani restano una copia sola. |
| Dati | Stessi file e stessi formati del Mac, in `%APPDATA%\FocusFriends\` | `sessioni.json` (v3), `profilo.json` (v1), `giardino.json` (v1). Le preferenze (`UserDefaults` sul Mac) diventano `impostazioni.json`. |
| Windows supportato | Windows 10 (22H2) e 11, x64; ARM dopo | Serve WebView2 (c'è già su Windows 11). |
| Lingua | Italiano, come sul Mac | Le frasi e i testi si copiano. |

Alternative scartate, e perché: **Tauri** (non ha il passaggio dei clic per pixel già pronto: va costruito, e richiede Rust e
gli strumenti di compilazione di Visual Studio; resta valida se l'installer piccolo diventa importante), C# nativo (solo
Windows, e io non potrei vedere niente di quello che scrivo), Swift su Windows (per la grafica non c'è niente di maturo),
web app (un compagno fuori dal browser non esiste).

*Storia della scelta:* la prima versione di questo piano proponeva Tauri; dopo aver controllato come si lasciano passare i
clic nelle zone trasparenti (Electron lo ha pronto, Tauri no) si è passati a Electron. L'ultima parola la ha la prova di M1.

## Cosa passa e cosa no

| Parte Mac | Righe | Sul Windows |
|---|---|---|
| Logica pura (registro, statistiche, timer, regole di sblocco, frasi) | ~2.100 | **Si riscrive** in TypeScript, con le stesse prove |
| Immagini (4 compagni, 36 oggetti, prato), frasi, 5 brani | — | **Si riusa** così com'è |
| Formati dei dati | — | **Si riusa** (compatibili con il Mac) |
| Interfaccia e sistema (AppKit, AVFoundation, ServiceManagement) | ~8.400 | **Si rifà** |
| Font Marker Felt, icone SF Symbols, suono «Glass» | — | **Si sostituiscono** (non esistono su Windows) |

### Dove va ogni file del Mac

| Mac | Windows |
|---|---|
| `SessionLog.swift` (registro, soggetti, note, statistiche, serie, CSV) | `core/sessionLog.ts`, `core/stats.ts` |
| `Profile`, `CustomTimers`, `BreakCycle`, `CompanionRewards` | `core/profile.ts`, `core/timers.ts`, `core/cycle.ts`, `core/rewards.ts` |
| `Chattiness`, `PhraseDeck`, `Quotes` | `core/phrases.ts` |
| `Pet.swift` | `data/pets.json` + `core/pet.ts` |
| `PetWindow`, `Walker` | `ui/pet/` (la finestra e i clic in `main/platform/`) |
| `Speaker`, `SpeechBubble` | `ui/bubble/` |
| `Pomodoro`, `TimerBubble`, `ExtendPrompt` | `core/pomodoro.ts`, `ui/clock/`, `ui/extend/` |
| `MenuController`, `MenuCard`, `MenuHeader`, `FocusScreenViews`, `PaperUI` | `ui/card/`, menu dell'area di notifica in `main/platform/` |
| `SubjectPrompt`, `ReflectionCard`, `IntroCard` | `ui/prompts/` |
| `DashboardWindow` | `ui/stats/` |
| `AmbientPlayer`, `MusicPlayer`, `AmbientSound`, `MusicLibrary` | `audio/` (AudioWorklet per i rumori) |
| `Garden*`, `GardenWindow` | `core/garden/`, `ui/garden/` — **seconda uscita** |
| `Migration.swift` (da Bonsy) | non serve |

## Come si lavora

- **Prove prima di tutto.** Le 332 prove del Mac (meno quelle del giardino) si portano in Vitest. In più, **prove di
  contratto**: gli stessi file di esempio (`tests/fixtures/`) passano dalla versione Swift e da quella TypeScript, e i
  risultati (totali, serie, punti, riepiloghi) devono essere uguali.
- **Il codice è diviso in quattro posti** (`windows/src/`): `core/` (logica pura, senza Electron: si prova con Node sul Mac),
  `main/` (processo principale: finestre, area di notifica, file, avvio al login; il codice che tocca Windows sta in
  `main/platform/`), `preload/` (il ponte sicuro) e `renderer/` (l'interfaccia). Tutto il resto si prova sul Mac.
- **Sicurezza di Electron**: l'interfaccia non tocca i file né il sistema; chiede al processo principale con messaggi
  precisi (`contextIsolation` acceso, niente Node nella pagina).
- **Per Windows serve una macchina vera o una virtuale** (Parallels o UTM con Windows 11 ARM, che esegue anche le app
  x64). Io non posso provarlo: ogni milestone che tocca Windows finisce con una schermata o un video che mi mandi.
  Per provare basta copiare la cartella nella macchina virtuale (cartella condivisa) e lanciare `npm start`: niente compilatori.
- **Un'azione alla volta, come al solito**: provo, ti mostro, commit in locale quando me lo chiedi, push con il tuo ok.
- **Da scaricare e installare** (te lo chiedo prima, una cosa alla volta): Node.js, i pacchetti (Electron, electron-builder,
  Svelte, Vitest), il software per la macchina virtuale, l'immagine di Windows, i font liberi.

## Prima uscita: tutto tranne il giardino

### M0 — Fondamenta (2–3 giorni)

- [~] Scegliere il font libero (OFL) più vicino a Marker Felt (candidati: Kalam, Patrick Hand, Itim) e il set di icone
      libero (candidato: Lucide) al posto delle icone di sistema. Prova affiancata alle schermate del Mac.
- [x] Suono di fine focus (al posto di «Glass»): generato da zero, quindi senza licenze (`windows/resources/fine-focus.wav`,
      due rintocchi di campana, 2,2 secondi). **Da ascoltare e approvare.**
- [x] Scrivere `FORMATI.md`: i tre file dei dati e le regole di lettura (versioni, file rovinato, file più nuovo in sola
      lettura, copia di sicurezza giornaliera, file del focus in corso), ricavati dal codice Swift.
- [x] Raccogliere i file di esempio in `tests/fixtures/` (18 cartelle: sessioni v0, v1, v2, v3, rovinate, più nuove, focus in corso, profilo,
      giardino, preferenze) **e i risultati attesi dal Mac** in `tests/fixtures/attesi/` (`tests/genera-attesi.sh`, sempre uguali a parità di codice).
- [~] Preparare l'ambiente: **fatto sul Mac** (Node 24, TypeScript 7.0.2, Electron 44.9.0, esbuild; progetto che si apre con `npm start`, sicurezza
      di Electron già impostata: `contextIsolation`, `sandbox`, niente Node nella pagina, protocollo `ff://` al posto di `file://`). **Manca la macchina virtuale con Windows**
      (e la prova lì).
- [x] Nome del pacchetto (`focusfriends-windows`) e cartella dati: `%APPDATA%\FocusFriends` su Windows; **sul Mac, quando si prova, una cartella di prova a parte** (mai quella dell'app per Mac).
      Identificatore dell'app (`com.jacopo.focusfriends`) da fissare con electron-builder (M10).

**Fatto quando:** una finestra vuota di Electron si apre sul Mac e su Windows, e `FORMATI.md` descrive tutto quello che il
codice Swift fa con i file.

### M1 — Il compagno sul desktop (4–6 giorni, il rischio più grosso)

Prima si prova la cosa più incerta: una finestra trasparente, sempre in primo piano, che lascia passare i clic dove è vuota.

- [~] **Prova a confronto**, con Pianty fermo e un fumetto finto:
  - A: una finestra piccola per il compagno, mossa dal processo principale a 30 volte al secondo (come sul Mac), con
    fumetto e orologio in finestre che la seguono;
  - B: **una sola finestra trasparente grande quanto l'area di lavoro**, in cui il compagno, il fumetto e l'orologio sono
    elementi della pagina; i clic passano dietro con `setIgnoreMouseEvents(true, { forward: true })` e la pagina, che continua
    a vedere il mouse, riaccende i clic solo quando il cursore è sopra un pixel non trasparente. Se non regge, piano di
    riserva dentro Electron: delimitare la zona cliccabile con la forma della finestra (`setShape`, se la versione la
    permette).
- [ ] Misure per scegliere: processore a riposo (meno del 2%), memoria con tutti i processi di Electron sommati (obiettivo sotto i 250 MB), clic che passano davvero nelle zone vuote, trascinamento
      fluido, comportamento con la barra delle applicazioni in basso, a lato, in alto e nascosta, con 100%, 150% e 200% di
      scala, con due schermi, e quando un'altra app va a schermo intero.
- [x] Mettere il compagno **sopra la barra delle applicazioni** (area di lavoro, non lo schermo intero), con i piedi sulla
      linea di terra (`groundFraction` di ogni personaggio).
- [x] Carico dei quattro personaggi da `data/pets.json` (tutti i campi di `Pet.swift`: immagini, misure, ombra, fotogrammi).
- [x] **Camminata** (`Walker`): passi, soste, specchio quando va a sinistra, rimbalzo ai bordi, mangia, dorme con gli
      «Zzz», saltelli; 30 volte al secondo mentre si muove, una al secondo quando è fermo o nascosto.
- [x] **Trascinamento** e disegno «sollevato» con il tremolio.
- [x] Area di notifica: icona del compagno, Nascondi/Mostra, Esci. Scelta del compagno (solo quelli sbloccati, vedi M8).
- [x] Preferenze di base in `impostazioni.json` (compagno, movimento acceso/spento).

**Stato (sul Mac):** scelta provata la **B** (una sola finestra trasparente grande quanto l'area di lavoro): il compagno cammina, si
solleva col mouse, parla, cambia con il menu dell'area di notifica; la pagina accende i clic solo sopra un pixel del disegno
(provato con eventi simulati, non ancora con il sistema vero). Misure sul Mac (Electron 44): processore a riposo sotto l'1% in
tutto, **memoria 460 MB sommando i quattro processi** (browser 208, GPU 103, pagina 107, utilità 43), cioè **sopra l'obiettivo di
250 MB**: da rimisurare su Windows e, se serve, ridurre (finestra per compagno più piccola, processo GPU spento, `--js-flags`).
Dati dei compagni **generati da `Pet.swift`** (`tools/genera-pets.sh` → `windows/data/pets.json`), con prova che gli stadi ricavati
in TypeScript sono uguali a quelli di Swift. Mancano, e vanno provati su Windows: clic che passano davvero, barra delle applicazioni
nei quattro lati e nascosta, 150% e 200%, due schermi (con B ci vuole **una finestra per schermo** e il passaggio del compagno
dall'una all'altra), app a schermo intero. Se B non regge, il piano di riserva è A.

**Fatto quando:** i quattro compagni camminano sopra la barra delle applicazioni su Windows 10 e 11, senza rubare clic e
senza consumare processore da fermi. La scelta A/B è scritta nel piano.

### M2 — Registro, statistiche e regole (5–7 giorni, quasi tutto sul Mac)

Solo logica, senza interfaccia. Ogni punto porta con sé le sue prove.

- [x] **Registro** (`SessionLog`): lettura e scrittura atomica di `sessioni.json` v3; migrazione da v0/v1/v2 con copia
      intatta in `backup/`; file più nuovo in sola lettura; file illeggibile mai sovrascritto; recupero delle sessioni
      leggibili e copia `sessioni.corrotto-…`; copia di sicurezza giornaliera (ultime 7); avvisi una volta sola.
- [x] **Focus in corso** (`in-corso.json`): scrittura ogni 30 secondi, recupero dopo una chiusura improvvisa (escludendo
      il tempo da fermo), pausa registrata.
- [x] Pulizia e unione delle materie, note di una riga (80 caratteri) e note del focus (40 da 160), ora «sull'orologio»
      (`localStart`) per i raggruppamenti.
- [x] **Statistiche** (`StudyStats`): periodi (giorno, settimana da lunedì, mese), riepiloghi con barre e materie,
      **serie di giorni con un giorno di ghiaccio** (`StudyStreak`, una volta ogni 7 giorni), frasi «quando rendi meglio»,
      incoraggiamenti, durata e testi in italiano, esportazione CSV (apice davanti ai campi che iniziano con `= + - @`,
      tab e ritorno a capo).
- [x] **Profilo** (nome, introduzione vista, compagni sbloccati, primo compagno), titoli personalizzati.
- [x] **Sblocco dei compagni** (`CompanionRewards`: 0, 20, 50, 100 «focus pieni» da 50 minuti), chi usava già l'app li ha tutti.
- [x] **Timer personalizzati** (`CustomTimers`: 1–180 minuti di focus, 1–60 di pausa, fino a 6 per tipo) e la matematica del
      quadrante (`TimerDialMath`).
- [x] **Ciclo della pausa lunga** (`BreakCycle`: quattro focus, 15 minuti, si azzera dopo 2 ore).
- [x] **Frasi**: file incluso, file dell'utente che ha la precedenza, mazzo mischiato senza ripetizioni, quattro
      frequenze (`Chattiness`), frase di riserva.
- [~] Porting delle prove (332 meno quelle del giardino) e **prove di contratto** Swift contro TypeScript sugli stessi file.
      Fatto: 109 prove in `windows/test/` (con `npm test` o `node --test test/*.test.ts`, senza installare niente) e le prove di
      contratto sulle 14 cartelle di esempio senza giardino, tutte uguali a quelle del Mac. Mancano il controllo dei tipi
      con `tsc` (serve installare TypeScript) e quello che va con i suoni (brani, suoni ambiente, M5).

**Fatto quando:** le prove di contratto danno gli stessi numeri del Mac su tutti i file di esempio e sui tuoi dati veri
(copiati in una cartella di prova, mai quelli veri).

### M3 — Il timer (5–7 giorni)

- [x] Il motore gira **nel processo principale** (o in una finestra sempre visibile): Chromium rallenta i timer delle
      pagine nascoste, e il timer non deve fermarsi quando le schede si chiudono.
- [x] Motore (`Pomodoro`): fine fissata sull'orologio (non sul conteggio), **pausa che sposta la fine**, finestra di 10
      secondi con «+5 minuti», minuti in più prima della scadenza e durante la pausa, «Termina e salva», «Elimina questo
      focus», focus interrotto che si registra comunque.
- [x] **Sleep del computer**: un salto di più di 10 secondi durante un focus conta come tempo da fermo (stessa regola del Mac).
- [x] Ciclo dei quattro focus e pausa lunga.
- [x] Suono di fine focus.
- [x] **Orologio** sotto il compagno (case scuro, schermo, cifre a sette segmenti): visibile nei primi 2 minuti, negli
      ultimi 5 e al passaggio del mouse, con la tendina di apertura.
- [x] «+5 minuti» accanto al compagno per 10 secondi (barra che si svuota).
- [x] **Crescita durante il focus**: Pianty cresce a cinque stadi, Ciccio nel nido, il Porcellino con la carota (che
      mangia a fine focus), il Gattino cammina. Dopo un «+5» resta all'ultimo stadio.
- [x] Il compagno mangia a fine focus, frase di fine focus e frase di pausa finita. **Senza giardino**: la frase non parla di punti.
- [x] Frequenza delle frasi più rara durante il focus.

**Stato (sul Mac):** il motore è in `core/pomodoro.ts` (24 prove, in `test/timer.test.ts`) e gira **nel processo principale**
(`main/timer.ts`, un battito ogni 0,2 s); la pagina riceve com'è il timer una volta al secondo o subito se succede qualcosa. Provati
davvero, con le quattro immagini che ne escono: avvio, orologio sotto il compagno che si apre come una tendina, compagno che si
alza per fargli posto e poi si riabbassa, crescita (Ciccio nel nido, il porcellino con la carota), «+5 minuti» a fine focus (la
barretta si svuota, il tocco prolunga e il focus si registra completo), fine del focus con il porcellino che mangia, pausa, registro
con materia e personaggio. I comandi per ora stanno nel menu dell'area di notifica (**Pomofocus**); la scheda arriva con M4. Il
suono è `resources/fine-focus.wav` (**da ascoltare**). Da provare su Windows: il suono, il computer che va in sleep durante un focus
(la regola dei 10 secondi è provata con il tempo simulato) e le misure di processore e memoria con il timer acceso.

**Fatto quando:** un focus da 25 minuti si può avviare, mettere in pausa, prolungare, interrompere e chiudere con il computer
messo in sleep, e la sessione registrata è identica a quella che farebbe il Mac.

### M4 — La scheda (6–8 giorni)

La scheda di carta si apre dall'icona nell'area di notifica (sotto l'icona) o dal compagno (di fianco, e lo segue).

- [x] Struttura a pagine e fotografia dello stato (`MenuCardState`), con aggiornamento leggero ogni secondo
      (`MenuCardLiveState`) e ricostruzione solo quando cambia fase o pausa.
- [x] **Pagina principale**: compagno nel cerchio (un tocco e parla), saluto con il nome, riga dei compagni con i
      lucchetti e la frase di quanto manca, durate 30/50/pausa e «Altri timer…», tre riquadri di oggi (minuti, focus,
      serie con il fiocco se ghiacciata), impostazioni rapide, «Esci».
- [x] **Pagina del quadrante** («Gira il timer»): pomodoro da trascinare, rotella un minuto alla volta, salvare e
      togliere i timer personali.
- [x] **Pagina del focus**: materia, orari, compagno, puntini «Focus N di 4», pomodoro con l'arco di avanzamento, +5,
      Ferma/Riprendi, «Termina e salva» da fermo, sottofondo con volume, **foglietto per le note**, elimina, ritorno al menu.
- [x] **Pagina della pausa** (variante verde): tempo, +5, Salta, «Nuovo focus · N min», le tre facce per l'ultimo focus.
- [x] Posizione e chiusura: clic fuori, Esc, segue il compagno e passa dall'altro lato ai bordi.
- [x] Il **menu completo** dall'area di notifica (tasto destro): sottomenu Pomofocus e timer personalizzati, frequenza
      delle frasi, movimento, nome, «Chiedi com'è andata», pausa lunga, frasi, avvio al login, esci.
- [x] Tutto accessibile da tastiera, con etichette per i lettori di schermo.

**Stato (sul Mac):** la scheda sta **dentro la finestra trasparente** (niente finestra in più: meno memoria): mentre è aperta la finestra
riceve i clic e la tastiera, un clic fuori o Esc la chiudono, e se sta accanto al compagno lo segue e passa dall'altro lato ai bordi.
Si apre con un clic sull'icona (sopra o sotto di lei, secondo dove sta la barra) o con il tasto destro sul compagno; il tasto destro
sull'icona dà il **menu completo** (Pomofocus con i timer personali, Suono ambiente, Musica, Frequenza delle frasi, Personaggio,
Movimento, «Chiedi com'è andata», Pausa lunga, «Modifica le frasi…», Mostra/Nascondi, Esci). Le quattro pagine ci sono (scheda,
«Gira il timer», focus, pausa) con le stesse parole e gli stessi disegni del Mac, fatti in SVG; i pulsanti sono veri (tastiera e
lettori di schermo), il quadrante si gira anche con la rotella e le frecce. **Niente Svelte**: la scheda si ricostruisce a ogni
cambio come sul Mac, e bastano TypeScript e il DOM. Icone: **Lucide** (ISC, in `tools/genera-icone.mjs`). Le icone di sistema, il
carattere e la musica che suona davvero arrivano con M0 (font) e M5 (suoni). Il pulsante «Giardino» non c'è (seconda uscita) e
«Statistiche» dice che arriva (M7). **Da provare su Windows:** passaggio del focus tra le finestre quando la scheda si apre e si
chiude, e la posizione rispetto all'icona con la barra in basso, a lato e in alto.

**Fatto quando:** da sola la scheda permette di fare un giro completo (scegliere materia, focus, note, pausa, voto).

### M5 — I suoni (4–6 giorni)

- [ ] **Rumori sintetizzati** (pioggia, rumore marrone, vento) in un `AudioWorklet`, con le stesse regole del Mac
      (dissolvenze di 2 secondi, anteprima breve alla scelta, volumi 10/25/40/60%).
- [ ] **Musica**: 5 brani inclusi (verificare che il formato si senta su Windows; altrimenti convertirli), cartella
      dell'utente (finestra di scelta, ricerca nelle sottocartelle, elenco in cache), coda mischiata che non riparte dal
      brano appena suonato.
- [ ] L'audio vive nella finestra sempre aperta, con `backgroundThrottling` spento: una finestra nascosta verrebbe rallentata e il suono scatterebbe.
- [ ] Solo durante un focus attivo (non in pausa); **un solo sottofondo alla volta**.
- [ ] Controlli sulla pagina del focus e sulla scheda.
- [ ] Se l'audio non parte, lo dice il compagno.

**Fatto quando:** la pioggia suona senza scatti per un'ora con il processore sotto il 5%, e passa a musica e viceversa senza buchi.

### M6 — Le schede collegate (3–4 giorni)

- [ ] **«Cosa studi adesso?»**: testo libero, fino a 6 materie recenti, «nessuna materia», indietro, ultima nota.
- [ ] **«Com'è andata?»**: tre facce e una riga facoltativa; non prende la tastiera; sparisce da sola; salvando solo la nota
      non cancella il voto già dato.
- [ ] **Introduzione**: nome e primo compagno (quattro bottoni).

**Fatto quando:** il primo avvio, un focus completo e un focus interrotto danno gli stessi dati che darebbe il Mac.

### M7 — Le statistiche (6–8 giorni)

- [ ] Finestra con le schede **Oggi / Settimana / Mese**, frecce tra i periodi, pulsante «‹ Menu».
- [ ] Riepilogo: totale in grande, focus completi e interrotti, barre sottili, barra a segmenti con le materie e la legenda,
      serie (con il fiocco), come è andata, frasi su quando rendi meglio.
- [ ] **Tendina «Mostra le sessioni»**: striscia del giorno, righe con ora, materia, nota, faccia e durata; per settimana e
      mese le sessioni sotto il giorno; la pagina scorre.
- [ ] **Modifica di una sessione** (materia, «applica a tutte», nota, voto, note del focus) ed eliminazione.
- [ ] **Esporta CSV** (finestra di salvataggio) e **Cancella tutto…** (con conferma).

**Fatto quando:** sugli stessi dati i numeri e i testi delle statistiche sono uguali a quelli del Mac.

### M8 — Sblocchi e nome (2–3 giorni)

- [ ] Annuncio dello sblocco a fine focus, scelta del primo compagno, compagni bloccati che non si possono scegliere.
- [ ] Il nome nei titoli («Le statistiche di …»), «Il tuo nome…».
- [ ] Modalità sviluppatore (`developerMode` nelle impostazioni) che sblocca tutto.

### M9 — Sistema e rifiniture (3–5 giorni)

- [ ] **Una sola copia dell'app aperta** (`requestSingleInstanceLock`): un doppio avvio non deve mai toccare i dati due volte.
- [ ] Avvio al login (`setLoginItemSettings`) con la voce nel menu.
- [ ] Più schermi, scala del 100%–200%, barra delle applicazioni in qualunque lato, tema scuro di Windows (le schede sono sempre chiare).
- [ ] Problemi con i dati detti dal compagno (file illeggibile, scrittura fallita), una volta sola.
- [ ] Chiusura pulita: un focus in corso si registra come interrotto, come sul Mac.
- [ ] Prestazioni: a riposo sotto il 2% di processore e sotto i 250 MB di memoria (tutti i processi di Electron sommati: è
      la parte più pesante rispetto al Mac).
- [ ] Arresti inattesi: un file di registro dell'app (senza dati personali) per capire cosa è successo.

### M10 — Installazione e distribuzione (3–4 giorni)

- [ ] Programma di installazione (NSIS, con electron-builder), icona, versione.
- [ ] **Firma del codice**: senza, Windows mostra l'avviso SmartScreen. Scelta da fare (certificato a pagamento, o servizio
      di firma, o niente e una nota nel README come per il Mac).
- [ ] **CI su GitHub** (macchina Windows): compila, lancia le prove e produce l'installer a ogni push. (È anche il
      punto F-07 della revisione dell'architettura, fatto per tutti e due i sistemi.)
- [ ] Sezione Windows nel README, note di rilascio, tag e release con l'installer e il suo SHA-256.
- [ ] Come si aggiorna (a mano, scaricando dalla pagina delle release; aggiornamenti automatici con electron-updater solo dopo, se serve).

### M11 — Parità e prove su Windows (4–5 giorni)

Lista di controllo, funzione per funzione, contro l'app per Mac:

- [ ] Ogni voce di `README.md` («Cosa fa») e di `ARCHITECTURE.md` §3 ha il suo equivalente o una nota su perché no.
- [ ] Windows 10 e 11, x64 e ARM, 100% / 150% / 200%, uno e due schermi, barra delle applicazioni ovunque.
- [ ] Sleep e risveglio, chiusura del coperchio, cambio di fuso orario, ora legale.
- [ ] App a schermo intero (il compagno non deve restare sopra a un gioco o a un video), cambio di desktop virtuale.
- [ ] Una giornata intera d'uso vero, e i dati riletti dall'app per Mac.

**Fine della prima uscita:** versione 1 per Windows, **senza giardino**. Durante la prima uscita il pulsante «Giardino» non
c'è nella scheda e nel menu.

## Seconda uscita: il giardino (8–12 giorni)

Si fa dopo, perché riusa tutto il resto (schede, finestre, immagini, dati) e non blocca nessuna delle altre funzioni.

- [ ] **G1 — Logica** (`GardenCatalog`, `Garden`, `GardenPoints`): catalogo da 36 oggetti, prezzi, punti con il
      moltiplicatore della serie, oggetti sbloccati e copie nel prato, `giardino.json` con le stesse regole di file
      rovinato e più nuovo. Prove di contratto contro il Mac (stessi punti sugli stessi dati).
- [ ] **G2 — Immagini**: prato e oggetti (già ritagliati in `assets/giardino/`).
- [ ] **G3 — La finestra del giardino**: prato, oggetti più piccoli verso il fondo, **trascinamento libero**, clic sul disegno
      vero (non sul rettangolo), compagni sbloccati che parlano, tasto destro per togliere, Esc.
- [ ] **G4 — Il negozio**: pannello con tre schede, due tocchi per sbloccare, oggetti gratuiti, messaggi dei punti che mancano.
- [ ] **G5 — Punti dappertutto**: chip del moltiplicatore e dei punti, frase di fine focus con i punti, «Cancella tutto…» che
      toglie anche il giardino, scala su schermi stretti.
- [ ] **G6 — Prove su Windows e seconda uscita**: versione 1.1 con il giardino.

## Cose che possono andare storte (e come si scoprono presto)

| Rischio | Quando lo vediamo | Cosa faremo |
|---|---|---|
| La finestra trasparente intercetta i clic o consuma troppo | M1, prima di tutto il resto | Cambiare strategia (una finestra piccola per compagno) o i limiti di aggiornamento |
| App a schermo intero (giochi, video): il compagno resta sopra, o sparisce | M1 e M11 | Nascondersi quando c'è un'app a schermo intero |
| Barra delle applicazioni nascosta o a lato | M1 | Calcolare l'area di lavoro a ogni cambio |
| Scala dello schermo diversa tra due monitor | M1 e M11 | Una finestra per schermo, o passare ai pixel fisici |
| Memoria alta (Electron) | M1 e M9 | Una sola finestra trasparente, schede create solo quando servono, meno processi |
| Timer o suoni rallentati in una finestra nascosta | M3 e M5 | Motore nel processo principale, `backgroundThrottling` spento |
| La sintesi dei rumori scatta | M5 | Passare il lavoro a un `AudioWorklet` e ridurre i calcoli per campione |
| Il computer va in sleep durante un focus | M3 | Stessa regola dei 10 secondi del Mac, provata davvero |
| Avviso SmartScreen scoraggia chi scarica | M10 | Decidere sulla firma; nota chiara nel README |
| Il font di sostituzione cambia l'aspetto delle schede | M0 | Prova affiancata prima di scrivere le schede |
| Le prove di contratto trovano differenze con il Mac | M2 | Si corregge la versione sbagliata e si aggiunge la prova |
| Due copie dell'app sugli stessi dati | M9 | Istanza unica (è già successo una volta sul Mac, per un errore di una prova) |

## Stime riassunte

| Pezzo | Giorni di lavoro |
|---|---|
| M0 Fondamenta | 2–3 |
| M1 Il compagno sul desktop | 4–6 |
| M2 Registro, statistiche e regole | 5–7 |
| M3 Il timer | 5–7 |
| M4 La scheda | 6–8 |
| M5 I suoni | 4–6 |
| M6 Le schede collegate | 3–4 |
| M7 Le statistiche | 6–8 |
| M8 Sblocchi e nome | 2–3 |
| M9 Sistema e rifiniture | 3–5 |
| M10 Installazione e distribuzione | 3–4 |
| M11 Parità e prove | 4–5 |
| **Prima uscita (senza giardino)** | **47–66, cioè circa 9–13 settimane di lavoro continuo** |
| Seconda uscita: il giardino | 8–12 |

Da usare con cautela: sono stime, e gli imprevisti sono quasi tutti in M1, M5 e M9. La prima settimana ne dirà di più di
qualunque numero scritto qui.

## Cosa mi serve da te per cominciare

1. **Electron va bene?** L'abbiamo scelto per il passaggio dei clic e per avere un solo linguaggio; Tauri resta l'alternativa.
2. **Una macchina con Windows** (anche virtuale). Quale?
3. **Il permesso di installare gli strumenti**, una cosa alla volta.
4. **Il font**: ti mostro tre candidati accanto a una schermata del Mac e scegli.
5. **Firma del codice**: decidere più avanti, ma prima di M10.
