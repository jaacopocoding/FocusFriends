#!/bin/bash
# Compila Spidy e crea build/Spidy.app
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Spidy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -o "$APP/Contents/MacOS/Spidy" Sources/Spidy/*.swift
cp assets/spidy.png assets/frasi.txt "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Spidy</string>
    <key>CFBundleDisplayName</key><string>Spidy</string>
    <key>CFBundleIdentifier</key><string>com.jacopo.spidy</string>
    <key>CFBundleExecutable</key><string>Spidy</string>
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
