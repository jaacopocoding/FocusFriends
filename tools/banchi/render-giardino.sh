#!/bin/bash
# Disegna fuori schermo il giardino vero dell'app per Mac (GardenView) da una cartella di dati, per confrontarlo con quello di Windows.
# Serve l'app compilata (./build.sh): ne prende i disegni.
#   tools/banchi/render-giardino.sh <cartella dei dati> <cartella dove scrivere>
# Scrive le stesse schermate di windows/test/vivo/giardino.cjs (casa, mondo, sera, inverno), con il nome «mac-…».
set -euo pipefail
cd "$(dirname "$0")/../.."
[ -d build/FocusFriends.app ] || { echo "Prima compila l'app: ./build.sh" >&2; exit 1; }
DATA=$1; OUT=$2
B=build/render-giardino
rm -rf "$B"
mkdir -p "$B/src" "$B/B.app/Contents/MacOS" "$B/B.app/Contents/Resources" "$OUT"
for f in Sources/FocusFriends/*.swift; do
    [ "$(basename "$f")" = "main.swift" ] && continue
    cp "$f" "$B/src/"
done
cp tools/banchi/render-giardino/main.swift "$B/src/zz_render.swift"
cp build/FocusFriends.app/Contents/Resources/* "$B/B.app/Contents/Resources/" 2>/dev/null || true
# un identificativo diverso da quello dell'app: le preferenze del banco non toccano quelle vere
sed -e 's/com\.jacopo\.focusfriends/com.jacopo.focusfriends.banco-giardino/' build/FocusFriends.app/Contents/Info.plist > "$B/B.app/Contents/Info.plist"
swiftc -O -parse-as-library -o "$B/B.app/Contents/MacOS/FocusFriends" "$B"/src/*.swift
R="$B/B.app/Contents/MacOS/FocusFriends"
"$R" "$DATA" "$OUT/mac-casa.png" 14 autumn casa
"$R" "$DATA" "$OUT/mac-mondo.png" 14 autumn mondo
"$R" "$DATA" "$OUT/mac-sera.png" 20.5 autumn casa
"$R" "$DATA" "$OUT/mac-inverno.png" 12 winter casa
