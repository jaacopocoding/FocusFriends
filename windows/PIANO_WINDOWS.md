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

(La mappa del piano, scritta prima di cominciare: i nomi veri dei file sono poi venuti diversi, per esempio `core/log.ts`, `core/pets.ts` e `renderer/` al posto di `ui/`. La struttura vera è in `ARCHITECTURE.md` §2.)

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

- [x] Scegliere il font libero più vicino a Marker Felt (candidati: Kalam, Patrick Hand, Itim, poi altri 40) e il set di icone
      libero (candidato: Lucide) al posto delle icone di sistema. Prova affiancata alle schermate del Mac.
      **Scelto Chewy** (18 ottobre 2026): provati 44 caratteri liberi contro il vero Marker Felt Wide del Mac (forma delle lettere, peso del tratto, larghezza e
      altezza delle maiuscole a parità di altezza delle minuscole) e poi nell'app; Chewy è il più vicino (Londrina Solid e Boogaloo i successivi). Itim, scelto
      prima a occhio, era 18° e troppo largo. Licenza Apache 2.0, in `windows/resources/fonts/` e in `CREDITS.md`. Cambiarlo è un file e una riga (`--marker` in `card.css`).
- [x] Suono di fine focus (al posto di «Glass»): generato da zero, quindi senza licenze (`windows/resources/fine-focus.wav`,
      due rintocchi di campana, 2,2 secondi). **Da ascoltare e approvare.**
- [x] Scrivere `FORMATI.md`: i tre file dei dati e le regole di lettura (versioni, file rovinato, file più nuovo in sola
      lettura, copia di sicurezza giornaliera, file del focus in corso), ricavati dal codice Swift.
- [x] Raccogliere i file di esempio in `tests/fixtures/` (18 cartelle: sessioni v0, v1, v2, v3, rovinate, più nuove, focus in corso, profilo,
      giardino, preferenze) **e i risultati attesi dal Mac** in `tests/fixtures/attesi/` (`tests/genera-attesi.sh`, sempre uguali a parità di codice).
- [x] Preparare l'ambiente: **fatto sul Mac** (Node 24, TypeScript 7.0.2, Electron 44.9.0, esbuild; progetto che si apre con `npm start`, sicurezza
      di Electron già impostata: `contextIsolation`, `sandbox`, niente Node nella pagina, protocollo `ff://` al posto di `file://`). **Prova su Windows fatta** il 18 ottobre 2026 su un computer Windows
      vero con l'installer della CI: l'app parte e funziona bene, circa 200 MB e 0 % di processore. I controlli uno per uno sono in `windows/PROVE_SU_WINDOWS.md`.
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
- [~] Misure per scegliere (su Windows, 18 ottobre 2026: circa 200 MB e 0 % di processore; il resto è ancora da provare): processore a riposo (meno del 2%), memoria con tutti i processi di Electron sommati (obiettivo sotto i 250 MB), clic che passano davvero nelle zone vuote, trascinamento
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
cambio come sul Mac, e bastano TypeScript e il DOM. Icone: **Lucide** (ISC, in `windows/tools/genera-icone.mjs`). Le icone di sistema, il
carattere e la musica che suona davvero arrivano con M0 (font) e M5 (suoni). Il pulsante «Giardino» non c'è (seconda uscita) e
«Statistiche» dice che arriva (M7). **Da provare su Windows:** passaggio del focus tra le finestre quando la scheda si apre e si
chiude, e la posizione rispetto all'icona con la barra in basso, a lato e in alto.

**Fatto quando:** da sola la scheda permette di fare un giro completo (scegliere materia, focus, note, pausa, voto).

### M5 — I suoni (4–6 giorni)

- [x] **Rumori sintetizzati** (pioggia, rumore marrone, vento) in un `AudioWorklet`, con le stesse regole del Mac
      (dissolvenze di 2 secondi, anteprima breve alla scelta, volumi 10/25/40/60%).
- [x] **Musica**: 5 brani inclusi (verificare che il formato si senta su Windows; altrimenti convertirli), cartella
      dell'utente (finestra di scelta, ricerca nelle sottocartelle, elenco in cache), coda mischiata che non riparte dal
      brano appena suonato.
- [x] L'audio vive nella finestra sempre aperta, con `backgroundThrottling` spento: una finestra nascosta verrebbe rallentata e il suono scatterebbe.
- [x] Solo durante un focus attivo (non in pausa); **un solo sottofondo alla volta**.
- [x] Controlli sulla pagina del focus e sulla scheda.
- [x] Se l'audio non parte, lo dice il compagno.

**Stato (sul Mac):** i rumori sono la classe `NoiseSynth` di Swift portata passo per passo in `core/noise.ts` e girano in un `AudioWorklet`
(a 44100 Hz, come sul Mac); la prova di contratto confronta quello che esce con le misure fatte dall'app per Mac
(`tests/genera-rumore.sh` → `tests/fixtures/rumore.json`: pioggia e marrone uguali all'1%, il vento al 3% perché sul Mac la fase
dell'oscillatore si somma in Float32 e si scosta col tempo). Provato davvero: anteprima di tre secondi fuori dal focus, suono durante
il focus, spento (e motore fermo) quando il focus si ferma e riacceso quando riprende, vento e marrone, musica dei brani inclusi e di una
cartella (anche nelle sottocartelle), brano successivo a fine brano, cartella che non c'è (silenzio), audio che non parte (lo dice il
compagno) e audio che continua con il compagno nascosto. Misure sul Mac con la pioggia e un focus: **processore circa 1,2% in tutto**
(obiettivo sotto il 5%); la memoria sale ancora a circa 530 MB sommando i processi (il processo dell'audio ne aggiunge una cinquantina),
quindi resta il punto da ridurre in M9. **Da provare su Windows:** che gli m4a si sentano (Chromium li legge, ma va verificato), la
pioggia per un'ora senza scatti, il cambio di cuffie o altoparlanti, e «Scegli la cartella…» con la finestra di Windows.

**Fatto quando:** la pioggia suona senza scatti per un'ora con il processore sotto il 5%, e passa a musica e viceversa senza buchi.

### M6 — Le schede collegate (3–4 giorni)

- [x] **«Cosa studi adesso?»**: testo libero, fino a 6 materie recenti, «nessuna materia», indietro, ultima nota.
- [x] **«Com'è andata?»**: tre facce e una riga facoltativa; non prende la tastiera; sparisce da sola; salvando solo la nota
      non cancella il voto già dato.
- [x] **Introduzione**: nome e primo compagno (quattro bottoni).

**Stato (sul Mac):** le tre schede sono **finestre di dialogo dentro la finestra trasparente** (`renderer/dialogs/`): «Cosa studi adesso?» e il
benvenuto sono al centro e prendono tutti i clic e la tastiera (Esc le chiude, un clic fuori no, come sul Mac); «Com'è andata?» sta
accanto al compagno e **non prende la tastiera finché non ci clicchi nel campo**. Tutti i focus passano da «Cosa studi adesso?» (dalla
scheda, dal quadrante, da «Nuovo focus» e dal menu dell'area di notifica). Il colore di ogni materia è lo stesso del Mac (stesso calcolo a
64 bit, provato con valori misurati con Swift). Provato: primo avvio (nome pulito, primo compagno, `profilo.json` con `unlocked`), materia
scritta con Invio, materia recente, «Senza materia», freccia indietro, Esc; un focus finito davvero fa comparire «Com'è andata?», un
voto con la nota si salva, con la sola nota il voto già dato resta, «Salta» non scrive niente, un nuovo focus la fa sparire, e i clic
tornano a passare subito dopo. **Da provare su Windows:** la tastiera che passa al campo di «Com'è andata?» senza togliere il fuoco
all'applicazione in cui stavi scrivendo finché non ci clicchi, e il fuoco che torna a quell'applicazione quando la scheda si chiude.

**Fatto quando:** il primo avvio, un focus completo e un focus interrotto danno gli stessi dati che darebbe il Mac.

### M7 — Le statistiche (6–8 giorni)

- [x] Finestra con le schede **Oggi / Settimana / Mese**, frecce tra i periodi, pulsante «‹ Menu».
- [x] Riepilogo: totale in grande, focus completi e interrotti, barre sottili, barra a segmenti con le materie e la legenda,
      serie (con il fiocco), come è andata, frasi su quando rendi meglio.
- [x] **Tendina «Mostra le sessioni»**: striscia del giorno, righe con ora, materia, nota, faccia e durata; per settimana e
      mese le sessioni sotto il giorno; la pagina scorre.
- [x] **Modifica di una sessione** (materia, «applica a tutte», nota, voto, note del focus) ed eliminazione.
- [x] **Esporta CSV** (finestra di salvataggio) e **Cancella tutto…** (con conferma).

**Stato (sul Mac):** una **finestra vera** (con la barra del titolo, «Le statistiche di …», 560 × 660) che si crea alla prima richiesta e si
distrugge alla chiusura, così non tiene memoria quando non serve; l'apre la scheda (riquadri di oggi e «Statistiche») o il menu
dell'area di notifica. I numeri li ricava la pagina dalle sessioni con le stesse funzioni di `core/` provate contro il Mac; i testi
(titoli dei periodi in italiano, righe sotto il numero, legenda, diario, striscia delle ore) sono funzioni pure provate in
`core/dashboard.ts` (stesse date di Swift, controllate una per una). Si aggiorna da sola se il registro cambia. Provato con dati
d'esempio: Oggi / Settimana / Mese, frecce, il diario (striscia dei giorni, sessioni sotto il giorno per settimana e mese), la modifica
di una sessione con «cambia la materia in tutte» (rinomina e unisce), voto, nota e note del focus, elimina, esporta CSV (23 righe, con
l'intestazione giusta), «‹ Menu» che chiude e riapre la scheda, «Cancella tutto…» (conferma di sistema, poi sessioni e profilo a zero).
Senza giardino: il testo della conferma non lo nomina. **Da provare su Windows:** le finestre di sistema (salvataggio del CSV e
conferma) e come sta la finestra con la scala 150% e 200%.

**Fatto quando:** sugli stessi dati i numeri e i testi delle statistiche sono uguali a quelli del Mac.

### M8 — Sblocchi e nome (2–3 giorni)

- [x] Annuncio dello sblocco a fine focus, scelta del primo compagno, compagni bloccati che non si possono scegliere.
- [x] Il nome nei titoli («Le statistiche di …»), «Il tuo nome…».
- [x] Modalità sviluppatore (`developerMode` nelle impostazioni) che sblocca tutto.

**Stato (sul Mac):** la regola degli sblocchi è in `core/unlocks.ts` (6 prove con il profilo vero: 20 focus pieni per il secondo, 50 per il
terzo, 100 per il quarto, l'ordine che dipende dal primo scelto, più sblocchi insieme, e niente di registrato in modalità sviluppatore).
A fine focus i compagni guadagnati si sbloccano e il compagno lo dice nove secondi dopo la frase di fine focus; quelli ancora bloccati
si vedono con il lucchetto e la frase su quanto manca, e non si possono scegliere né dalla scheda né dal menu. «Il tuo nome…» (menu
dell'area di notifica) apre una finestra di dialogo: il nome si pulisce, vuoto lo toglie, e cambia il saluto della scheda e il titolo
della finestra delle statistiche. Modalità sviluppatore: si accende scrivendo `"developerMode": true` in `impostazioni.json` (sul Mac si
fa con `defaults write`); sblocca tutto senza toccare il profilo. Provato dal vivo con un profilo che ha scelto Pianty per primo.


### M9 — Sistema e rifiniture (3–5 giorni)

- [x] **Una sola copia dell'app aperta** (`requestSingleInstanceLock`): un doppio avvio non deve mai toccare i dati due volte.
- [x] Avvio al login (`setLoginItemSettings`) con la voce nel menu.
- [x] Più schermi, scala del 100%–200%, barra delle applicazioni in qualunque lato, tema scuro di Windows (le schede sono sempre chiare).
- [x] Problemi con i dati detti dal compagno (file illeggibile, scrittura fallita), una volta sola.
- [x] Chiusura pulita: un focus in corso si registra come interrotto, come sul Mac.
- [x] Prestazioni: a riposo sotto il 2% di processore e sotto i 250 MB di memoria (tutti i processi di Electron sommati: è
      la parte più pesante rispetto al Mac). **Misurato su Windows il 18 ottobre 2026: circa 200 MB e 0 % di processore** (da rimisurare con la pioggia accesa).
- [x] Arresti inattesi: un file di registro dell'app (senza dati personali) per capire cosa è successo.

**Stato (sul Mac):**
- **Una sola copia** (`requestSingleInstanceLock`): la seconda esce in un secondo e la prima mostra il compagno e lo scrive nel registro.
- **Registro dell'app** (`core/diagnostics.ts`, `registro-app.log` nella cartella dei dati, due file da 200 KB al massimo): avvio con le versioni,
  chiusura, eccezioni non gestite, promesse respinte, processi caduti, schermi aggiunti e tolti. Niente nomi, materie o note, e il nome
  dell'utente nei percorsi diventa «~». Se la pagina del compagno cade si ricarica (non più di tre volte in dieci minuti).
- **Avvio al login:** voce nel menu, attiva solo nell'app installata (da sviluppo registrerebbe Electron).
- **Problemi con i dati** detti dal compagno una volta sola (sessioni illeggibili o rovinate, profilo, impostazioni): provato con un file senza permessi.
- **Chiusura pulita:** all'uscita, e anche quando Windows chiude la sessione (`session-end`), un focus in corso si registra come interrotto
  (provato: 65 secondi salvati, segno «in corso» tolto).
- **Più schermi:** una sola finestra trasparente che sta sull'area di lavoro dello schermo del compagno e **si sposta con lui**: trascinandolo
  oltre il bordo la finestra segue il cursore sull'altro schermo (si controlla ogni 50 ms), dal menu c'è «Schermo» per sceglierlo, e se lo
  schermo sparisce torna sul principale. La geometria (`core/displays.ts`) è provata con schermi inventati; lo spostamento della
  finestra con due schermi finti. Una sola finestra invece di una per schermo costa meno memoria. **Da provare su Windows:** che il
  trascinamento continui quando la finestra si sposta sotto il cursore, e la scala diversa tra due monitor.
- **Barra delle applicazioni** in basso, in alto, a destra o a sinistra: la scheda si apre dal lato giusto dell'icona (provato con i quattro lati).
- **Tema scuro di Windows:** le schede dichiarano `color-scheme: light`, quindi campi e barre di scorrimento restano chiari.
- **Prestazioni (misure sul Mac, solo indicative):** a riposo il processore sta sotto l'1% in tutto; la memoria è circa **590 MB** sommando i
  quattro processi. L'opzione `in-process-gpu` toglie il processo della GPU e porta la somma a **circa 480 MB** con lo stesso processore, ma
  fa dipendere l'app da un componente instabile: da misurare su Windows (dove un Electron semplice sta intorno ai 250 MB) prima di
  deciderla. Spegnere l'accelerazione costa più processore e non toglie il processo su Mac.


### M10 — Installazione e distribuzione (3–4 giorni)

- [x] Programma di installazione (NSIS, con electron-builder), icona, versione.
- [~] **Firma del codice**: senza, Windows mostra l'avviso SmartScreen. Scelta da fare (certificato a pagamento, o servizio
      di firma, o niente e una nota nel README come per il Mac).
- [x] **CI su GitHub** (macchina Windows): compila, lancia le prove e produce l'installer a ogni push. (È anche il
      punto F-07 della revisione dell'architettura, fatto per tutti e due i sistemi.)
- [~] Sezione Windows nel README, note di rilascio, tag e release con l'installer e il suo SHA-256.
- [x] Come si aggiorna (a mano, scaricando dalla pagina delle release; aggiornamenti automatici con electron-updater solo dopo, se serve).

**Stato:** installer NSIS per l'utente (electron-builder 26, `windows/electron-builder.yml`): un `…-x64-Setup.exe` e un `…-arm64-Setup.exe`
(circa 134 MB l'uno: Electron e 25 MB di immagini, frasi e brani, preparati da `windows/tools/prepara-risorse.mjs` senza i fogli originali), per l'utente,
senza amministratore, **che non cancella i dati** se si toglie l'app. Provato sul Mac: pacchetto non compresso e installer x64 si fanno; l'app
**gira da un archivio asar** (pagina, ponte, suono e brani letti da lì). Versione `0.9.0` (da confermare alla release). La **CI** è scritta
(`.github/workflows/windows.yml`: tipi, prove e compilazione a ogni modifica; con un tag `windows-v…` anche i due installer, lo SHA-256 e una *bozza* di
release; `mac.yml` lancia le prove di Swift: punto F-07 della revisione) ma non è mai girata: parte al primo push. Cosa resta: **la scelta sulla firma**
(vedi `windows/RILASCIO.md`: niente, SignPath Foundation gratis per i progetti liberi, Trusted Signing, o un certificato) e provare l'installer su
Windows. Dopo la firma si potranno aggiungere gli aggiornamenti automatici (electron-updater).


### M11 — Parità e prove su Windows (4–5 giorni)

Lista di controllo, funzione per funzione, contro l'app per Mac:

- [x] Ogni voce di `README.md` («Cosa fa») e di `ARCHITECTURE.md` §3 ha il suo equivalente o una nota su perché no: **`windows/PARITA.md`**.
- [ ] Windows 10 e 11, x64 e ARM, 100% / 150% / 200%, uno e due schermi, barra delle applicazioni ovunque. *(Solo su Windows: `windows/PROVE_SU_WINDOWS.md` §A–C.)*
- [~] Sleep e risveglio, chiusura del coperchio, cambio di fuso orario, ora legale. *(Fatto quello che si prova dal Mac; lo sleep vero è in §D.)*
- [ ] App a schermo intero, cambio di desktop virtuale. *(Decisione rimandata alla prova su Windows: §E. Il Mac lascia il compagno sopra le app a schermo
      intero; qui è lo stesso, e il desktop virtuale è un limite di Windows.)*
- [~] Una giornata intera d'uso vero, e i dati riletti dall'app per Mac. *(I dati riletti dal Mac: fatto, con file scritti dal codice per Windows.
      La giornata vera: §J.)*

**Stato (sul Mac):**
- **Confronto funzione per funzione** (`PARITA.md`): ogni riga dice cosa fa il Mac, cosa fa Windows e come l'ho verificato (prova automatica, prova dal vivo,
  solo nel codice, o solo su Windows). Le differenze volute o imposte da Windows sono in fondo (§10).
- **Contratto al contrario** (`test/ritorno.test.ts`): i file scritti dal codice per Windows (una migrazione da v2, sessioni con accenti, emoji, virgolette e
  formule da foglio di calcolo, voto e note, una materia rinominata, una tolta, un focus in corso con pausa e uno fermo, un profilo con nome da accorciare e
  sblocchi) li legge **il codice Swift del Mac** (lo stesso generatore degli attesi) e ne ricava risultati identici. Controllato anche che la prova fallisca se
  un file cambia (mutazione).
- **Un errore trovato e corretto**: il fuso orario del computer si leggeva una volta sola, all'avvio. Con l'app aperta, un viaggio o un cambio di fuso
  avrebbero lasciato l'orologio di prima (le nuove sessioni al giorno sbagliato, «Oggi» sbagliato) fino al riavvio. Ora si rilegge ogni cinque secondi e subito
  dopo uno sleep (`core/time.ts`). Prove in `test/fusi.test.ts`: cambio d'ora di ottobre (giorno da 25 ore, 02:30 due volte) e di marzo (giorno da 23 ore),
  serie di giorni e settimane attraverso il cambio, Sydney, Lord Howe (mezz'ora), India e Nepal, Kiritimati e Pago Pago, e il cambio di fuso durante l'esecuzione.
- **Sleep e risveglio** (`powerMonitor`): al risveglio e allo sblocco dello schermo si rilegge il fuso, la finestra si riadatta agli schermi (può essere
  cambiato qualcosa) e **suono e musica ripartono se il sistema li aveva fermati**; lo stesso se l'uscita audio cambia mentre suonano. Provato dal vivo con sleep
  e risveglio simulati: pioggia che riparte, musica che riparte, nulla che parte fuori dal focus o a focus fermo.
- **Registro dell'app più utile per le prove**: ora scrive la versione di Windows e, per ogni schermo, misure, scala, area di lavoro e il lato della barra
  delle applicazioni (all'avvio, a ogni cambio, al risveglio). Una prova su un altro computer si capisce dal file.
- **Prove su Windows pronte** (`PROVE_SU_WINDOWS.md`): dieci gruppi di passi con cosa deve succedere e cosa mandare.
- **Non fatto di proposito**: nascondere il compagno davanti alle app a schermo intero e seguire il cambio di desktop virtuale. Su Windows servono chiamate di
  sistema che Electron non offre; farle alla cieca (pacchetti nativi, o PowerShell da un'app non firmata, che può far arrivare un antivirus) rischia più di
  quanto vale. Le due strade sono scritte in `PROVE_SU_WINDOWS.md` §E, da scegliere dopo aver visto cosa succede davvero.

**Fine della prima uscita:** versione 1 per Windows, **senza giardino**. Durante la prima uscita il pulsante «Giardino» non
c'è nella scheda e nel menu.

**Stato della prima uscita (aggiornato il 20 ottobre 2026): pubblicata.** Il 18 ottobre è uscita come
[`windows-v1.0.0`](https://github.com/jaacopocoding/FocusFriends/releases/tag/windows-v1.0.0): installer x64 e ARM con il loro SHA-256, **non firmato**,
senza giardino (la release non è segnata «Latest», che resta la 0.8.0 per Mac). Verifiche: 247 prove della logica per Windows e 332 di Swift, tutte passate;
CI verde su macchine Windows e Mac; l'installer aperto e controllato (architettura, versione, risorse, carattere, licenze). Su un computer Windows vero l'ha
provata l'utente in modo sommario: funziona bene, circa 200 MB e 0 % di processore. **Ancora aperti:** i controlli uno per uno di `windows/PROVE_SU_WINDOWS.md`
(sleep vero, più schermi, scale, suoni, finestre di sistema), l'approvazione della campana di fine focus, la decisione su schermo intero e desktop virtuali,
e la firma del codice (SignPath Foundation).

**1.0.1 (preparata il 20 ottobre 2026, non uscita da sola: è dentro la 1.1.0).** Chiude i punti deboli della revisione scritti in `windows/ARCHITECTURE.md` §10: le finestre non
navigano più altrove, non ne aprono di nuove e non ottengono permessi (`main/security.ts`); le variabili di prova (`FF_NO_LOCK`, `FF_FAKE_DISPLAYS`, `FF_SELFTEST_SAVE`,
`FF_SELFTEST_CONFIRM`, `FF_DATA_DIR` nell'app installata) valgono solo con `FF_SELFTEST`; i copioni delle prove dal vivo stanno in `windows/test/vivo/`. 259 prove della logica,
tutte passate. Nessuna funzione nuova e nessun cambio ai dati.
Il commit è `74bda89`.

**1.1.0 (pubblicata il 21 ottobre 2026): «Da fare».** La stessa funzione dell'app per Mac (commit `6bf851c`, `c5c769b`): una riga nella scheda,
la pagina con la lista divisa per scadenza, le scelte di data (con un calendario disegnato nella scheda) e di materia, «Inizia un focus» con la materia già scritta,
e il compagno che ricorda le scadenze di oggi o domani. Logica in `core/todo.ts` (pura) e `core/todoList.ts` (il file `dafare.json`, `FORMATI.md` §9); la frase la
decide il processo principale quando la pagina chiede la prossima. Contratto con il Mac nei due versi (4 cartelle di esempio nuove, `tests/fixtures/dafare*`, e una
cartella scritta da Windows letta da Swift); 276 prove della logica, tutte passate; provata dal vivo con `test/vivo/dafare.cjs`. Comprende la 1.0.1.
È uscita come [`windows-v1.1.0`](https://github.com/jaacopocoding/FocusFriends/releases/tag/windows-v1.1.0) (tag su `4b84a72`): installer x64 e ARM con il loro SHA-256, **non firmata**,
non segnata «Latest» (resta la `v0.9.0` per Mac). Installer controllati prima di pubblicare: SHA-256 uguali a `SHA256SUMS.txt`, architettura giusta dentro l'eseguibile (x64 e ARM64),
versione 1.1.0 nel pacchetto e nell'eseguibile, 114 file di immagini, frasi e brani (5 `.m4a`), il carattere Chewy con la sua licenza, le licenze di Electron e Chromium, nessuna
mappa dei sorgenti, e dentro il codice compilato la pagina «Da fare» e il blocco di navigazione e permessi della 1.0.1.

**1.1.1 (pubblicata il 21 ottobre 2026): aggiungere e modificare.** Dopo averla usata, l'utente ha chiesto di cambiare il modo di aggiungere: il «+»
in alto a destra apre la pagina «Nuova cosa» (nome, scadenza, materia, «Aggiungi»), non più un campo sopra la lista; e toccando il testo di una voce si apre la stessa pagina per
**modificarla**. I nomi lunghi vanno a capo su due righe; la materia si può anche scrivere. Stessa cosa sul Mac (0.9.1). Il formato di `dafare.json` non cambia; nuova operazione
`update` in `ToDoList` (Swift e TypeScript), provata in `tests/main.swift` e `windows/test/dafare.test.ts`; 277 prove su Windows e 393 sul Mac.
Provando la versione sul Mac, una seconda correzione: il ▶ «Inizia un focus» faceva partire la durata dell'ultimo focus; ora porta al quadrante «Gira il timer» (con «Focus per…»
in alto, e l'ultima durata come punto di partenza), e «Avvia il focus» parte con la materia della voce, senza richiederla (senza materia si apre «Cosa studi adesso?»).
È uscita come [`windows-v1.1.1`](https://github.com/jaacopocoding/FocusFriends/releases/tag/windows-v1.1.1) (tag su `e989d20`), insieme alla `v0.9.1` per Mac (che è la «Latest»); non firmata, non «Latest».
Installer controllati prima di pubblicare: SHA-256 uguali a `SHA256SUMS.txt`, eseguibile x64 e ARM64 giusti, versione 1.1.1, 114 file di immagini, frasi e brani (5 `.m4a`), Chewy con la sua
licenza, licenze di Electron e Chromium, nessuna mappa dei sorgenti, e nel codice compilato «Nuova cosa», «FOCUS PER», la modifica delle voci e il blocco di navigazione e permessi.

**1.2.0 (preparata il 21 ottobre 2026, pubblicata il 26 ottobre 2026): «Hai finito?», le frasi legate al momento e la scheda «Anno».** Chiude il giro tra «Da fare» e il timer: se un focus parte dal ▶ di una voce, a fine focus la scheda
«Com'è andata?» chiede anche «Hai finito «…»?» con *Fatta* e *Non ancora* (con «Chiedi com'è andata» spento, solo questa domanda). *Fatta* segna la voce. Il timer ricorda la voce solo in
memoria (nessun nuovo formato di dati; se l'app si chiude durante il focus il legame si perde). Stessa cosa sul Mac (0.10.0). Provata dal vivo con `test/vivo/hai-finito.cjs`.
Poi **le frasi legate al momento e i numeri a voce** (stesse regole e testi del Mac, `Remarks.swift` ↔ `core/remarks.ts`): il saluto dell'avvio per fascia della giornata, con il nome; il riepilogo
della settimana scorsa (lunedì–mercoledì, una volta per settimana: l'unica cosa salvata è `lastWeeklyRecap` in `impostazioni.json`, già `UserDefaults` sul Mac); ogni tanto una frase «quando rendi
meglio»; «Rieccoti!» al risveglio dallo sleep dopo almeno un'ora; i traguardi (giorni di fila, focus, ore, «un mese insieme») detti dopo la frase di fine focus. Le frasi in coda e la scelta
della prossima (`PhraseChooser`) stanno nel processo principale; un nuovo canale `speech:when-quiet` fa aspettare le frasi che non devono coprirne un'altra (anche l'annuncio degli sblocchi). Il fumetto
sta ora sopra «Com'è andata?». Provata sugli stessi dati del Mac (saluti in 6 momenti fissi, traguardi mano a mano che il registro cresce, 294 anniversari su date inventate: `genera-attesi` e
`contratto.test.ts`) e dal vivo con `test/vivo/frasi-contesto.cjs`. Nel farlo si è corretto anche il Mac: da un 31 gennaio al 28 febbraio il conteggio dei mesi dava zero. 318 prove su Windows e 445 sul Mac.
Poi **la scheda «Anno» delle statistiche** (Mac 0.10.0, Windows 1.2.0): l'anno di calendario come mappa con un quadratino per giorno (soglie fisse a 30, 90 e 180 minuti), tre caselle (serie più lunga, giorno più forte, mese migliore) e l'andamento per settimana, di tutte le materie o di una a scelta; passando sopra un giorno si legge il tempo, cliccandolo si apre in «Oggi». Nessun dato nuovo. `YearStats.swift` ↔ `core/yearStats.ts`, con i testi in comune provati sui due lati; il contratto confronta anche un anno e mezzo di studio inventato (504 sessioni) e le griglie di 41 anni. 337 prove su Windows e 484 sul Mac; provata dal vivo con `test/vivo/anno.cjs` (e sul Mac con un banco di prova di dati inventati).

È uscita come [`windows-v1.2.0`](https://github.com/jaacopocoding/FocusFriends/releases/tag/windows-v1.2.0) (tag su `7d691bb`, la stessa punta di `main` della `v0.10.0` per Mac, che resta la «Latest»); non firmata, non «Latest».
Controllato prima di pubblicare la bozza: il flusso «Windows» verde (tipi, prove, build e i due installer), SHA-256 degli installer scaricati uguali a `SHA256SUMS.txt`, installer x64 e ARM64 di
misure diverse (134 e 128 MB), note della release uguali a `windows/NOTE_DI_RILASCIO.md`. Non si sono guardati dentro gli installer (senza 7-Zip a disposizione sul Mac). Il giardino nuovo (Mac 0.10.0) non c'è ancora su Windows: resta la seconda uscita.

## Seconda uscita: il giardino (circa 6 settimane)

> **Rifatto il 1° novembre 2026, sul giardino del Mac 0.11.0.** Il vecchio piano (G1–G6, 8–12 giorni) era per il prato libero con punti e negozio, che sul Mac non
> c'è più. Oggi il giardino sono le **figurine** a fine focus (`GardenDrops.swift`), l'**album** (`AlbumWindow.swift`) e un **mondo di cinque isole** a tessere viste di
> sbieco, unite da ponti (`GardenGrid.swift`, `GardenWindow.swift`), con il cielo e le stagioni, gli angoli, gli ospiti e i compagni che ci camminano.

**Quanto c'è da portare.** Sul Mac la logica senza disegno (solo Foundation) è di circa 2.950 righe: `GardenCatalog`, `Garden`, `GardenDrops`, `GardenGrid`, `GardenSky`,
`GardenCorners`, `GardenCompanions`, `GardenVisitors`; la serie di giorni (`GardenPoints.swift`) c'è già, come `core/points.ts`. Il disegno e l'interfaccia (AppKit) sono
circa 5.250 righe: `GardenWindow` 3.441, `AlbumWindow` 1.204, `Sticker` e `GiftCard` 321, `GardenSprites` 283. Le immagini sono pronte: 167 file in `assets/giardino/`
(25 MB, senza i fogli `*_original.png`) e l'album in `assets/album/` (3 MB).

**Le scelte**
- **La logica** va in `core/` con gli stessi nomi (`gardenCatalog.ts`, `gardenDrops.ts`, `gardenGrid.ts`, `gardenSky.ts`, `gardenCorners.ts`, `gardenCompanions.ts`,
  `gardenVisitors.ts`; `garden.ts` è il file `giardino.json` e usa `node:fs`, quindi sta nel processo principale e le pagine ricevono lo stato per IPC). Si prova con le
  **prove di contratto**: `tests/genera-attesi` scrive cosa ricava il Mac (tiri, sentieri, terreno, ponti, luce, angoli, ospiti, e un giardino che cambia passo per passo)
  e `contratto.test.ts` lo confronta. Le cartelle `giardino-*` e la parte `giardino` di `v3-completo`, finora saltate, si confrontano anche loro.
- **Il disegno**: l'isola e il mondo su un `<canvas>` 2D, in una finestra normale aperta a richiesta (come le statistiche: `ff://`, un ponte suo). Si ridisegna solo
  quando serve; da nascosta non disegna. L'album in CSS 3D, le carte in HTML.
- **Le immagini** si portano come sono (PNG). L'installer passa da circa 134 a circa 165 MB: alla G7 si misura e si decide se convertirle in WebP.
- **Gli interruttori nascosti del Mac** (`quickGifts`, `gardenSeason`, la modalità sviluppatore che apre tutto) diventano opzioni del costruttore, che l'app per ora
  non accende (le prove dal vivo sì).
- **Due uscite.** La prima (G0–G7) ha già il mondo, perché con il secondo compagno (20 focus pieni) serve la sua isola, e il tiro sceglie fra le cose dei compagni
  sbloccati. La seconda (G8) è la vita sull'isola: non cambia il formato dei dati. (Poi si è deciso di fare la G8 prima di pubblicare: esce tutto nella 1.3.0.)
- **Durante il porting il giardino del Mac non cambia**, o si cambia sui due lati insieme: altrimenti le prove di contratto si spostano sotto i piedi.

**Le fasi**
- [x] **G0 — Il piano** (questo capitolo).
- [x] **G1 — La logica** (5 giorni): catalogo (47 oggetti, rarità, isole, nomi con l'articolo, pagine dell'album), tiri (FNV-1a, MurmurHash3, Mulberry32, la riserva di
      minuti), griglia, sentieri, terreno, collina, mondo e ponti, cielo e stagioni, angoli, pose dei compagni e strade, ospiti; `Garden` con `giardino.json` versione 4
      (lettura dalle versioni 1–3, file rovinato o più nuovo, oggetti tolti, regole delle isole, ponti e benvenuti). Prove di contratto e prove proprie.
      **Fatta il 1° novembre 2026**: otto file in `core/` (circa 2.550 righe). Il generatore del Mac ha un file in più, `tests/genera-attesi/giardino.swift`, che scrive
      `attesi/_giardino.json` (catalogo, 420 regali con le isole che si aprono, sentieri delle cinque isole a tre grandezze, terreno e dettagli in ogni stagione, ponti, luce ogni
      quarto d'ora, particelle, angoli, pose, strade, ospiti per 40 giorni, e un giardino passo per passo: casa, 60 focus, ponti, mosse, ospiti, rilettura, «Cancella tutto»);
      ogni cartella con un giardino ha in più `dopoLAvvio` (casa, regole delle isole, ponti, file messi da parte), con due esempi nuovi (`giardino-formato3-regole`,
      `giardino-formato4`), e ogni cartella con sessioni le figurine che il registro avrebbe dato. Su Windows tutto uguale al primo colpo, tranne lo zero negativo che Swift
      scrive `-0`. Anche la prova di ritorno ora confronta il giardino. 366 prove su Windows, 1013 controlli sul Mac.
- [x] **G2 — Il giardino a schermo, fermo** (6): finestra, isola con terreno, bordo e collina, casa, oggetti (anche quelli sul lato e la staccionata), cielo e stagioni,
      zoom e spostamenti. Si verifica mettendo accanto la stessa scena sul Mac e su Windows.
      **Fatta il 1° novembre 2026.** `main/gardenWindow.ts` (la finestra, 1000 × 600 come la scena del Mac, più piccola su uno schermo stretto; si apre dal menu
      dell'area di notifica), `shared/gardenApi.ts` e `preload/preloadGarden.ts` (la pagina riceve una fotografia del giardino), `renderer/garden/` (`scene.ts` il disegno,
      `sprites.ts` le immagini: parte visibile, disegni sul lato con i bracci, tinta della luce). Tutte le isole con colline, terreno, dettagli, case, ponti costruiti, cose e
      compagni (fermi), la luce dell'ora e della stagione, le finestre accese di sera, zoom con la rotellina e spostamento trascinando, «+», «−», «0», «M». La scena ferma
      si dipinge una volta e si ridisegna solo se cambia qualcosa; spostandosi un fotogramma sta nei 16 ms. Il confronto: `test/vivo/giardino.cjs` fa le schermate su
      Windows e `tools/banchi/render-giardino.sh` disegna la stessa cartella di dati con la `GardenView` vera del Mac (a mezzogiorno d'autunno, la sera, d'inverno, tutte le
      isole): uguali, a parte quello che appartiene alle fasi dopo (i comandi, i nomi delle isole, il fumo). L'ora e la stagione si forzano con `gardenHour` e
      `gardenSeason` in `impostazioni.json`. L'installer porta 285 file di immagini (46 MB): restano fuori i fogli originali, i pezzi del paesaggio, il vecchio prato e il bordo.
- [x] **G3 — Si gioca** (3): la cassetta «Da mettere», trascinare con l'anteprima verde o rossa, girare, togliere, i comandi in alto. Copioni in `test/vivo/`.
      **Fatta il 1° novembre 2026.** I comandi sono HTML sopra il canvas, nelle misure della scena (si scalano con la finestra): «‹ Menu», «Isola di …» (tocca per tutte
      le isole), le pastiglie della prossima figurina, della serie e delle figurine (con le spiegazioni al passaggio del mouse), lo zoom, la pillola e la cassetta «Da mettere»
      (scorre con la rotellina), la zona «Rilascia qui per toglierla», le righe in basso e il fumetto del compagno toccato. Dalla cassetta si trascina sull'isola (verde se ci
      sta, rosso se no, con la riga che dice perché) o si tocca (va da sola su una tessera libera); una copia si sposta, si gira con R mentre si trascina, con due tocchi o con
      il tasto destro («Gira», «Togli dal giardino»), e si toglie lasciandola in basso a sinistra; la staccionata si unisce e la prossima parte girata come l'ultima; passando
      sopra un'altra isola aperta diventa lei quella viva (non vicino alla zona per togliere, a differenza del Mac). Le regole sono quelle di `Garden` (la pagina le controlla
      con `core/gardenGrid.ts`, il processo principale le applica). La rotellina del mouse ingrandisce a scatti di 1,3 come i tasti, due dita sul touchpad spostano, il pizzico
      ingrandisce. Provata dal vivo con `test/vivo/giardino-mosse.cjs` (il mouse simulato sulla finestra).
- [x] **G4 — Le figurine** (3): il tiro a fine focus (`PomodoroDeps.gardenLine`), la carta della figurina, la riga e la barra sotto «Album» nella scheda, «Cancella
      tutto…» che toglie anche il giardino (`StatsDeps.onDeleteAll`).
      **Fatta il 1° novembre 2026.** A fine focus il processo principale tira la figurina (`main/main.ts`, con i giorni di fila del giorno del focus, come il Mac): la frase
      di fine focus dice la figurina o quanto manca (`giftLine`), la figurina va sull'isola e compare accanto al compagno (`renderer/giftCard.ts`, che si gira e luccica se è
      rara, 6,5 secondi, sopra «Com'è andata?» e sotto il fumetto). La figurina si disegna con `renderer/garden/sticker.ts` (lo stesso disegno servirà all'album).
      Nella scheda: «Giardino» accanto a «Statistiche» (anche nella pagina del focus) e, sotto «Da fare», la riga «Prossima figurina: ancora N minuti di studio» con la
      barretta (un tocco apre il giardino; la riga «Album» arriva con la G6). «Cancella tutto…» toglie anche il giardino dalla G2. `quickGifts` in `impostazioni.json` fa
      contare un focus da un minuto come un'ora, per provarlo: `test/vivo/giardino-regalo.cjs`.
- [x] **G5 — Il mondo** (4): le cinque isole, i ponti che si costruiscono, le case, il lucchetto, il regalo di benvenuto.
      **Fatta il 1° novembre 2026.** Le isole, le case e i ponti già costruiti si disegnavano dalla G2; ora: alla prima entrata dopo uno sblocco (mai durante un focus) il
      processo principale calcola i ponti da costruire e i compagni da accogliere e la pagina fa la cerimonia (la telecamera inquadra le isole, i pezzi dei ponti compaiono
      uno dopo l'altro scendendo al loro posto, con «Riduci movimento» tutto insieme); alla fine il processo principale salva, solo quello che era davvero da fare, e dà il
      regalo di benvenuto, che la pagina festeggia con le stelline e la scritta in alto («Nuovo ponte: un regalo per Porcellino · Cesto di carote»). Rimpicciolendo si leggono
      i nomi delle isole; quelle chiuse hanno il lucchetto e «???» con «si sblocca a N focus», e toccandole la riga dice quanto manca. La finestra del giardino non rallenta
      in sottofondo: coperta dalla finestra trasparente del compagno smetteva di disegnare (sul Mac, e probabilmente anche su Windows). Senza le chiavi `replayBridges` e
      `replayWelcome` del Mac. Provata dal vivo con `test/vivo/giardino-mondo.cjs`.
- [x] **G6 — L'album** (5): il libro, le pagine, le sagome, le animazioni. Dopo la G1 non dipende dalle G2–G5: si può fare in parallelo.
      **Fatta il 2 novembre 2026**, con i titoli nuovi del Mac (Amatic SC, `assets/fonts/AmaticSC-Bold.ttf`, licenza OFL, portato anche nell'installer).
      `main/albumWindow.ts` (980 × 730 come la vista del Mac, si apre dalla riga «Album» della scheda, dalla riga della prossima figurina e dal pulsante «Album» del
      giardino), `renderer/album/book.ts` (il disegno su canvas: prato, copertina con la targa, doppie pagine con le figurine di `sticker.ts`, i numeri di pagina, il
      sigillo «completa», le frecce, le linguette e il conto) e `album.ts` (le animazioni: come sul Mac sono fotografie del libro su fogli che girano in 3D, con
      la Web Animations API; la copertina si apre in 0,95 secondi, una pagina gira in 0,6; con «Riduci movimento» niente animazioni). Il libro si apre sulla doppia
      pagina della prima figurina nuova e poi le segna viste; la doppia pagina si ricorda (`albumSpread` in `impostazioni.json`). Un tocco su una figurina scrive in fondo
      cosa è e dove si mette. A metà giro i fogli si scuriscono con un filtro (solo il disegno, non i bordi trasparenti). Provato dal vivo con `test/vivo/album.cjs` e
      confrontato con `tools/banchi/render-album.sh` (il Mac sugli stessi dati): uguali.
- [x] **G7 — Prima uscita** (3): parità a occhio, installer e sua misura, `PROVE_SU_WINDOWS.md` per il giardino, documenti. Versione 1.3.0.
      **Preparata il 2 novembre 2026** (manca solo la pubblicazione): la versione è 1.3.0 (`windows/package.json`), `PARITA.md` ha il §11 (il giardino e l'album, con le
      differenze volute: la rotellina del mouse ingrandisce, l'isola viva non cambia vicino alla zona per togliere, niente `replayBridges`/`replayWelcome`), `PROVE_SU_WINDOWS.md`
      il punto K, le note di rilascio il giardino, l'album, la vita sull'isola (G8, fatta prima di pubblicare) e il Riccio, l'architettura il §4.19. Le immagini nell'installer:
      287 file, 46,6 MB (la 1.2.0 ne aveva 114); gli installer veri li fa la CI con il tag `windows-v1.3.0`, e si misurano lì.
      **Pubblicata il 2 novembre 2026** come [`windows-v1.3.0`](https://github.com/jaacopocoding/FocusFriends/releases/tag/windows-v1.3.0) (tag su `43c281b`, non firmata,
      non «Latest»: resta la `v0.11.0` per Mac), con la G8. Installer: x64 158 MB, ARM64 152 MB (la 1.2.0: 134 e 128). Prima di pubblicare la bozza: flusso verde,
      SHA-256 uguali a `SHA256SUMS.txt`, note uguali a `NOTE_DI_RILASCIO.md`; dentro gli installer non si è guardato.
- [x] **G8 — La vita** (5, seconda uscita): i compagni sull'isola con le loro pose, gli angoli con le stelline, gli ospiti, il vento, l'acqua, il fumo, le luci della sera.
      **Fatta il 2 novembre 2026**, ed entra nella 1.3.0 (una sola uscita invece di due). `renderer/garden/life.ts` (i compagni che passeggiano, le commissioni e le
      pose negli angoli, l'ospite che arriva, resta e se ne va), `scene.ts` (il vento a strisce sulle piante, l'acqua, il fumo del camino sullo sfondo, gli effetti
      degli angoli, petali, foglie e neve, le lucciole, i lampioni che tremolano), la pagina con un solo ciclo di `requestAnimationFrame` (30 fotogrammi al secondo
      quando qualcosa si muove, 15 altrimenti). Il saluto all'ospite passa dal processo principale (`greetGuest` → `Garden.welcomeGuest`), gli angoli nuovi arrivano
      con la fotografia (`newCorners`). Provata dal vivo con `test/vivo/giardino-vita.cjs`.

Il Riccio, già in `windows/` dal commit `5387d2e`, è uscito con la 1.3.0.

## Terza uscita: la 2.0 (insieme al Mac)

**Preparata il 13 novembre 2026** come `2.0.0` (`windows/package.json`): il numero salta da 1.3 a 2.0 per essere lo stesso del Mac (che passa dalla 0.11.0 alla 2.0.0);
da qui le due app escono insieme e con lo stesso numero. Ogni novità è stata fatta sui due lati nello stesso commit, con la parte comune nel contratto:

- la **Tartaruga**, sesta compagna, con la sua isola (`1e01fcf`); la **lepre** al posto dell'ospite tartaruga e la linguetta **«Scene»** dell'album (`4a2ac76`);
- i **compagni che usano le cose** del giardino, ventiquattro scene (`cac6a22`, `core/gardenInteractions.ts`);
- il **giro guidato** della prima apertura e le prime volte (`2204961`, `renderer/tour.ts`); la **prima figurina** a 50 minuti (`d36dab9`); la figurina di fine focus che non copre «Com'è andata?» (`bb69c1a`, `core/giftPlacement.ts`);
- le **statistiche**: le sessioni di oggi subito, l'andamento per giorno, le ore di ogni materia, i consigli solo in positivo, il riepilogo senza le facce (`c1972b8`, `d74d4d7`, `6d58737`, `35d34e9`);
- la **musica**: undici brani e un inizio diverso a ogni focus (`5423a1c`); 36 **frasi** riscritte (`5d847b3`); la **copertina** nuova dell'album (`66e3c8b`); gli **avatar** (`7bc8390`, `e5e5c0b`).

**Provata sull'app installata** con il flusso nuovo `prova-installer.yml` (macchine di GitHub x64 e ARM: installazione, avvio con una schermata, 22 copioni dal vivo, disinstallazione).
Ha trovato due guasti, corretti prima dell'uscita (`f5da9ab`): l'**installer ARM** saltava tutti gli `.exe` e `.dll` (il filtro ARM64 di 7-Zip, che l'estrattore dentro
l'installer non conosce: ora `ELECTRON_BUILDER_7Z_FILTER=BCJ`; la 1.3.0 per ARM ha probabilmente lo stesso guasto), e il **pulsante nella barra delle applicazioni**
che ricompariva con la scheda di benvenuto aperta. Rifatta la bozza `windows-v2.0.0` (tag su `f5da9ab`), riprovati gli installer della bozza: SHA-256 uguali, tutto passato.
Installer: x64 175 MB, ARM64 178 MB (la 1.3.0: 158 e 152). 376 prove della logica. Da provare a mano: il punto **L** di `PROVE_SU_WINDOWS.md`.
**Pubblicata il 13 novembre 2026** come [`windows-v2.0.0`](https://github.com/jaacopocoding/FocusFriends/releases/tag/windows-v2.0.0) (non firmata, non «Latest»), e subito dopo
la [`v2.0.0`](https://github.com/jaacopocoding/FocusFriends/releases/tag/v2.0.0) per Mac, che è la «Latest». I file pubblicati hanno gli SHA-256 dei file provati.

## Cose che possono andare storte (e come si scoprono presto)

| Rischio | Quando lo vediamo | Cosa faremo |
|---|---|---|
| La finestra trasparente intercetta i clic o consuma troppo | M1, prima di tutto il resto | Cambiare strategia (una finestra piccola per compagno) o i limiti di aggiornamento |
| App a schermo intero (giochi, video): il compagno resta sopra, o sparisce | M1 e M11 | Come il Mac per ora (resta sopra, si nasconde a mano); se alla prova su Windows dà fastidio, nasconderlo con una chiamata di sistema (vedi `windows/PROVE_SU_WINDOWS.md` §E) |
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
| Seconda uscita: il giardino (G0–G8, rifatta il 1° novembre 2026) | circa 35 (la prima parte, G0–G7, circa 30) |

Da usare con cautela: sono stime, e gli imprevisti sono quasi tutti in M1, M5 e M9. La prima settimana ne dirà di più di
qualunque numero scritto qui.

## Cosa serviva da te per cominciare (storico: tutto risolto tranne la firma)

1. **Electron va bene?** Sì: scelta la finestra unica trasparente (B) e confermata sul Mac.
2. **Una macchina con Windows**: c'è (un computer vero, usato per la prima prova).
3. **Il permesso di installare gli strumenti**: dato («installa le cose che devi installare»).
4. **Il font**: scelto Chewy, dopo un confronto misurato con Marker Felt (vedi M0).
5. **Firma del codice**: ancora da decidere (consiglio: partire senza e fare domanda a SignPath Foundation).
