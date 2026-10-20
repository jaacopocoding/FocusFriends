#!/bin/bash
# Una prova dal vivo: compila, apre l'app vera di Electron con una cartella di dati NUOVA, esegue un copione e raccoglie
# schermate e misure. Non tocca mai i dati veri: la cartella dei dati è sempre dentro la cartella dei risultati, e quella
# dei risultati si crea da zero (se esiste già, ci si ferma: niente viene cancellato).
#
# uso:  test/vivo/esegui.sh <copione.cjs> [secondi massimi, default 90]
#
# Variabili (tutte facoltative):
#   FF_OUT            la cartella dei risultati (deve non esistere); di solito se ne crea una nuova in $TMPDIR
#   FF_IMPOSTAZIONI   il contenuto di impostazioni.json (default: {})
#   FF_PROFILO        il contenuto di profilo.json (default: introduzione già vista)
#   FF_INTRO=1        non scrivere profilo.json: compare la scheda di benvenuto
#   FF_APP            l'app da aprire (default: questa cartella; per provare un pacchetto, il suo app.asar)
#   FF_FAKE_DISPLAYS, FF_PROVA_MUSICA, …   quelle che servono al copione (vedi il README)
#
# Pensato per il Mac (e Linux); su Windows con Git Bash o WSL.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

[ $# -ge 1 ] || { echo "uso: $0 <copione.cjs> [secondi massimi]"; exit 2; }
SCRIPT="$1"
[ -f "$SCRIPT" ] || SCRIPT="$HERE/$SCRIPT"
[ -f "$SCRIPT" ] || SCRIPT="$HERE/$1.cjs"
[ -f "$SCRIPT" ] || { echo "copione non trovato: $1"; exit 2; }
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"

if [ -n "${FF_OUT:-}" ]; then
  OUT="$FF_OUT"
  mkdir "$OUT" || { echo "la cartella dei risultati esiste già (o non si può creare): $OUT"; exit 1; }
else
  OUT="$(mktemp -d "${TMPDIR:-/tmp}/ff-vivo.XXXXXX")"
fi
mkdir "$OUT/data"

IMPOSTAZIONI='{}'
[ -z "${FF_IMPOSTAZIONI:-}" ] || IMPOSTAZIONI="$FF_IMPOSTAZIONI"
PROFILO='{"version": 1, "introSeen": true}'
[ -z "${FF_PROFILO:-}" ] || PROFILO="$FF_PROFILO"
printf '%s\n' "$IMPOSTAZIONI" > "$OUT/data/impostazioni.json"
[ -n "${FF_INTRO:-}" ] || printf '%s\n' "$PROFILO" > "$OUT/data/profilo.json"

(cd "$ROOT" && node tools/build.mjs) > "$OUT/build.txt" 2>&1 || { cat "$OUT/build.txt"; exit 1; }

# Il vero comando: FF_SELFTEST accende le variabili di prova; FF_DATA_DIR sceglie la cartella nuova.
FF_DATA_DIR="$OUT/data" FF_SELFTEST=1 FF_SELFTEST_OUT="$OUT" FF_SELFTEST_FILE="$SCRIPT" \
  "$ROOT/node_modules/.bin/electron" "${FF_APP:-$ROOT}" > "$OUT/log.txt" 2>&1 &
PID=$!
# Sul Mac non c'è `timeout`: un sorvegliante chiude l'app se il copione si pianta.
( sleep "${2:-90}"; kill "$PID" 2>/dev/null ) &
WATCH=$!
wait "$PID"
{ kill "$WATCH"; wait "$WATCH"; } 2>/dev/null

grep -v sandbox_extension "$OUT/log.txt"

# Schermate ridotte a un terzo, su uno sfondo colorato (lo sfondo del compagno è trasparente), se c'è Python con Pillow.
python3 - "$OUT" <<'PY' 2>/dev/null
import sys, glob
from PIL import Image
for f in sorted(glob.glob(sys.argv[1] + '/*.png')):
    if f.endswith('-ridotto.png'): continue
    im = Image.open(f).convert('RGBA')
    bg = Image.new('RGBA', im.size, (120, 150, 170, 255)); bg.alpha_composite(im)
    w, h = bg.size
    bg.convert('RGB').resize((w // 3, h // 3)).save(f.replace('.png', '-ridotto.png'))
PY
echo "risultati in: $OUT"
