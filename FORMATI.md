# FocusFriends — formati dei dati

I file che l'app scrive e legge, e le regole con cui li tratta. Vale per **tutte e due le versioni** (Mac e Windows): chi
scrive una nuova versione dell'app deve leggere e scrivere questi file nello stesso modo, così i dati sono compatibili e
le prove di confronto (`tests/fixtures/`) hanno un punto fermo.

Fonte: il codice Swift della versione per Mac (`SessionLog.swift`, `Profile.swift`, `Garden.swift`, `AmbientSound.swift`,
`MusicLibrary.swift`, `Chattiness.swift`, `CustomTimers.swift`, `ToDo.swift`). Dove questo documento e il codice non sono d'accordo,
vale il codice, e va corretto il documento.

## 1. Dove stanno

| Sistema | Cartella dei dati |
|---|---|
| Mac | `~/Library/Application Support/FocusFriends/` |
| Windows | `%APPDATA%\FocusFriends\` (cioè `C:\Users\<nome>\AppData\Roaming\FocusFriends\`) |

```
FocusFriends/
├── sessioni.json              le sessioni di studio (versione 3)
├── in-corso.json              il focus in corso (c'è solo mentre dura)
├── profilo.json               nome, introduzione vista, compagni sbloccati
├── giardino.json              il giardino (oggetti, copie, posizioni) — seconda uscita su Windows
├── impostazioni.json          le preferenze (solo Windows; sul Mac stanno in UserDefaults)
├── dafare.json                le cose da fare
├── registro-app.log           (solo Windows) cosa ha fatto l'app: avvio, chiusura, errori; senza dati personali; l'altro è registro-app.1.log
├── frasi_<personaggio>.txt    le frasi dell'utente (facoltative)
├── sessioni.corrotto-<epoch>.json   un file di sessioni messo da parte perché rovinato
├── profilo.corrotto-<epoch>.json    idem per il profilo
├── giardino.corrotto-<epoch>.json   idem per il giardino
├── dafare.corrotto-<epoch>.json     idem per le cose da fare
└── backup/
    ├── sessioni-AAAA-MM-GG.json     una copia al giorno (le ultime 7)
    └── sessioni-formato<N>.json     la copia intatta di un file di una versione precedente (N = 0, 1, 2)
```

- **Codifica:** UTF-8, senza BOM, a capo `\n`.
- **Scrittura atomica:** si scrive un file temporaneo nella stessa cartella e lo si rinomina sopra quello vecchio
  (su Windows la rinomina sostituisce il file esistente). Un'app che si chiude a metà non deve lasciare un file mozzo.
- **Un solo scrittore.** Le due app non sono pensate per usare la stessa cartella nello stesso momento (per esempio in
  una cartella sincronizzata): i formati sono compatibili, ma non c'è nessun blocco tra un'app e l'altra.
- **Formattazione:** il Mac scrive JSON con indentazione di 2 spazi e chiavi in ordine alfabetico. Per leggere non conta;
  chi scrive può usare lo stesso stile per avere differenze pulite.

## 2. `sessioni.json`

```json
{
  "version" : 3,
  "sessions" : [
    {
      "id" : "00000000-0000-4000-8000-000000000001",
      "start" : "2026-10-14T07:00:00Z",
      "localStart" : "2026-10-14T09:00",
      "seconds" : 3000,
      "plannedMinutes" : 50,
      "completed" : true,
      "subject" : "Anatomia",
      "pet" : "pianty",
      "rating" : "good",
      "note" : "cap. 4, nervi cranici",
      "notes" : ["rivedere l'esercizio 4"]
    }
  ]
}
```

| Campo | Tipo | Obbligatorio | Note |
|---|---|---|---|
| `id` | testo (UUID) | sì | Il Mac lo scrive in maiuscolo; in lettura le maiuscole non contano. Chi riscrive un file **conserva il testo com'era**. |
| `start` | testo (data UTC) | sì | ISO 8601 **con secondi interi e `Z`**, senza frazioni: `2026-10-14T07:00:00Z`. (In JavaScript `toISOString()` aggiunge i millisecondi: vanno tolti.) |
| `localStart` | testo | no (formato 1+) | L'ora «sull'orologio» in cui è iniziato, **senza fuso**: `AAAA-MM-GGThh:mm`, 16 caratteri esatti. **Tutte le statistiche usano questa**, così una sessione non cambia giorno se cambia il fuso orario o l'ora legale. Se manca o non è nel formato, si usa `start`. |
| `seconds` | intero | sì | Secondi di studio davvero svolti (per un focus interrotto meno di quelli previsti). |
| `plannedMinutes` | intero | sì | Minuti previsti. |
| `completed` | vero/falso | sì | Il focus è arrivato alla fine. |
| `subject` | testo | no | La materia, già pulita (vedi §2.3). |
| `pet` | testo | no | Il compagno con cui è stata fatta (`pianty`, `porcellino`, `ciccio`, `gattino`). Manca nelle sessioni vecchie. |
| `rating` | `good` / `soso` / `poor` | no (formato 2+) | «Com'è andata?». **Un valore sconosciuto si ignora** (non deve rendere illeggibile il file). |
| `note` | testo | no (formato 2+) | La riga «cosa hai fatto», al massimo 80 caratteri. |
| `notes` | elenco di testi | no (formato 3) | Le note scritte durante il focus, al massimo 40 da 160 caratteri. |

I campi facoltativi **non compaiono** nel file quando sono vuoti (non si scrive `null`). Le sessioni stanno in ordine di `start`.

### 2.1 Le versioni

| Versione | Com'è fatto |
|---|---|
| 0 | Una lista di sessioni, senza involucro (`[ {…}, {…} ]`) |
| 1 | `{"version": 1, "sessions": [...]}`, con `localStart` |
| 2 | più `rating` e `note` |
| 3 | più `notes` (**la versione che si scrive**) |

### 2.2 Come si legge (nell'ordine)

1. **Il file non c'è:** nessuna sessione, e non è un problema.
2. **C'è ma non si può leggere** (permessi): si lavora in **sola lettura** e si avvisa; il file non si tocca mai.
3. **Involucro con `version` e `sessions`:**
   - `version` **maggiore** di 3: si legge, si lavora in **sola lettura** e si avvisa (i nuovi focus non si salvano);
   - `version` **minore** di 3: si legge, si salva una **copia intatta** in `backup/sessioni-formato<N>.json` e si riscrive in versione 3.
4. **Una lista nuda** (versione 0): copia intatta in `backup/sessioni-formato0.json`, poi si riscrive in versione 3.
5. **Qualche sessione non si legge** (per esempio manca `seconds`): si leggono **una per una**, si tengono quelle buone e si
   conta quante sono state scartate. Se la versione è più nuova di 3: sola lettura. Se non se n'è scartata nessuna: si riscrive.
   Altrimenti si salva il file com'era come `sessioni.corrotto-<epoch>.json` (`<epoch>` = secondi dal 1970), si avvisa («N sessioni non erano
   leggibili…») e si riscrive con quelle buone. **Se la copia non si riesce a salvare, sola lettura.**
6. **Non è nemmeno un elenco di sessioni:** il file si sposta in `sessioni.corrotto-<epoch>.json`, si avvisa e si riparte
   da vuoto. **Se non si riesce a spostarlo, sola lettura** (non si sovrascrive mai).

Dopo la lettura si **normalizza**: ogni materia ha una sola scrittura (vince quella della sessione **più recente**, e vale
per tutte le sessioni con la stessa chiave, vedi §2.3), e dove manca `localStart` lo si calcola dall'istante `start` nel fuso di quel momento.
Se la normalizzazione cambia qualcosa (e non si è in sola lettura) si riscrive.

**In sola lettura** nessuna operazione scrive (né nuove sessioni, né modifiche, né cancellazioni di una sessione): le viste
mostrano comunque quello che c'è. L'unica eccezione è «Cancella tutto», che è una scelta esplicita: toglie i file e da
lì si riparte da vuoto, anche se prima si era in sola lettura.

### 2.3 Come si scrive

- **Una sessione si registra solo se dura almeno 60 secondi** (`seconds >= 60`).
- La materia si pulisce (`Subject.clean`): le parole separate da qualunque spazio o a capo si uniscono con **uno spazio solo**,
  al massimo **40 caratteri**, vuota = nessuna materia. (Non toglie i caratteri di controllo.)
- Se esiste già una materia con la **stessa chiave**, si usa la sua scrittura più recente. La chiave è il testo senza
  maiuscole e senza accenti, secondo le regole dell'italiano (`Anatomia`, `anatomia` e `ANATOMIA` sono la stessa;
  `Fisica` e `Física` pure).
- Le note (`note`, `notes`) si puliscono togliendo i caratteri di controllo da ogni parola e unendo con uno spazio; le
  vuote si scartano. `notes` vuoto = il campo non c'è.
- `localStart` si calcola nel fuso del computer in quel momento.
- Ogni modifica riscrive **tutto il file** (atomicamente). Prima della **prima modifica della giornata** si copia il file
  com'era in `backup/sessioni-AAAA-MM-GG.json` (data di oggi nel fuso del computer), e si tengono solo le **ultime 7** (ordinando i nomi).
- **«Cancella tutto»** toglie `sessioni.json`, `in-corso.json` e la cartella `backup/`; l'app toglie anche `profilo.json` e `giardino.json`.

### 2.4 I giorni e le settimane

Le statistiche contano sul calendario **gregoriano**, con la **settimana che parte dal lunedì** e almeno 4 giorni nella prima
settimana dell'anno, e usano `localStart` (non l'istante assoluto). Un giorno va da mezzanotte a mezzanotte «sull'orologio».

## 3. `in-corso.json`

Il focus in corso, per non perderlo se l'app si chiude di colpo. Si crea all'avvio di un focus e **sparisce** quando
finisce (o viene eliminato).

```json
{
  "start" : "2026-10-14T07:00:00Z",
  "plannedMinutes" : 50,
  "subject" : "Anatomia",
  "pet" : "pianty",
  "lastSeen" : "2026-10-14T07:21:30Z",
  "notes" : ["rivedere l'esercizio 4"],
  "pausedSeconds" : 120,
  "pausedSince" : "2026-10-14T07:20:00Z"
}
```

- `start`, `plannedMinutes`, `lastSeen`: obbligatori. Gli altri no (`subject`, `pet`, `notes`, `pausedSeconds`, `pausedSince`).
- `lastSeen` si aggiorna al massimo **ogni 30 secondi** mentre il timer va.
- `pausedSeconds`: i secondi in cui il timer è stato fermo (le pause già finite). `pausedSince`: da quando è fermo adesso
  (assente = sta andando). Quando si aggiorna lo stesso focus (per esempio con «+5 minuti») il tempo fermo si conserva
  (lo stesso focus = `start` che differisce di meno di 1 secondo).
- Le note si salvano subito, appena scritte.

**Recupero all'avvio** (`recoverInterrupted`): se il file c'è, la sessione recuperata ha

```
fermo    = pausedSeconds + (pausedSince ? max(0, lastSeen − pausedSince) : 0)
secondi  = max(0, floor(lastSeen − start − fermo))
secondi  = min(secondi, plannedMinutes × 60)
```

ed è registrata con `completed = false` (con le stesse regole di §2.3, quindi **sotto i 60 secondi non si registra**).
Il file `in-corso.json` si toglie solo se la sessione è stata aggiunta o se il registro non è in sola lettura (se lo è, resta
dov'è).

## 4. `profilo.json`

```json
{
  "version" : 1,
  "name" : "Jacopo",
  "introSeen" : true,
  "unlocked" : ["gattino", "pianty", "porcellino"],
  "firstCompanion" : "pianty"
}
```

| Campo | Obbligatorio | Note |
|---|---|---|
| `version` | **sì** | 1 |
| `introSeen` | **sì** | La scheda di introduzione è già stata mostrata. |
| `name` | no | Pulito: spazi in eccesso e caratteri di controllo tolti (lo spazio resta), al massimo **24** caratteri, vuoto = nessun nome. Le maiuscole restano com'erano. |
| `unlocked` | no | I compagni sbloccati, in ordine alfabetico. **Assente = niente è bloccato** (chi usava già l'app, o chi non ha ancora scelto). |
| `firstCompanion` | no | Il compagno scelto all'inizio: gli altri si sbloccano dopo di lui. |

- Se `version` o `introSeen` **mancano**, il file è considerato **rovinato** (è un errore di lettura, non un valore di
  riserva): vedi sotto.
- Illeggibile (permessi): si lavora in sola lettura e si avvisa. Rovinato: si sposta in `profilo.corrotto-<epoch>.json`,
  si avvisa e si riparte da vuoto (se non si riesce a spostarlo: sola lettura).
- Non c'è controllo sulla versione: la 1 è l'unica.
- Regole d'uso: `introSeen` vero e `unlocked` assente all'avvio → si sbloccano **tutti** i compagni (chi c'era già li tiene
  tutti). Il primo compagno si sceglie **una volta** (solo se `unlocked` è assente) e lascia `unlocked = [primo]`. Gli
  sblocchi (`unlock`) si **aggiungono** e non si tolgono mai, nemmeno se poi si cancellano delle sessioni. «Cancella tutto»
  toglie il file.
- **Modalità sviluppatore** (`developerMode` nelle impostazioni): tutti i compagni (e gli oggetti del giardino) risultano
  sbloccati **senza scrivere niente** nel profilo.

### 4.1 Quando si sbloccano i compagni (`CompanionRewards`)

Un «focus pieno» sono **50 minuti** di studio (si sommano tutte le sessioni, interrotte comprese: secondi totali ÷ 3000,
arrotondati per difetto). L'ordine degli sblocchi è: prima il compagno scelto all'inizio, poi gli altri **nell'ordine dei
personaggi** (`pianty`, `porcellino`, `ciccio`, `gattino`). Soglie per posizione: 0, 20, 50, 100 focus pieni (e 50 in più per ogni posizione dopo la quarta).

## 5. `giardino.json` (seconda uscita su Windows)

Versione 4 (Mac, dopo la 0.10.0): **più isole, una per compagno**. L'id di un'isola è l'id del compagno (`pianty`, `porcellino`, `ciccio`, `gattino`, sempre in quest'ordine
e sempre nelle stesse posizioni sulla mappa). Ogni copia in `placements` dice su quale isola sta (`island`), e c'è l'isola di casa (`home`: quella del compagno scelto all'inizio, o
per chi usava già l'app quella del compagno in uso). Il resto è come nella 3; chi apre un file della 3 trova tutte le copie sull'isola di casa (la scelta della casa si fa al primo
avvio con la versione nuova: finché non c'è, le copie senza `island` stanno sull'isola `pianty`, che poi seguono la casa) e il vecchio file si tiene come `giardino-formato3.json`.
Per ora l'app mostra una sola isola (quella di casa): le altre arrivano nei prossimi passi (sono al buio finché non si sblocca il compagno, e il ponte si costruisce alla
prima entrata nel giardino dopo averlo sbloccato).

Versione 3 (Mac 0.10.0): il giardino non ha più punti né negozio né prato libero: si riempie con le figurine trovate a fine focus
(`GardenDrops.swift`), ognuna con le sue copie, che stanno sulle tessere di un'isola (`GardenGrid.swift`).

```json
{
  "version" : 4,
  "home" : "gattino",
  "drops" : { "found" : { "margherite" : 2, "lavanda" : 1 }, "nothingInARow" : 0, "sinceRare" : 3, "sinceLegendary" : 11 },
  "lastRolled" : "5B0C2A4E-6D1F-4C8B-9E27-3A7D41C0F8B2",
  "unseen" : ["lavanda"],
  "pendingGifts" : 0,
  "legacySpent" : null,
  "placements" : [
    { "id" : "00000000-0000-4000-8000-0000000000A1", "item" : "margherite", "island" : "gattino", "col" : 4, "row" : 1, "turned" : false }
  ],
  "companions" : { "gattino" : { "col" : 3, "row" : 4 } },
  "corners" : ["te", "orto"],
  "guests" : { "riccio" : { "first" : "2026-10-26", "visits" : 2, "reason" : "Funghi" } }
}
```

- `drops.found`: quante copie si sono trovate di ogni oggetto (chi non c'è non è stato trovato); la «dotazione» (gli oggetti con prezzo 0 nel catalogo) c'è
  fin dall'inizio, con una copia. `nothingInARow`, `sinceRare`, `sinceLegendary`: i contatori delle garanzie.
- `lastRolled`: l'identificativo dell'ultimo focus che ha tirato (lo stesso focus non tira due volte). `unseen`: gli oggetti trovati e non ancora visti nell'album.
- `pendingGifts`: i regali da aprire che vengono dalla conversione dei punti. `legacySpent`: i punti spesi nel formato 1, finché i punti non sono stati
  convertiti (poi `null`).
- **L'isola**: una griglia quadrata di `n × n` tessere, `col` verso destra e in basso, `row` verso sinistra e in basso, (0, 0) l'angolo in fondo. `n` è
  **8** più il numero di doppie pagine dell'album complete (tutte le figurine trovate), al massimo **10** (e mai meno di quanto serve a quello che c'è già sopra).
  Il **sentiero** sono le tessere `row = 3` con `col` da 0 a 3, `col = 3` con `row` da 3 a 5, e `row = 5` con `col ≥ 3`: non cambia quando l'isola si
  allarga (si allunga soltanto l'ultimo pezzo) e non ci si mette niente sopra.
- `home`: l'isola di casa; assente nei file della 3 finché non si decide. `placements[].island`: l'isola della copia (omesso se vuoto = casa).
- **Oggetti universali e di un animale** (nel catalogo, non nel file): i 24 fiori e arredi stanno su qualunque isola; i 12 «per i compagni» sono 3 per animale e si mettono solo
  sulla sua isola (annaffiatoio, vaso grande e aiuola rialzata: `pianty`; cesto di carote, tunnel con fieno e casa porcellino: `porcellino`; altalena uccelli, bagnetto e casa per
  uccelli: `ciccio`; cesto con cuscino, tiragraffi e casa del gatto: `gattino`). I regali, per ora, restano sull'isola di casa.
- `placements`: le copie sulle isole (al massimo **150** per isola). `col`, `row`: la tessera dove sta l'angolo in fondo dell'oggetto; `turned`: se è girato (larghezza e
  profondità si scambiano). Un oggetto occupa `cols × rows` tessere del catalogo (`footprint`: 1×1 quasi sempre; 2×1 panchina, bandierine, cancelletto,
  ponticello, aiuola, arco di rose; 2×2 casette del gatto e del porcellino, altalena, amaca, tappeto da picnic). Di un oggetto se ne possono mettere
  **al massimo quante copie si sono trovate**. In lettura, una copia fuori dall'isola, sul sentiero o sopra un'altra si toglie (torna tra quelle da mettere);
  una di un oggetto sconosciuto si tiene.
- `corners` (facoltativo; assente se non se n'è sbloccato nessuno): gli **angoli** sbloccati, nell'ordine in cui si sono trovati (`te`, `lettura`, `orto`, `gatto`, `porcellino`,
  `uccelli`, `prato-fiorito`, `bosco`, `festa`, `rose`). Non cambia la versione: un'app che non lo conosce lo ignora (e, riscrivendo il file, lo perde: gli angoli
  si risbloccano). Quali cose formano un angolo e quanto devono stare vicine sta in `GardenCorners.swift`, e va ripetuto uguale su Windows.
- `guests` (facoltativo): gli **ospiti** salutati, per specie (`pettirosso`, `cinciallegra`, `coniglio`, `riccio`, `rana`, `anatroccolo`, `lucertola`, `tartaruga`, `topolino`,
  `scoiattolo`, `civetta`, `volpe`): `first` il giorno della prima visita (`AAAA-MM-GG`), `visits` quante volte l'hai salutato, `reason` cosa l'aveva attirato (il nome di una
  cosa o di un angolo). La prima volta lascia un regalo, che è già dentro `drops` e `placements`: il regalo è deterministico (come per i punti, un tiro con
  l'identificativo fisso `OSPITE-<specie>` in maiuscolo, che non può dare «niente»). Non cambia la versione; chi non lo conosce lo ignora (e, riscrivendo il file, lo perde).
- `companions`: la tessera di «casa» dei compagni (gli altri stanno sul sentiero, a posti fissi); camminando si spostano di una tessera alla volta, ma non si
  salva.
- **La dotazione** (le quattro cose a prezzo 0) parte su tessere fisse: margherite (5, 3), trifoglio (2, 5), erba alta (1, 1), mughetti (6, 6).
- **Il tiro è deterministico**: FNV-1a a 32 bit sull'identificativo della sessione in **maiuscolo** (byte UTF-8) come seme di un Mulberry32; i quattro numeri
  (niente, rarità, nuovo, scelta) si estraggono in quest'ordine. Mac e Windows devono dare gli stessi regali sugli stessi dati
  (il blocco `giardino` dei file in `tests/fixtures/attesi/`). Anche **dove cade** la copia trovata è deterministico (FNV-1a di «posto-» più
  l'identificativo, sulle tessere libere in ordine di riga e colonna).
- **Versioni vecchie**: si leggono ancora. La **2** aveva il prato libero: `placements` con `x`, `y` (frazioni della scena) e `companions` con `x`, `y`; ogni
  cosa va sulla tessera libera più vicina (`GardenLayout.tile(fromLegacy:size:)`, poi `nearestOrigin`), nell'ordine del file, e quello che non ci sta torna
  tra le copie da mettere. La **1** (`unlocked`, `spent`): gli oggetti sbloccati diventano trovati (con tante copie quante ne erano nel prato, almeno una),
  `spent` va in `legacySpent`, e al primo avvio i punti guadagnati meno quelli spesi diventano `pendingGifts`. L'ultimo file di una versione vecchia si
  copia in `giardino-formato1.json` o `giardino-formato2.json` prima di riscriverlo.
- **Obbligatori**: `version`, `placements` e `companions` (se ne manca uno il file è rovinato: si sposta in `giardino.corrotto-<epoch>.json` e si riparte
  da vuoto). Il resto è facoltativo; senza `drops` si tratta come il formato 1.
- `version` maggiore di 4: si legge e si lavora in sola lettura (con un avviso). Illeggibile: sola lettura.
- «Cancella tutto» toglie il file.

## 6. `impostazioni.json` (solo Windows)

Sul Mac le preferenze stanno in `UserDefaults`. Su Windows stanno in un oggetto JSON piatto con **gli stessi nomi di chiave**:

| Chiave | Tipo | Valori | Predefinito |
|---|---|---|---|
| `pet` | testo | un id di compagno | `pianty` (anche per un id sconosciuto) |
| `phraseFrequency` | testo | `often`, `sometimes`, `rarely`, `never` | `sometimes` |
| `movement` | vero/falso | cammina per lo schermo | `true` |
| `askHowItWent` | vero/falso | mostra «Com'è andata?» | `true` |
| `longBreakEnabled` | vero/falso | pausa lunga dopo 4 focus | `true` |
| `ambientSound` | testo | `none`, `rain`, `brown`, `wind` | `none` |
| `ambientVolume` | numero | da 0 a 1 (se non è finito: 0,25) | `0.25` |
| `musicSource` | testo | `off`, `bundled`, `folder` | `off` |
| `musicFolder` | testo | percorso della cartella (**dipende dal sistema**) | assente |
| `musicVolume` | numero | da 0 a 1 | `0.30` |
| `customTimers.focus` | elenco di interi | minuti, da 1 a 180, fino a 6, in ordine crescente | vuoto |
| `customTimers.rest` | elenco di interi | minuti, da 1 a 60, fino a 6, in ordine crescente | vuoto |
| `developerMode` | vero/falso | tutto sbloccato | `false` |
| `lastWeeklyRecap` | testo | il lunedì («AAAA-MM-GG») della settimana di cui il compagno ha già detto il riepilogo | assente |

- Un valore mancante, di un tipo sbagliato o fuori elenco vale il **predefinito**; non è mai un errore. I timer fuori misura o ripetuti si ignorano.
- I timer di serie non si salvano: **focus 30 e 50**, **pausa 5 e 10**.
- `musicFolder` non si porta da un sistema all'altro.
- `migratedFromBonsy` esiste solo sul Mac e non serve su Windows.
- Se il file non è un oggetto JSON (rovinato, vuoto) si parte dai predefiniti e il primo salvataggio lo sostituisce: sono solo
  preferenze. Le chiavi che l'app non conosce restano nel file.
- `ambientVolume` e `musicVolume` fuori dal range 0–1 si riportano dentro (7 → 1, −1 → 0); un numero non finito vale 0,25.

## 7. Le frasi

- I file **inclusi** nell'app sono `assets/frasi_<personaggio>.txt` (uno per compagno).
- Il file **dell'utente** `frasi_<personaggio>.txt`, nella cartella dei dati, ha la **precedenza**. Su Mac c'è anche la
  cartella `Bonsy` dei tempi in cui l'app aveva un altro nome (non serve su Windows).
- **Formato:** una frase per riga, UTF-8; le righe che iniziano con `#` e quelle vuote si ignorano; gli spazi ai bordi si tolgono.
- Se non c'è nessuna frase, ogni compagno ha una **frase di riserva** (`fallbackQuote` in `Pet.swift`).
- Il file si **rilegge a ogni frase**, così le modifiche valgono subito.
- Le frasi si pescano da un **mazzo mischiato**: non si ripete una frase finché non sono finite, e la prima del mazzo nuovo non è mai l'ultima detta.

## 8. Le prove di confronto

`tests/fixtures/` raccoglie cartelle di dati di esempio (ognuna è una cartella dei dati) e, in `tests/fixtures/attesi/`,
**quello che la versione per Mac ne ricava** con un «adesso» fisso (14 ottobre 2026, ore 20:00, fuso `Europe/Rome`): quante
sessioni, quali file nascono (copie, file messi da parte), quali avvisi, la serie, i punti. Ogni nuova versione dell'app
deve dare gli stessi risultati. Per rifarli: `tests/genera-attesi.sh`. Dalla 0.10.0 / 1.2.0 comprendono anche le **frasi di contesto** (`contesto`: saluti, risveglio, riepilogo e numeri in sei momenti fissi, e i traguardi man mano che il registro cresce) e `attesi/_contesto-anniversari.json` (gli anniversari su date inventate). La scheda «Anno» delle statistiche (0.10.0 / 1.2.0) aggiunge `anno` (mappa, tre numeri, andamento e testi), `attesi/_anno-griglie.json` (la griglia di 41 anni) e `attesi/_anno-sintetico.json` (un anno e mezzo di studio inventato).

La stessa prova vale **nel verso opposto**: `windows/test/ritorno.test.ts` fa scrivere al codice per Windows alcune cartelle di dati (una migrazione da una
versione vecchia, sessioni con accenti, emoji, virgolette e formule da foglio di calcolo, voti e note, un focus in corso con pausa, un profilo con il
nome da accorciare) e le fa leggere al codice Swift del Mac con lo stesso generatore (`tests/genera-attesi.sh`): i risultati devono essere uguali. Sul Mac
gira con `npm test` dentro `windows/` (serve `swiftc`; dove manca si salta) e a ogni modifica sulla CI del Mac. Per i suoni, `tests/fixtures/rumore.json` ha
le misure della sintesi dei rumori fatta dall'app per Mac (`tests/genera-rumore.sh`).

## 9. `dafare.json` (le cose da fare)

Lo scrivono e lo leggono **tutte e due le app** (la pagina «Da fare» della scheda: Mac dalla 0.9, Windows dalla 1.1). Che l'una legga i file
dell'altra è provato nei due versi: `tests/fixtures/dafare*` con i loro attesi, e `windows/test/ritorno.test.ts`.

```json
{
  "items" : [
    {
      "createdAt" : "2026-10-20T07:00:00Z",
      "due" : "2026-10-21",
      "id" : "8F1C2D3E-4B5A-4C6D-8E7F-901A2B3C4D5E",
      "subject" : "Analisi",
      "text" : "Esercizi di analisi 4–6"
    },
    {
      "createdAt" : "2026-10-19T16:30:00Z",
      "doneAt" : "2026-10-20T08:12:00Z",
      "id" : "1A2B3C4D-5E6F-4A7B-8C9D-0E1F2A3B4C5D",
      "text" : "Mandare la mail al prof"
    }
  ],
  "version" : 1
}
```

| Campo | Obbligatorio | Note |
|---|---|---|
| `version` | **sì** | 1 |
| `items` | **sì** | Le voci, al massimo **200** (da fare e fatte da poco). |
| `id` | **sì** | UUID. |
| `text` | **sì** | Pulito come le note del focus: parole separate da qualunque spazio o a capo unite con uno spazio solo, caratteri di controllo tolti, al massimo **120** caratteri. Vuoto = la voce si scarta. |
| `createdAt` | **sì** | Quando è stata scritta (ISO 8601, UTC). |
| `due` | no | La scadenza: un **giorno** `AAAA-MM-GG`, senza ora e senza fuso (il 23 è il 23 sull'orologio del computer, in qualunque fuso). Una data che non esiste (il 31 giugno) si toglie e la voce resta senza scadenza. |
| `subject` | no | Come le materie di `sessioni.json` (§2.3: al massimo 40 caratteri, vuota = nessuna). |
| `doneAt` | no | Quando è stata segnata come fatta (ISO 8601, UTC). Assente = ancora da fare. |

- **Le voci fatte** restano **7 giorni** (da `doneAt`) e poi si tolgono, all'apertura o alla prima modifica.
- **Si scrive** come gli altri file: tutto il file a ogni modifica, atomicamente, chiavi in ordine alfabetico, indentazione di 2 spazi.
- **Rovinato**: si sposta in `dafare.corrotto-<epoch>.json`, si avvisa e si riparte da vuoto (se non si riesce a spostarlo: sola lettura).
  **Illeggibile**, o di una **versione più nuova** di 1: si legge (se si può) e non si riscrive, con un avviso.
- **«Cancella tutto»** (statistiche) **non** tocca questo file: le cose da fare non sono dati di studio.
- **Come si mostrano** (`ToDoList.sections`): *Scadute* (`due` prima di oggi), *Oggi*, *Prossime*, *Senza data*; dentro ogni gruppo
  per `due` e poi per `createdAt`, dal più vecchio. Accanto a ogni voce: «ieri», «oggi», «domani», il giorno della settimana e il numero
  entro sei giorni («ven 23»), altrimenti giorno e mese («26 ott», con l'anno se non è quello di oggi).
- **Il compagno** (`ToDoReminder`) ricorda solo le scadenze di **oggi** (o, se non ce ne sono, di **domani**), mai le scadute; al posto di una
  frase a caso, al massimo una volta ogni tre ore, mai durante un focus e mai con le frasi spente.

