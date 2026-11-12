#!/bin/bash
# Disegna fuori schermo la scheda del menu vera dell'app (MenuCardView) in build/readme/scheda.png (a riposo) e scheda-focus.png (durante un focus), con dati inventati.
# Serve l'app compilata (./build.sh): ne prende i disegni. Per le immagini del README (tools/compone-readme.sh).
set -euo pipefail
cd "$(dirname "$0")/../.."
[ -d build/FocusFriends.app ] || { echo "Prima compila l'app: ./build.sh" >&2; exit 1; }
B=build/scheda
rm -rf "$B"
mkdir -p "$B/src" "$B/B.app/Contents/MacOS" "$B/B.app/Contents/Resources" build/readme
for f in Sources/FocusFriends/*.swift; do
    name=$(basename "$f")
    [ "$name" = "main.swift" ] && continue
    [ "$name" = "MenuCard.swift" ] && continue
    [ "$name" = "GuidedTour.swift" ] && continue
    cp "$f" "$B/src/$name"
done
# MenuCardView e il fumetto del giro sono privati al loro file: li rendo visibili solo in questa copia
sed -e 's/^private final class/final class/' Sources/FocusFriends/MenuCard.swift > "$B/src/MenuCard.swift"
sed -e 's/^private final class TourTipView/final class TourTipView/' Sources/FocusFriends/GuidedTour.swift > "$B/src/GuidedTour.swift"
cp tools/banchi/render-scheda/main.swift "$B/src/zz_render.swift"
cp build/FocusFriends.app/Contents/Resources/* "$B/B.app/Contents/Resources/" 2>/dev/null || true
cp build/FocusFriends.app/Contents/Info.plist "$B/B.app/Contents/"
swiftc -O -parse-as-library -o "$B/B.app/Contents/MacOS/FocusFriends" "$B"/src/*.swift
"$B/B.app/Contents/MacOS/FocusFriends" build/readme/scheda.png riposo gattino
"$B/B.app/Contents/MacOS/FocusFriends" build/readme/scheda-focus.png focus gattino
# il giro guidato al passo del giardino: la scheda con il velo (scheda-giro.png), il fumetto (giro-fumetto.png) e dove sta il giardino (giro.txt)
"$B/B.app/Contents/MacOS/FocusFriends" build/readme/scheda-giro.png giro gattino
