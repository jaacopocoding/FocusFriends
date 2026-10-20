#!/bin/bash
# Memoria e processore a riposo, con opzioni di Chromium alternative (le prove del PIANO_WINDOWS.md, M9).
# uso:  test/vivo/misure.sh <nome> [FF_SWITCHES: elenco JSON di opzioni] [FF_NO_GPU: 1]
# Come esegui.sh: dati in una cartella nuova, mai quelli veri.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
[ $# -ge 1 ] || { echo "uso: $0 <nome> [opzioni JSON] [1 per spegnere la GPU]"; exit 2; }
OUT="$(mktemp -d "${TMPDIR:-/tmp}/ff-misure-$1.XXXXXX")"
mkdir "$OUT/data"
printf '%s\n' '{"phraseFrequency":"never","pet":"pianty"}' > "$OUT/data/impostazioni.json"
printf '%s\n' '{"version":1,"introSeen":true}' > "$OUT/data/profilo.json"
(cd "$ROOT" && node tools/build.mjs) > "$OUT/build.txt" 2>&1 || { cat "$OUT/build.txt"; exit 1; }
FF_SWITCHES="${2:-[]}" FF_NO_GPU="${3:-0}" FF_DATA_DIR="$OUT/data" FF_SELFTEST="14,24" FF_SELFTEST_OUT="$OUT" \
  "$ROOT/node_modules/.bin/electron" "$ROOT" > "$OUT/log.txt" 2>&1
python3 - "$OUT" "$1" <<'PY'
import json, sys
d, name = sys.argv[1], sys.argv[2]
for f in ('misure-1.json', 'misure-2.json'):
    m = json.load(open(f"{d}/{f}"))['metrics']
    print(name, f, "MB:", sum(x['workingSetMB'] for x in m), "CPU%:", round(sum(x['cpu'] for x in m), 2),
          [(x['type'], x['workingSetMB'], round(x['cpu'], 1)) for x in m])
PY
echo "risultati in: $OUT"
