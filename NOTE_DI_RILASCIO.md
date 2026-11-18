## FocusFriends 2.0.1

Un ritocco al giro guidato e tre correzioni. Esce insieme alla 2.0.1 per Windows.

**Novità della 2.0.1**
- **«Cliccami!!!»**: all'inizio del giro guidato il compagno non trema più. Ogni tanto si carica, fa un salto, atterra e fa un saltino più piccolo, con l'ombra che resta a terra (con «Riduci movimento» sta fermo).
- **«Ferma» subito dopo un focus finito.** Se premevi «Ferma» (o facevi partire un altro timer) nei secondi in cui si può ancora chiedere «+5 minuti», il focus finito veniva contato come interrotto: niente figurina e niente «Com'è andata?». Adesso conta come finito.
- **«Cancella tutto» con un timer in corso**: prima ferma il timer, così il focus in corso non ricompare nei dati appena cancellati.
- **Il giardino e «Da fare» con una voce rovinata.** Se una sola cosa del giardino o una sola voce di «Da fare» non si leggeva, veniva messo da parte tutto il file e si ripartiva da capo. Adesso si scarta solo quella voce, il resto resta, e il file com'era viene tenuto da parte (`giardino.corrotto-….json` o `dafare.corrotto-….json`), come già succedeva per le sessioni.

**Se aggiorni dalla 2.0.0**: niente cambia nei dati.

Per macOS 13 o successivo (Apple Silicon e Intel).

**Installazione**
1. Decomprimi lo zip e trascina `FocusFriends` in *Applicazioni* (sostituisci la versione che hai: i dati restano).
2. L'app non è firmata con un account sviluppatore Apple: la prima volta fai clic destro → **Apri** → **Apri**, oppure da Terminale:
   `xattr -dr com.apple.quarantine /Applications/FocusFriends.app`

Tutto resta sul tuo Mac: nessuna rete, nessun invio.

SHA-256 di `FocusFriends-2.0.1-macOS.zip`:
`ca2012f69787e9aeaf457283a824b1bee6768ae286933de015cf0248476a2315`

### La 2.0

La prima versione ufficiale: sei compagni, sei isole, l'album delle figurine e un giro guidato per chi apre l'app la prima volta.
(Dopo la 0.11.0 il numero salta a 2.0, lo stesso della versione per Windows: da qui le due app escono insieme e con lo stesso numero.)

**Novità della 2.0**
- **La Tartaruga**, la sesta compagna: cammina, mangia una fragola, dorme e ogni tanto si ritira nel guscio. **Durante un focus** avanza piano lungo un sentiero di sassi verso una bandierina, e a fine focus mangia la fragola che la aspetta lì. Ha trenta frasi sue («Piano piano si arriva») e si sblocca per ultima, a 200 focus pieni.
- **La sua isola**, la sesta, a destra di quella di Porcellino e sopra quella del Riccio, con la casa dal tetto a guscio, il suo verde oliva e sette figurine nuove (il sasso al sole, il cespo di lattuga, l'aiuola di fragole, la bandierina del traguardo, la lanterna di carta, il laghetto, il rifugio di paglia). Due angoli nuovi, e il coniglio e la rana vengono anche per la lattuga e il laghetto.
- **Il giro guidato.** Alla prima apertura, dopo il nome e il compagno, il compagno ti chiama («Cliccami!!!»): cliccandolo si apre la scheda e il giro ne spiega le parti una alla volta, il timer, il giardino, le statistiche, l'album e i compagni da sbloccare, con le immagini di come sono fatti. Si rifà da «Fai il giro» nel menu. La prima volta che serve, il compagno dice quanto manca alla prima figurina e dove trovarla, e il giardino mostra come si mettono le cose.
- **La prima figurina arriva prima**: con il primo focus pieno, 50 minuti di studio invece di 60 (le altre come prima, 8 minuti in più ognuna). La figurina di fine focus compare accanto al compagno senza coprire «Com'è andata?».
- **I compagni usano le cose del giardino.** Dopo una passeggiata il compagno va a una delle sue cose e la usa: il gattino dondola nell'amaca, il porcellino fa capolino dal tunnel, Ciccio fa il bagnetto, il riccio si tuffa nel mucchio di foglie, la tartaruga si scalda sul sasso, Pianty si fa annaffiare. Quattro scene disegnate per ogni compagno, ventiquattro in tutto; dopo un po' il compagno torna a passeggiare.
- **Le scene nell'album.** Una linguetta nuova, «Scene»: la prima volta che vedi una scena il giardino lo festeggia e la scena entra nell'album, con la sua didascalia. Quelle che mancano sono una sagoma, e toccandole l'album ti dice quale cosa serve.
- **L'album** ha una copertina nuova, la bussola fra gli allori con il tuo nome sulla targa e il conto delle figurine su una fascia di pergamena, e i titoli scritti a mano.
- **La lepre**: la tartaruga era un ospite e adesso è una compagna, quindi al suo posto arriva la lepre, per la sdraio e il picnic, di giorno, in primavera e in estate. Se la tartaruga ti aveva già salutato, la lepre la prima volta ti lascia un regalo nuovo.
- **Le statistiche**: in «Oggi» le sessioni si vedono subito, senza aprire niente. Nella settimana e nel mese c'è l'andamento per giorno, come quello dell'anno: scegli una materia e vedi solo i suoi giorni; passando sopra un giorno leggi quanto hai studiato, e cliccandolo lo apri. Ogni periodo mostra le ore di ogni materia, una riga ciascuna con la sua barra. I consigli su quando rendi meglio parlano del periodo che guardi e solo di quello che va bene. Il riepilogo in alto è più pulito: i giorni di fila, senza il conto delle facce.
- **Più musica**: i brani inclusi passano da cinque a undici, sempre di HoliznaCC0 in pubblico dominio, e ogni focus parte da un brano diverso, né l'ultimo ascoltato né quello del focus prima, anche dopo aver riaperto l'app.
- **Le frasi**: trentasei riscritte, più semplici e meno ripetute fra un compagno e l'altro.
- **Gli avatar** nei cerchi (la scheda di benvenuto, il menu, la pagina Avatar) sono meno ingranditi: la testa intera, con un po' del compagno attorno (per Pianty la rosetta con il viso, per la Tartaruga anche il guscio).
- **Il giardino è più fluido**: circa il 15% di lavoro in meno per ogni fotogramma.

**Se aggiorni dalla 0.11.0**
- Il giardino resta nello stesso file e nello stesso formato; le scene viste si aggiungono in `giardino.json` (`scenes`). **Non si perde niente.**
- Le sessioni, le impostazioni e la lista Da fare non cambiano.
- Lo zip passa da 53 a 79 MB (la Tartaruga, le scene e i brani nuovi).
