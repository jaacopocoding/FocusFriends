#!/bin/bash
# Compila Bonsy e crea build/Bonsy.app
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Bonsy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Una versione per ogni tipo di Mac, poi unite in un solo eseguibile (così l'app gira anche su Mac Intel).
mkdir -p build/tmp
for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos13.0" -o "build/tmp/Bonsy-$arch" Sources/Bonsy/*.swift
done
lipo -create build/tmp/Bonsy-arm64 build/tmp/Bonsy-x86_64 -output "$APP/Contents/MacOS/Bonsy"
rm -rf build/tmp
cp assets/spidy.png assets/bubble.png assets/frasi.txt assets/frasi_bonsy.txt assets/frasi_porcellino.txt assets/AppIcon.icns "$APP/Contents/Resources/"
for i in 1 2 3; do cp "assets/simulazione/frame$i.png" "$APP/Contents/Resources/simulazione_frame$i.png"; done
for f in assets/porcellino/frame*.png; do cp "$f" "$APP/Contents/Resources/porcellino_$(basename "$f")"; done
cp assets/porcellino/picked.png "$APP/Contents/Resources/porcellino_picked.png"
cp assets/pianty/picked.png "$APP/Contents/Resources/pianty_picked.png"
for i in 1 2 3 4 5; do
    cp "assets/bonsy/stage$i.png" "$APP/Contents/Resources/bonsy_stage$i.png"
    for f in 1 2 3 4 5 6 7; do
        cp "assets/pianty/stage${i}_$f.png" "$APP/Contents/Resources/pianty_stage${i}_$f.png"
    done
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Bonsy</string>
    <key>CFBundleDisplayName</key><string>Bonsy</string>
    <key>CFBundleIdentifier</key><string>com.jacopo.bonsy</string>
    <key>CFBundleExecutable</key><string>Bonsy</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Creato $APP"
