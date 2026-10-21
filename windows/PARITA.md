# Parità con l'app per Mac

Funzione per funzione: cosa fa l'app per Mac (`README.md` «Cosa fa» e `ARCHITECTURE.md` §3), cosa fa la versione per Windows,
e **come è stato verificato**. Il giardino non c'è nella prima uscita (vedi `PIANO_WINDOWS.md`, G1–G6).

**Prova su Windows (18 ottobre 2026):** una prova sommaria su un computer Windows vero con l'installer della CI: l'app si installa, parte e «funziona bene»,
circa 200 MB e 0 % di processore. **Le sigle W qui sotto non sono state spuntate una per una**: restano da fare con `PROVE_SU_WINDOWS.md`.

**Come leggere la colonna «Verifica»**

| Sigla | Significato |
|---|---|
| **P** | Prova automatica (`npm test`, 283 prove): la logica dà gli stessi risultati. Le prove «di contratto» confrontano con i risultati dell'app per Mac sugli stessi file. |
| **S** | Prova dal vivo sul Mac con l'app vera di Electron: eventi del mouse e tastiera simulati, schermate e misure (`FF_SELFTEST`). I copioni sono in `test/vivo/`. |
| **W** | **Solo su Windows**: non si può provare dal Mac. Il passo da fare è in `PROVE_SU_WINDOWS.md`. |
| **C** | Scritto nel codice, **senza una prova dedicata**: l'ho letto, non l'ho visto funzionare. |
| **=** | Uguale al Mac, per costruzione (stessi dati o stesso codice portato passo per passo). |
| **≠** | Diverso dal Mac **di proposito** o per un limite di Windows; il perché è scritto. |

## 1. Il compagno sul desktop

| Mac | Windows | Verifica |
|---|---|---|
| Finestra trasparente, sempre sopra, nell'angolo in basso a destra sopra il Dock | Una sola finestra trasparente grande quanto l'area di lavoro dello schermo, sempre sopra, il compagno parte in basso a destra sopra la barra delle applicazioni | S; i clic che passano davvero e la posizione sopra la barra: W |
| Si trascina ovunque; disegno «sollevato» con tremolio | Uguale; il cursore resta sulla presa (`pickedGrab`) | S |
| Clic solo sul disegno, non sul rettangolo | Il clic passa dietro dove il pixel è trasparente (`setIgnoreMouseEvents` con `forward`, maschera alfa) | S con eventi simulati; il sistema vero: **W** |
| Sopra tutti gli Spaces e sopra le app a schermo intero (`fullScreenAuxiliary`) | Sopra tutte le finestre (livello `screen-saver`). **Sopra le app a schermo intero:** come il Mac, non si nasconde da solo | ≠ (vedi §10) W |
| Su tutti gli Spaces | Windows non permette a una finestra di stare su tutti i desktop virtuali senza codice nativo: resta sul desktop in cui è nata | ≠ **W** (vedi §10) |
| Fumetto sempre sopra il disegno, di lato se manca posto | Uguale (stessa geometria) | P S |
| Nascondi / Mostra; fine di un focus lo rimette | Nel menu dell'area di notifica e nella scheda; a fine focus ricompare | S (nascondi e mostra); C (la ricomparsa a fine focus) |
| Cambio compagno (solo gli sbloccati) | Scheda e menu; i bloccati non si scelgono | P S |
| Nessuna icona nel Dock | Nessun pulsante nella barra delle applicazioni né in Alt+Tab (`skipTaskbar`, finestra non attivabile) | C; **W** |
| Più schermi: sul principale; lo si trascina dove si vuole | Una finestra che si sposta con il compagno da uno schermo all'altro (o dal menu «Schermo»); se lo schermo sparisce torna sul principale | P (geometria); S (due schermi finti); trascinamento vero e scala diversa tra due monitor: **W** |

## 2. Camminata, mangiare, dormire

| Mac | Windows | Verifica |
|---|---|---|
| 30 Hz mentre cammina, 1 Hz fermo o nascosto | Uguale | P (la logica); C (le frequenze) |
| 42 pt/s, rimbalzo ai bordi, specchio, soste (mangia 30 %, dorme 15 %, popcorning 12 %) | Uguale (stessa tabella di probabilità, stessi tempi) | P |
| Fermo mentre parla, mentre lo si trascina, con «Fermo» attivo | Uguale | P |
| Mangia 7–10 s a fine focus (Porcellino) | Uguale | P S |

## 3. Frasi

| Mac | Windows | Verifica |
|---|---|---|
| Prima frase dopo 5 s, poi ogni 40–110 s; più rade durante il focus | Uguale | P (intervalli e frequenze); C (i 5 secondi) |
| Mazzo mischiato senza ripetizioni; file dell'utente prima di quello incluso; frase di riserva | Uguale | P |
| Quattro frequenze (spesso, ogni tanto, raramente, mai) | Uguale | P |
| «Fai parlare», «Modifica le frasi…» (copia il file incluso e lo apre) | Menu e tocco sul compagno; il file si apre con l'editor predefinito di Windows | S; l'editor vero: **W** |
| Il file delle frasi è `~/Library/Application Support/FocusFriends/frasi_<pet>.txt` | `%APPDATA%\FocusFriends\frasi_<pet>.txt` | = |
| Il compagno ricorda le scadenze di oggi (o di domani) di «Da fare», al posto di una frase a caso, al massimo ogni 3 ore, mai durante un focus | Uguale: lo decide il processo principale quando la pagina chiede la frase | P (le frasi, sugli stessi dati del Mac) S |
| Saluti legati al momento (dalla 1.2): all'avvio, per fascia della giornata e con il nome («Buongiorno, Jacopo! Ieri hai studiato 2 h 40: si riparte?»), alla prima frase spontanea; il lunedì–mercoledì il riepilogo della settimana scorsa (una volta per settimana, `lastWeeklyRecap`); ogni tanto, al posto di una frase a caso, una frase «quando rendi meglio»; al risveglio dallo sleep dopo almeno un'ora «Rieccoti!…» | Uguale; `suspend` e `resume` di Windows al posto delle notifiche dello sleep del Mac; `lastWeeklyRecap` sta in `impostazioni.json` invece che in `UserDefaults` | P (saluti, risveglio, riepilogo e numeri: stessi testi del Mac su 9 cartelle di esempio, in 6 momenti fissi) S (`test/vivo/frasi-contesto.cjs`); il vero sleep: **W** |
| Traguardi a voce dopo la frase di fine focus (giorni di fila 3/7/14/30/60/100, focus 10…1000, ore 10…500, «un mese / un anno insieme»), una sola frase, mai coperta né sopra un'altra (aspetta che il fumetto finisca) | Uguale | P (gli stessi traguardi del Mac mano a mano che il registro cresce, e 294 anniversari su date inventate) S |

## 4. Il focus

| Mac | Windows | Verifica |
|---|---|---|
| «Cosa studi adesso?»: testo libero, fino a 6 recenti, «Senza materia», freccia indietro, ultima nota; Esc annulla | Uguale (finestra di dialogo dentro la finestra trasparente) | S |
| Motore: fine fissata sull'orologio, pausa che sposta la fine, «+5 minuti» anche prima della fine e in pausa | Uguale, nel processo principale (non si ferma con le finestre nascoste) | P S |
| Alla fine: avviso e 10 s di «Ancora 5 minuti?» con barretta | Uguale. **Suono: una campana generata da zero** (al posto di «Glass» di macOS) | S; il suono: **da ascoltare** |
| Sleep del computer: più di 10 s di salto = tempo da fermo | Uguale (la stessa regola, nel motore) | P; sleep vero: **W** |
| Pausa lunga dopo 4 focus (15 min, si azzera dopo 2 h), puntini del ciclo, si può spegnere | Uguale | P S |
| «Ferma / Riprendi», «Termina e salva», «Elimina questo focus» (con conferma), note (fino a 40 da 160 caratteri) | Uguale | P S |
| Orologio sotto il compagno: primi 2 minuti, ultimi 5, al passaggio del mouse (tendina) | Uguale | S |
| Crescita: Pianty a stadi, Ciccio nel nido, Porcellino con la carota, Gattino cammina; dopo «+5» resta all'ultimo stadio | Uguale | P S |
| «Com'è andata?» a fine focus: tre facce e una riga; non prende la tastiera; sparisce da sola | Uguale | P S; il fuoco che resta all'altra app: **W** |
| «Hai finito «…»?» a fine focus, se il focus è partito dal ▶ di una voce di «Da fare» ancora da fare: *Fatta* la segna, *Non ancora* la lascia; con «Chiedi com'è andata» spento la scheda ha solo questa domanda (dalla 1.2) | Uguale | P (`timer.test.ts`, `dafare.test.ts`) S (`test/vivo/hai-finito.cjs`) |
| Focus interrotto da chiusura improvvisa: si recupera all'avvio | Uguale (`in-corso.json` ogni 30 s); anche quando Windows chiude la sessione | P S |
| All'uscita un focus in corso si registra come interrotto | Uguale | P S |

## 5. La scheda e i menu

| Mac | Windows | Verifica |
|---|---|---|
| Icona nella barra dei menu; clic = scheda, tasto destro / ⌥-clic = menu classico | Icona nell'area di notifica; clic = scheda, tasto destro = menu completo. **Su Windows 11 l'icona nuova finisce nel menu «^» finché non la si trascina fuori**: il tasto destro sul compagno funziona comunque | W |
| Tasto destro o ctrl-clic sul compagno = scheda di fianco a lui, lo segue, passa dall'altro lato ai bordi | Tasto destro (non c'è il ctrl-clic su Windows); lo segue e passa dall'altro lato | S |
| Esc o un clic fuori la chiudono | Uguale | S |
| Pagina principale: compagni con lucchetti, durate 30/50/pausa, «Altri timer…», riquadri di oggi, impostazioni rapide, «Esci» | Uguale (senza il pulsante «Giardino», seconda uscita) | S |
| «Gira il timer»: quadrante a pomodoro 5–120 / 1–30, rotella, fino a 6 timer salvati per tipo | Uguale (anche con le frecce) | P S |
| Pagina del focus e della pausa (verde), facce per l'ultimo focus | Uguale | S |
| **Da fare** (dalla 1.1): riga nella scheda; lista divisa in scadute, oggi, prossime, senza data, con il «+» in alto; pagina «Nuova cosa» (nome, scadenza, materia) e «Modifica» toccando il testo di una voce (dalla 1.1.1); ▶ «Inizia un focus» (dalla 1.1.1 porta al quadrante «Gira il timer» per scegliere i minuti, e parte con la materia della voce; senza materia si chiede «Cosa studi adesso?») e × sotto il mouse; voci fatte ripiegate, tolte dopo 7 giorni | Uguale. Il calendario di «Scegli…» è disegnato nella scheda (quello di sistema si apre in una finestra a parte, che in una finestra trasparente e senza fuoco non è affidabile) | P (contratto su 4 cartelle di esempio, nei due versi) S (`test/vivo/dafare.cjs`) |
| Menu classico: Nascondi/Mostra, Fai parlare, Pomofocus, Statistiche, Il tuo nome, Chiedi com'è andata, Pausa lunga, Frequenza, Personaggio, Movimento, Avvia al login, Modifica le frasi, Esci | Tutte le voci, più **Schermo** (con più schermi) e i sottomenu di suono e musica | C (l'elenco); **W** (come si apre) |
| Tutto leggibile ai lettori di schermo | Pulsanti veri con etichette; tastiera completa | C; con un lettore vero (Narrator): **W** |
| Icona del compagno (la testa) | Stessa testa, 32 px | C; **W** |
| Aspetto «carta»; carattere Marker Felt (Wide) | Stesso disegno in SVG; **Chewy al posto di Marker Felt** (il più vicino tra 44 caratteri liberi, misurato contro l'originale), icone Lucide al posto di SF Symbols | ≠ voluta: le lettere non sono identiche |

## 6. Suoni

| Mac | Windows | Verifica |
|---|---|---|
| Pioggia, vento, rumore marrone sintetizzati, a 44 100 Hz | Lo stesso algoritmo (`NoiseSynth` portato) in un `AudioWorklet` | P (confronto con le misure del Mac: pioggia e marrone all'1 %, vento al 3 %) S |
| Dissolvenze di 2 s, anteprima di 3 s (musica 5 s), volumi 10/25/40/60 % | Uguale | P S |
| Solo durante un focus attivo, un sottofondo alla volta | Uguale | P S |
| Musica: 5 brani inclusi o una cartella (anche sottocartelle), coda mischiata | Uguale. I cinque brani inclusi sono `.m4a`; i formati riconosciuti nelle cartelle sono quelli del Mac (mp3, m4a, aac, wav, aif, aiff, flac, caf) | S; **che gli m4a si sentano, e se `aif`, `aiff` e `caf` suonano** (un brano che non si legge viene saltato): W |
| Se l'audio non parte lo dice il compagno | Uguale | S |
| — | **Nuovo:** dopo uno sleep, o se il sistema ferma l'audio (cuffie scollegate), il suono e la musica ripartono da soli se dovevano esserci | S (sleep simulato) |

## 7. Registro, statistiche, profilo

| Mac | Windows | Verifica |
|---|---|---|
| `sessioni.json` v3: scrittura atomica, migrazione da v0/v1/v2 con copia in `backup/`, file più nuovo in sola lettura, file rovinato messo da parte, recupero delle sessioni leggibili, copia giornaliera (ultime 7) | Uguale | P (contratto su 14 cartelle di esempio) |
| I file scritti da una app li legge l'altra | Provato nei due versi: Swift legge i file di Swift (contratto), **e Swift legge quelli scritti dal codice per Windows** (con migrazione, voti, note, accenti, emoji, virgolette, focus in corso fermo e profilo) | P (`ritorno.test.ts`, solo su un Mac) |
| Giorno «sull'orologio» (`localStart`): non cambia con il fuso o l'ora legale | Uguale. **Corretto in M11:** il fuso del computer ora si rilegge se cambia mentre l'app è aperta (prima restava quello di quando era partita) | P (`fusi.test.ts`: cambio d'ora a ottobre e marzo, Sydney, Lord Howe, fusi a mezz'ora) |
| Statistiche Oggi / Settimana / Mese, frecce, serie con giorno di ghiaccio, frasi «quando rendi meglio», diario, modifica e elimina, CSV, «Cancella tutto…» | Uguale (finestra vera, 560 × 660, creata alla richiesta e distrutta alla chiusura) | P (stessi testi e numeri) S; i dialoghi di sistema (salvataggio del CSV, conferma): **W** |
| Sblocco dei compagni a 20/50/100 focus pieni; chi usava già l'app li ha tutti; `developerMode` | Uguale (`developerMode` in `impostazioni.json` invece di `defaults write`) | P S |
| Primo avvio: nome e compagno; il nome nei titoli; «Il tuo nome…» | Uguale | S |
| Preferenze in `UserDefaults` | `impostazioni.json` (valori sbagliati = predefiniti) | ≠ P |
| Migrazione dalla vecchia app «Bonsy» | Non serve: Windows parte da zero | ≠ |
| `dafare.json`: voci ripulite alla lettura, fatte tolte dopo 7 giorni, file rovinato messo da parte, versione più nuova in sola lettura; «Cancella tutto» non lo tocca | Uguale | P (`contratto.test.ts`, `ritorno.test.ts`, `dafare.test.ts`) |

## 8. Sistema

| Mac | Windows | Verifica |
|---|---|---|
| Avvia al login (`SMAppService`) | `setLoginItemSettings`, attivo solo nell'app installata | S da sviluppo (disattivo); installata: **W** |
| Una copia sola | `requestSingleInstanceLock`; la seconda esce e la prima mostra il compagno | S |
| Esci: l'app chiude e registra il focus come interrotto | Uguale; anche alla chiusura della sessione di Windows (`session-end`) | S |
| Problemi con i dati detti dal compagno una volta sola | Uguale | P S |
| Registro degli arresti inattesi | `registro-app.log` (200 KB ×2): versioni, schermi (misure, scala, lato della barra), sleep e risveglio, eccezioni, processi caduti; niente dati personali | P S |
| App nativa, leggera | **Più pesante (Electron)**. **Misurato su Windows (18 ottobre 2026): circa 200 MB e 0 % di processore** (obiettivo 250 MB; sul Mac, con gli stessi processi, 590 MB). Da rimisurare con un focus e la pioggia accesi | ≠ misurato |
| `Info.plist`, firma ad-hoc | Installer NSIS per l'utente, x64 e ARM; **non firmato** (avviso SmartScreen) | ≠ vedi `RILASCIO.md` |

## 9. Fuso orario, ora legale, sleep

| Caso | Cosa succede | Verifica |
|---|---|---|
| Il computer va in sleep durante un focus | Il tempo del salto conta come tempo da fermo (regola dei 10 s) | P; sleep vero: **W** |
| Risveglio | Si rileggono fuso e schermi, la finestra si riadatta, il suono riparte se doveva suonare | S (simulato); **W** |
| Cambio di fuso o ora legale con l'app aperta | Le sessioni già registrate non cambiano giorno; quelle nuove usano il fuso nuovo | P; il cambio vero di Windows: **W** |
| Mezzanotte con la scheda o le statistiche aperte | «Oggi» si ricalcola quando la scheda si riapre, cambia la fase o cambia il registro; non allo scoccare della mezzanotte. Non l'ho confrontato riga per riga con il Mac | C |
| Coperchio chiuso | Come lo sleep (Windows manda gli stessi messaggi) | **W** |
| Schermo bloccato / sbloccato | Allo sblocco: come al risveglio | S (simulato) **W** |

## 10. Differenze volute o limiti di Windows (da decidere dopo la prova su una macchina vera)

1. **App a schermo intero (giochi, video).** Il Mac lascia il compagno sopra anche alle app a schermo intero; qui è lo stesso.
   Rilevare un'app a schermo intero su Windows vuol dire interrogare il sistema con codice nativo (`SHQueryUserNotificationState`),
   che Electron non offre: servirebbe un componente nativo o un processo in più (e uno script PowerShell lanciato da un'app
   non firmata rischia di far scattare l'antivirus). **Non l'ho aggiunto alla cieca.** Rimedio oggi: *Nascondi* dal menu.
   Se alla prova su Windows dà fastidio, le strade sono in `PROVE_SU_WINDOWS.md`.
2. **Desktop virtuali.** `setVisibleOnAllWorkspaces` non fa niente su Windows: cambiando desktop il compagno resta sull'altro.
   Da vedere alla prova: cosa succede toccando l'icona dall'altro desktop (la scheda sta nella finestra del compagno).
   Idea già pronta se serve: la pagina sa quando la finestra non è sul desktop corrente (`visibilitychange`) e il processo
   principale può nasconderla e rimostrarla, cosa che, da quanto ricordo, su Windows la porta sul desktop attuale (da verificare).
3. **Carattere e icone** liberi al posto di Marker Felt e SF Symbols (vedi §5).
4. **Memoria.** Electron pesa più di Swift: da misurare su Windows; leve già individuate in `PIANO_WINDOWS.md` (M9).
