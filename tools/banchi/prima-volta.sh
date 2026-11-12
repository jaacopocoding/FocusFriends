#!/bin/bash
# La prima apertura, come per chi scarica l'app: l'app vera con una cartella di dati vuota (temporanea), le preferenze con un identificativo a parte
# (com.jacopo.focusfriends.banco-primavolta, cancellate prima) e un minuto che dura un secondo. Un pilota automatico (prima-volta/autopilota.swift)
# fa i passi e fotografa le finestre in <cartella delle foto>. I dati veri non si toccano. Le finestre compaiono davvero sullo schermo per un paio di minuti.
#   tools/banchi/prima-volta.sh <cartella delle foto>
set -euo pipefail
cd "$(dirname "$0")/../.."
[ -d build/FocusFriends.app ] || { echo "Prima compila l'app: ./build.sh" >&2; exit 1; }
FOTO=$1
B=build/prima-volta
rm -rf "$B"
mkdir -p "$B/src" "$B/dati" "$B/B.app/Contents/MacOS" "$B/B.app/Contents/Resources" "$FOTO"
cp Sources/FocusFriends/*.swift "$B/src/"
# solo in questa copia: la cartella dei dati, un minuto di un secondo (ma la sessione salvata conta i minuti veri), e il pilota automatico all'avvio
sed -i '' -e 's|FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FocusFriends")|URL(fileURLWithPath: ProcessInfo.processInfo.environment["FF_DATI"]!)|' "$B/src/SessionLog.swift"
sed -i '' -e 's|private static let secondsPerMinute: TimeInterval = 60|private static let secondsPerMinute: TimeInterval = 1|' \
          -e 's|let session = log.add(start: phaseStart, seconds: elapsed,|let session = log.add(start: phaseStart, seconds: elapsed * 60,|' "$B/src/Pomodoro.swift"
sed -i '' -e 's|        // La prima volta (anche per chi la usava già): come ti chiami e chi ti fa compagnia.|        Autopilota.start()\n        // La prima volta (anche per chi la usava già): come ti chiami e chi ti fa compagnia.|' "$B/src/AppDelegate.swift"
grep -q 'FF_DATI' "$B/src/SessionLog.swift" && grep -q 'TimeInterval = 1$' "$B/src/Pomodoro.swift" && grep -q 'elapsed \* 60' "$B/src/Pomodoro.swift" \
    && grep -q 'Autopilota.start()' "$B/src/AppDelegate.swift" || { echo "Errore: la copia di prova non si è potuta preparare." >&2; exit 1; }
cp tools/banchi/prima-volta/autopilota.swift "$B/src/zz_autopilota.swift"
cp build/FocusFriends.app/Contents/Resources/* "$B/B.app/Contents/Resources/" 2>/dev/null || true
sed -e 's/com\.jacopo\.focusfriends/com.jacopo.focusfriends.banco-primavolta/' build/FocusFriends.app/Contents/Info.plist > "$B/B.app/Contents/Info.plist"
swiftc -O -o "$B/B.app/Contents/MacOS/FocusFriends" "$B"/src/*.swift 2>&1 | grep -E "error" || true
defaults delete com.jacopo.focusfriends.banco-primavolta >/dev/null 2>&1 || true
FF_DATI="$PWD/$B/dati" FF_FOTO="$FOTO" "$B/B.app/Contents/MacOS/FocusFriends"
echo "dati scritti:"; ls "$B/dati"
