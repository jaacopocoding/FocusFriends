#!/bin/bash
# Compila FocusFriends e crea build/FocusFriends.app
set -euo pipefail
cd "$(dirname "$0")"

APP="build/FocusFriends.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Una versione per ogni tipo di Mac, poi unite in un solo eseguibile (così l'app gira anche su Mac Intel).
mkdir -p build/tmp
for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos13.0" -o "build/tmp/FocusFriends-$arch" Sources/FocusFriends/*.swift
done
lipo -create build/tmp/FocusFriends-arm64 build/tmp/FocusFriends-x86_64 -output "$APP/Contents/MacOS/FocusFriends"
rm -rf build/tmp
cp assets/bubble.png assets/frasi_pianty.txt assets/frasi_porcellino.txt assets/frasi_ciccio.txt assets/frasi_gattino.txt assets/AppIcon.icns "$APP/Contents/Resources/"
for f in assets/porcellino/frame*.png; do cp "$f" "$APP/Contents/Resources/porcellino_$(basename "$f")"; done
cp assets/porcellino/picked.png "$APP/Contents/Resources/porcellino_picked.png"
for f in assets/ciccio/frame*.png; do cp "$f" "$APP/Contents/Resources/ciccio_$(basename "$f")"; done
cp assets/ciccio/picked.png "$APP/Contents/Resources/ciccio_picked.png"
for f in assets/gattino/frame*.png; do cp "$f" "$APP/Contents/Resources/gattino_$(basename "$f")"; done
cp assets/gattino/picked.png "$APP/Contents/Resources/gattino_picked.png"
cp assets/pianty/picked.png "$APP/Contents/Resources/pianty_picked.png"
# I brani inclusi (assets/music, con le licenze in CREDITS.md): nelle risorse con il prefisso music_.
for f in assets/music/*.m4a assets/music/*.mp3; do
    [ -f "$f" ] && cp "$f" "$APP/Contents/Resources/music_$(basename "$f")"
done
# Le immagini che crescono con il focus (la collezione di Ciccio, la carota del porcellino).
for f in assets/garden/garden_*.png assets/garden/growth_*.png; do
    [ -f "$f" ] && cp "$f" "$APP/Contents/Resources/$(basename "$f")"
done
# Il giardino: il prato e gli oggetti del negozio (i fogli *_original.png non servono nell'app).
for f in assets/giardino/*.png; do
    case "$f" in *_original.png) continue ;; esac
    cp "$f" "$APP/Contents/Resources/giardino_$(basename "$f")"
done
# L'album delle figurine: la copertina del libro (i fogli *_original.png non servono nell'app).
for f in assets/album/*.png; do
    case "$f" in *_original.png) continue ;; esac
    cp "$f" "$APP/Contents/Resources/album_$(basename "$f")"
done
for i in 1 2 3 4 5; do
    for f in 1 2 3 4 5 6 7; do
        cp "assets/pianty/stage${i}_$f.png" "$APP/Contents/Resources/pianty_stage${i}_$f.png"
    done
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>FocusFriends</string>
    <key>CFBundleDisplayName</key><string>FocusFriends</string>
    <key>CFBundleIdentifier</key><string>com.jacopo.focusfriends</string>
    <key>CFBundleExecutable</key><string>FocusFriends</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.10.0</string>
    <key>CFBundleVersion</key><string>13</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || { echo "Errore: la firma ad-hoc dell'app non è riuscita." >&2; exit 1; }
echo "Creato $APP"
