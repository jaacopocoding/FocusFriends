#!/bin/bash
# Disegna fuori schermo la finestra delle statistiche vera dell'app per Mac (DashboardView), con un anno di sessioni inventate, per le immagini della
# guida e del README: build/readme/statistiche-*.png. I dati stanno in una cartella temporanea e le preferenze hanno un identificativo a parte:
# quelli veri non si toccano. La finestra è alta quanto serve per mostrare la pagina intera, senza scorrere; poi la cornice e docs/images/.
# Serve l'app compilata (./build.sh): ne prende i disegni.
set -euo pipefail
cd "$(dirname "$0")/../.."
[ -d build/FocusFriends.app ] || { echo "Prima compila l'app: ./build.sh" >&2; exit 1; }
B=build/render-statistiche
rm -rf "$B"
mkdir -p "$B/src" "$B/dati" "$B/B.app/Contents/MacOS" "$B/B.app/Contents/Resources" build/readme
for f in Sources/FocusFriends/*.swift; do
    name=$(basename "$f")
    [ "$name" = "main.swift" ] && continue
    [ "$name" = "DashboardWindow.swift" ] && continue
    cp "$f" "$B/src/"
done
# Solo in questa copia: l'altezza della finestra viene da ALTA, e due modi per scegliere una materia e mettere il mouse su un punto della pagina.
sed -e 's/static let size = NSSize(width: 560, height: 660)/static let size = NSSize(width: 560, height: CGFloat(Double(ProcessInfo.processInfo.environment["ALTA"] ?? "660")!))/' \
    Sources/FocusFriends/DashboardWindow.swift > "$B/src/DashboardWindow.swift"
grep -q 'environment\["ALTA"\]' "$B/src/DashboardWindow.swift" || { echo "Errore: l'altezza della finestra non si è potuta cambiare." >&2; exit 1; }
cat >> "$B/src/DashboardWindow.swift" <<'SWIFT'

extension DashboardView {
    func chooseSubject(_ name: String) {
        let chips = kind == .year ? layout.year?.chips ?? [] : layout.chartChips
        if let chip = chips.first(where: { $0.subject == name }) { pageClicked(at: NSPoint(x: chip.rect.midX, y: chip.rect.midY)) }
    }
    func pageHovered(at point: NSPoint) { pageHovered(at: Optional(point)) }
}
SWIFT
cp tools/banchi/render-statistiche/main.swift "$B/src/zz_render.swift"
cp build/FocusFriends.app/Contents/Resources/* "$B/B.app/Contents/Resources/" 2>/dev/null || true
sed -e 's/com\.jacopo\.focusfriends/com.jacopo.focusfriends.banco-statistiche/' build/FocusFriends.app/Contents/Info.plist > "$B/B.app/Contents/Info.plist"
swiftc -O -parse-as-library -o "$B/B.app/Contents/MacOS/FocusFriends" "$B"/src/*.swift
R="$B/B.app/Contents/MacOS/FocusFriends"
ALTA=680 "$R" "$B/dati" build/readme/statistiche-oggi.png oggi
ALTA=740 "$R" "$B/dati" build/readme/statistiche-settimana.png settimana
ALTA=760 "$R" "$B/dati" build/readme/statistiche-mese.png mese
ALTA=790 "$R" "$B/dati" build/readme/statistiche-anno.png anno
# la cornice (angoli tondi, ombra) e la copia in docs/images/
python3 tools/compone_readme.py statistiche
