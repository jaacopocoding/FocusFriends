# Bonsy

Un bonsai che se ne sta sul desktop del Mac, ti accompagna nel Pomofocus e ogni tanto dice una
frase gentile. Cresce mentre lavori: parte da un seme e, man mano che il tempo del focus passa,
diventa un albero. Non fa altro: è solo una cosa carina sullo schermo.

Dal menu si possono scegliere altri personaggi: **Pianty** (una succulenta che cresce allo stesso modo,
con le stesse frasi), il **Porcellino** (cammina per lo schermo, con frasi sue),
**Spidy** (un mini Spider-Man, fisso) e **Simulazione** (una prova: Spidy che cammina per lo schermo).

## Cosa fa

- Compare nell'angolo in basso a destra, sempre sopra le altre finestre e su tutti gli Spaces.
- Ogni 40–110 secondi mostra un fumetto con una frase (la prima dopo 5 secondi dall'avvio).
- Si può trascinare dove si vuole; fumetto e orologio lo seguono.
- Non ha icona nel Dock: si controlla dalla barra dei menu o con il tasto destro sul personaggio.

## Menu

| Voce | Cosa fa |
|---|---|
| Nascondi / Mostra | Lo toglie dallo schermo o lo rimette |
| Fai parlare | Mostra subito una frase |
| Pomofocus ▸ | Timer: *Focus 30/50 min*, *Pausa 5/10 min*, *Ferma timer* |
| Personaggio ▸ | Sceglie il personaggio (la scelta resta alla riapertura) |
| Movimento ▸ | *In movimento* / *Fermo*: per i personaggi che camminano |
| Avvia al login | Si avvia da solo all'accensione del Mac |
| Modifica le frasi… | Apre il file delle frasi del personaggio attivo |
| Esci da Bonsy | Chiude l'app |

## Pomofocus

Dal menu *Pomofocus* scegli un focus di 30 o 50 minuti: sotto il personaggio compare un mini orologio
digitale con il conto alla rovescia. L'orologio resta visibile per i primi 2 minuti di ogni fase, poi si
ritira; ricompare con un'animazione a tendina quando passi il mouse sul personaggio, e resta sempre
visibile quando mancano 5 minuti o meno. Alla fine del focus suona un avviso e parte da sola la pausa
(5 minuti, oppure l'ultima durata scelta tra *Pausa 5 min* e *Pausa 10 min*, segnata con la spunta).
Alla fine della pausa l'orologio sparisce. Durante il focus il personaggio parla più di rado, per non
distrarti.

## La crescita di Bonsy e Pianty

Bonsy e Pianty hanno cinque stadi ciascuno, dal seme alla pianta adulta. Durante un focus parte dal primo stadio e passa al
successivo ogni quinto del tempo (con un focus da 50 minuti: ai minuti 0, 10, 20, 30 e 40). Durante la
pausa e quando non c'è nessun timer resta allo stadio finale.

## Personaggi che camminano

Il Porcellino e Simulazione camminano per lo schermo: fanno qualche passo in una direzione
(3–8 secondi, 42 punti al secondo), si fermano 4–10 secondi, poi ripartono, rimbalzando ai bordi.
Stanno fermi mentre parlano o mentre li trascini col mouse. Camminano solo in orizzontale, all'altezza
a cui si trovano. Dal menu *Movimento ▸ Fermo* smettono di camminare e restano dove sono; *In movimento*
li rimette in cammino. Se le immagini guardano a destra (come il porcellino), vengono specchiate quando
vanno a sinistra.

Il Porcellino ha un ciclo di passi a 4 fotogrammi, una posa con le orecchie che saltellano mentre
parla, e le sue frasi in `assets/frasi_porcellino.txt`. Ogni tanto, in momenti casuali mentre gira per lo
schermo, si ferma a mangiare una carota per una decina di secondi (non due volte di fila). Quando ci
saranno le immagini, dormirà durante il focus e farà il "popcorning" quando ne finisce uno. Quando lo trascini col mouse compare un disegno in cui
viene sollevato da due mani, spaventato (con un leggero tremolio); lasciandolo, torna in piedi dove si trova. Simulazione usa le frasi di Spidy.

## Installazione

Serve macOS 13 o successivo e gli strumenti da riga di comando di Xcode (`xcode-select --install`).

```bash
./build.sh                         # crea build/Bonsy.app
cp -R build/Bonsy.app /Applications/
open /Applications/Bonsy.app
```

Per l'avvio al login è meglio che l'app stia in **Applicazioni**. macOS potrebbe chiedere
l'approvazione in Impostazioni di Sistema → Generali → Elementi login.

## Frasi

Le frasi di partenza sono in `assets/frasi_bonsy.txt` (Bonsy e Pianty, condivise) e `assets/frasi.txt` (Spidy), una per riga
(le righe che iniziano con `#` sono ignorate). Per usare le tue senza ricompilare, scegli *Modifica le
frasi…* dal menu: crea e apre `~/Library/Application Support/Bonsy/frasi_bonsy.txt` (o `frasi.txt` per
Spidy), che ha la precedenza sul file incluso nell'app. Le modifiche valgono dalla frase successiva.
Se esiste ancora la vecchia cartella `Application Support/Spidy`, viene letta come seconda scelta.

## Struttura

```
Sources/Bonsy/
  main.swift            avvio dell'app
  AppDelegate.swift     crea finestra, fumetti, timer e menu
  Pet.swift             i personaggi: immagini, frasi, misure, come camminano
  PetWindow.swift       finestra trasparente con il personaggio e i suoi stadi
  Speaker.swift         tempi e comparsa dei fumetti
  Walker.swift          camminata dei personaggi che camminano
  SpeechBubble.swift    fumetto: immagine scalata sul testo
  Quotes.swift          caricamento delle frasi
  Pomodoro.swift        logica del timer focus/pausa e crescita
  TimerBubble.swift     orologio digitale sotto il personaggio
  MenuController.swift  icona nella barra, menu, avvio al login
assets/
  bonsy/original.png    immagine di partenza di Bonsy (5 stadi)
  bonsy/stage1..5.png   stadi ritagliati (generati da tools/cutout_bonsy.py)
  pianty/original.png   immagine di partenza di Pianty (5 stadi)
  pianty/stage1..5.png  stadi ritagliati (generati da tools/cutout_pianty.py)
  original.png, spidy.png   immagine di Spidy e ritaglio (tools/cutout.py)
  bubble_original.png, bubble.png   fumetto e ritaglio (tools/cutout_bubble.py)
  frasi_bonsy.txt, frasi.txt, frasi_porcellino.txt   frasi incluse nell'app
  simulazione/frame1..3.png   le tre pose di Simulazione (generate da tools/make_simulazione.sh)
  porcellino/original.png     immagine di partenza del porcellino (5 fotogrammi)
  porcellino/eat_original.png il foglio della carota (stesso formato; anche sleep_original.png e jump_original.png)
  porcellino/frame*.png       fotogrammi ritagliati e allineati (1-5 cammino, 6-10 mangia), da tools/cutout_porcellino.py
  porcellino/picked_original.png, picked.png   il porcellino sollevato (tools/cutout_picked.py)
  AppIcon.icns          icona dell'app (generata da tools/make_icon.py)
tools/                  script per ritagli, icona e pose di Simulazione (Python con Pillow e numpy; make_simulazione.sh usa Swift)
build.sh                compila e crea build/Bonsy.app
```

## Aggiungere o cambiare un personaggio

Un personaggio è una riga in `Pet.swift` (con `pickedResource` può avere un disegno diverso mentre lo si trascina): immagini (una per stadio, tutte sullo stesso formato e
allineate sulla linea di terra), file delle frasi, dimensione della finestra. Un solo stadio = personaggio
fisso, più stadi = cresce con il timer; con `walks: true` le immagini sono pose e il personaggio
cammina. Per ritagliare un'immagine su sfondo bianco si può partire da
`tools/cutout.py`.
