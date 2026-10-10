#!/bin/bash
# Compila e genera tools/preview.png con le pose di Spidy
set -euo pipefail
cd "$(dirname "$0")/.."
swiftc -o /tmp/spidy-preview Sources/Spidy/SpidyArt.swift tools/preview/main.swift
/tmp/spidy-preview tools/preview.png
