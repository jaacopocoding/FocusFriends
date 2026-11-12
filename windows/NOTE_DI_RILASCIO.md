## FocusFriends per Windows 1.4.0

Il compagno che ti fa compagnia mentre studi, adesso anche su Windows 10 e 11 (Intel/AMD e ARM): un personaggio che cammina sul desktop,
un timer Pomofocus con la sua schermata del focus, i suoni di sottofondo, le statistiche e i compagni da sbloccare studiando.
Stessi dati, stesse regole e stesso aspetto dell'[app per Mac](https://github.com/jaacopocoding/FocusFriends#readme): i file di studio si possono
leggere con l'una e con l'altra.

### Novità della 1.4

**La Tartaruga**, la sesta compagna: cammina, mangia una fragola, dorme e ogni tanto si ritira nel guscio. **Durante un focus** avanza piano lungo un
sentiero di sassi verso una bandierina, e a fine focus mangia la fragola che la aspetta lì. Ha trenta frasi sue («Piano piano si arriva») e si sblocca
per ultima, a 200 focus pieni.

- **Il giro guidato.** Alla prima apertura, dopo il nome e il compagno, il compagno ti chiama («Cliccami!!!»): cliccandolo si apre la
  scheda e il giro ne spiega le parti una alla volta, il timer, il giardino, le statistiche, l'album e i compagni da sbloccare, con le
  immagini di come sono fatti. Si rifà da «Fai il giro» nel menu. E la prima volta che serve il compagno dice quanto manca alla prima
  figurina e dove trovarla, e il giardino mostra come si mettono le cose. La prima figurina arriva con il primo focus pieno: 50 minuti di studio
  invece di 60 (le altre come prima, 8 minuti in più ognuna).
- **La sua isola**, la sesta, a destra di quella di Porcellino e sopra quella del Riccio, con la casa dal tetto a guscio, il suo verde oliva e sette
  figurine nuove (il sasso al sole, il cespo di lattuga, l'aiuola di fragole, la bandierina del traguardo, la lanterna di carta, il laghetto, il rifugio
  di paglia). Due angoli nuovi, e il coniglio e la rana vengono anche per la lattuga e il laghetto.
- **I compagni usano le cose del giardino.** Dopo una passeggiata il compagno va a una delle sue cose e la usa: il gattino dondola nell'amaca, il
  porcellino fa capolino dal tunnel, Ciccio fa il bagnetto, il riccio si tuffa nel mucchio di foglie, la tartaruga si scalda sul sasso, Pianty si fa annaffiare.
  Quattro scene disegnate per ogni compagno, ventiquattro in tutto; dopo un po' il compagno torna a passeggiare.
- **Le scene nell'album.** Una linguetta nuova, «Scene»: la prima volta che vedi una scena il giardino lo festeggia e la scena entra nell'album, con la
  sua didascalia. Quelle che mancano sono una sagoma, e toccandole l'album ti dice quale cosa serve.
- **La lepre**: la tartaruga era un ospite e adesso è una compagna, quindi al suo posto arriva la lepre, per la sdraio e il picnic, di giorno, in
  primavera e in estate. Se la tartaruga ti aveva già salutato, la lepre la prima volta ti lascia un regalo nuovo.
- **Le statistiche**: in «Oggi» le sessioni si vedono subito, senza aprire niente. Nella settimana e nel mese c'è l'andamento per giorno, come quello dell'anno: scegli una materia
  e vedi solo i suoi giorni; passando sopra un giorno leggi quanto hai studiato, e cliccandolo lo apri. I consigli su quando rendi meglio parlano del periodo che guardi e solo
  di quello che va bene; per un giorno solo dicono quale materia è andata bene. Ogni periodo mostra le ore di ogni materia, una riga ciascuna con la sua barra.
- **Più musica**: i brani inclusi passano da cinque a undici, sempre di HoliznaCC0 in pubblico dominio, e ogni focus parte da un brano diverso,
  né l'ultimo ascoltato né quello del focus prima, anche dopo aver riaperto l'app.
- **Le frasi**: trentasei riscritte, più semplici e meno ripetute fra un compagno e l'altro.
- **Gli avatar** nel cerchio si vedono per intero, non più solo la testa da vicino, e la scheda di benvenuto si allarga per i sei compagni.

Il giardino resta nello stesso file e nello stesso formato: le scene viste si aggiungono in `giardino.json` (`scenes`). Si installa sopra la 1.3 e
non si perde niente.

### Novità della 1.3

**Il giardino.** Studiando trovi le figurine: a fine focus (completato, di almeno 20 minuti) i minuti si mettono da parte, e quando bastano esce una
figurina (la prima dopo 60 minuti di studio, ognuna dopo qualche minuto in più). Il compagno lo dice nella frase di fine focus («Nuova figurina: Lavanda
(n. 6). La prossima tra 68 minuti di studio.») e la figurina compare accanto a lui. Non esce mai un doppione, e con i giorni di fila e i focus lunghi
quelle rare sono più probabili. Quanto manca alla prossima lo vedi sempre nella scheda, sotto «Album».

- **Le isole.** Ogni compagno ha la sua isola, con la sua casa e il suo sentiero, unite da ponti: un mondo solo, che si guarda da vicino o da lontano
  (la rotellina ingrandisce, trascinando ci si sposta, «M» mostra tutte le isole). Quelle dei compagni non ancora sbloccati sono al buio, con un lucchetto.
  Quando sblocchi un compagno, alla prima entrata nel giardino si costruisce il ponte verso la sua isola e arriva un regalo di benvenuto.
- **Ciò che trovi è tuo.** Dalla cassetta «Da mettere» trascini le cose sull'isola (le tessere si fanno verdi dove ci stanno), quante volte vuoi; si
  spostano, si girano (R, due tocchi o il tasto destro) e si tolgono. Le cose di un animale stanno sulla sua isola. La staccionata si unisce da sola.
- **L'album.** Le figurine si raccolgono in un libro: una copertina da aprire, le pagine che girano, le sagome di quelle che mancano, un sigillo d'oro
  sulle doppie pagine complete (che allargano le isole). Si apre dalla scheda o dal giardino.
- **La luce e le stagioni.** Il giardino segue l'ora (la sera si accendono le finestre e i lampioni) e la stagione (d'inverno c'è la neve).
- **La vita sull'isola.** Il compagno passeggia e, se gli hai preparato un angolo (la cuccia con il cuscino, il tavolino con la sdraio, i fiori…), ci va a
  fare la sua posa; quando un angolo si forma, le stelline lo festeggiano. Le piante si muovono col vento, cadono petali, foglie o neve, la sera arrivano le
  lucciole. Ogni tanto passa un ospite, attirato da qualcosa che hai messo: ha una stellina sopra, e toccandolo ti saluta (la prima volta ti lascia un regalo).
  Con «Riduci movimento» di Windows niente vento né particelle.
- **Il Riccio**, il quinto compagno: cammina, mangia, dorme e si arrotola a palla; durante un focus la schiena si riempie di cose d'autunno. Si sblocca
  per ultimo, a 150 focus pieni.

Il giardino sta in `%APPDATA%\FocusFriends\giardino.json`, nello stesso formato dell'app per Mac; «Cancella tutto…» nelle statistiche lo toglie con il resto.

### Novità della 1.2

**La scheda «Anno» nelle statistiche.** Accanto a Oggi, Settimana e Mese c'è *Anno*: l'anno come una mappa con un quadratino per giorno, più scuro dove hai studiato di più (meno di 30 minuti, meno di 90, meno di 3 ore, 3 ore o più). Passando sopra un giorno si legge il tempo e quanti focus; cliccandolo si apre in *Oggi*, con le sue sessioni. Sotto la mappa, la serie di giorni di fila più lunga dell'anno, il giorno più forte e il mese migliore, e l'andamento per settimana, di tutte le materie o di una sola (le più studiate dell'anno, da scegliere con un clic). Si ricava tutto dai dati che già hai: nessun file nuovo.

**Saluti legati al momento e numeri a voce.** Il compagno ti saluta quando apri l'app, secondo l'ora e con il tuo nome («Buongiorno, Jacopo! Ieri hai studiato 2 h 40: si riparte?»), e quando il computer torna da uno sleep di almeno un'ora («Rieccoti!»). Il lunedì (fino al mercoledì) racconta com'è andata la settimana scorsa («Settimana scorsa: 3 h 40 in 3 giorni, 3 focus. Il giorno più forte: mercoledì (2 h 10).»), ogni tanto, al posto di una frase a caso, ti dice quando rendi meglio, e dopo la frase di fine focus festeggia i traguardi: giorni di fila, numero di focus, ore di studio, «Oggi è un mese che studiamo insieme». Mai durante un focus. Con «Frasi: Mai» tace, tranne i traguardi, che fanno parte del messaggio di fine focus. Le frasi non si coprono più a vicenda (l'annuncio dei compagni sbloccati aspetta che il fumetto finisca) e il fumetto sta sopra la scheda «Com'è andata?», così si legge sempre per intero. L'unica cosa nuova nei dati è quale riepilogo della settimana hai già sentito (`lastWeeklyRecap` in `impostazioni.json`).

**«Hai finito?» a fine focus.** Se un focus è partito dal ▶ di una voce di *Da fare*, quando finisce la scheda di fine focus chiede anche «Hai finito «Riassunto del capitolo 7»?» con *Fatta* e *Non ancora*. *Fatta* segna la voce e il compagno ti fa i complimenti; *Non ancora* la lascia in lista. Se hai spento «Chiedi com'è andata», la scheda ha solo questa domanda. Se fermi il focus prima della fine non chiede niente. I dati non cambiano.

### Novità della 1.1

**Da fare.** Nella scheda c'è una riga nuova, *Da fare*: una lista di cose da ricordare, con una scadenza (un giorno) e una materia,
tutte e due facoltative.

- Il **«+»** in alto a destra apre la pagina *Nuova cosa*: il nome, la scadenza (*Oggi*, *Domani*, *Fra una settimana* o un giorno dal calendario) e la materia (si scrive, o si tocca una di quelle usate di recente), poi *Aggiungi*. *Annulla*, la freccia o Esc tornano alla lista senza salvare.
- **Toccando il testo di una voce** si apre la stessa pagina, *Modifica*, già compilata. I nomi lunghi vanno a capo.
- La lista è divisa in *Scadute*, *Oggi*, *Prossime* e *Senza data*. Il cerchio segna una voce come fatta (sparisce dopo una settimana).
- Passando sopra una voce compaiono ▶ *Inizia un focus* e × *Togli*. Il ▶ porta al quadrante *Gira il timer*, con «Focus per…» in alto: scegli i minuti e il focus parte con la materia della voce (senza materia, dopo i minuti si apre «Cosa studi adesso?»).
- Il compagno ogni tanto ricorda le scadenze di oggi o di domani, mai durante un focus.

(La 1.1.1 è la 1.1 con il «+» e la modifica delle voci: la 1.1.0 aggiungeva le cose scrivendo il nome in un campo sopra la lista.)

Le voci stanno in `%APPDATA%\FocusFriends\dafare.json`, nello stesso formato dell'app per Mac. Si installa sopra la versione di prima e i dati restano.

Comprende anche le correzioni della 1.0.1 (per chi non l'ha installata), che non si vedono ma rendono l'app più solida:

- **Più chiusa in sé**: le finestre dell'app non aprono mai pagine web né finestre nuove, e non ottengono permessi (microfono, fotocamera, posizione, notifiche): l'app non ne usa nessuno.
- **Le opzioni di prova non cambiano più l'app**: quelle usate solo per provarla durante lo sviluppo (per esempio saltare la conferma di «Cancella tutto…») hanno effetto soltanto con l'interruttore delle prove.
- Le prove dal vivo di chi sviluppa l'app sono ora nel repository (`windows/test/vivo/`).

### Come si installa

1. Scarica l'installer giusto: **`FocusFriends-Windows-<versione>-x64-Setup.exe`** per i computer Intel e AMD, **`…-arm64-Setup.exe`** per quelli ARM
   (per esempio Surface Pro e i portatili Copilot+).
2. Lancialo: si installa solo per te (nessun permesso di amministratore) e si apre da solo.
3. **Il programma non è firmato**: la prima volta Windows può mostrare «Windows ha protetto il PC». Scegli *Ulteriori informazioni* → *Esegui comunque*.
4. Il compagno compare in basso a destra. L'icona è nell'area di notifica (su Windows 11, nel menu «^» finché non la trascini fuori):
   clic = la scheda, tasto destro = il menu. Il tasto destro sul compagno apre la scheda accanto a lui.

I dati di studio e le impostazioni stanno in `%APPDATA%\FocusFriends`; **restano anche se togli l'app**. Nessuna rete, nessun invio. Per aggiornare basta
lanciare l'installer nuovo: si installa sopra e i dati restano.

### Come controllare il file scaricato

Il checksum SHA-256 di ogni installer è in `SHA256SUMS.txt`. Da PowerShell:

```powershell
Get-FileHash .\FocusFriends-Windows-<versione>-x64-Setup.exe -Algorithm SHA256
```

### Cosa non c'è (ancora)

- **Sopra le app a schermo intero**: come sul Mac, il compagno resta sopra anche a un video o a una presentazione a schermo intero. Si nasconde dal menu.
- **Desktop virtuali**: Windows non lo lascia comparire su tutti; sta sul desktop in cui l'hai aperto.

### Se qualcosa non va

Apri una [segnalazione](https://github.com/jaacopocoding/FocusFriends/issues) e, se puoi, allega `%APPDATA%\FocusFriends\registro-app.log`: contiene la
versione di Windows, le misure degli schermi e gli errori, e **non** contiene nomi, materie o note.
