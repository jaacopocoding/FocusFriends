#!/bin/bash
# Genera assets/simulazione/frame1..3.png dal disegno vettoriale in tools/simulazione/
set -euo pipefail
cd "$(dirname "$0")/.."
swiftc -o /tmp/make-simulazione tools/simulazione/SpidyArt.swift tools/simulazione/main.swift
/tmp/make-simulazione
rm -f /tmp/make-simulazione
