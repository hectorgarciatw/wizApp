#!/bin/bash
# Compila Luz WiZ, arma el .app y lo instala en ~/Applications.
# Uso: ./build.sh          compila e instala
#      ./build.sh --open   además la abre
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Luz WiZ.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/LuzWiz "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"

mkdir -p ~/Applications
pkill -x LuzWiz 2>/dev/null || true
rm -rf ~/Applications/"Luz WiZ.app"
cp -R "$APP" ~/Applications/
echo "Instalada en ~/Applications/Luz WiZ.app"

if [ "${1:-}" = --open ]; then open ~/Applications/"Luz WiZ.app"; fi
