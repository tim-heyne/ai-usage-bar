#!/bin/bash
set -euo pipefail

# Installiert "AI Usage Bar" in /Applications, entfernt die Download-Quarantäne
# und richtet den automatischen Start beim Login ein.

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/AI Usage Bar.app"
DEST="/Applications/AI Usage Bar.app"

echo "==> AI Usage Bar – Installation"

if [ ! -d "$SRC" ]; then
  echo "FEHLER: 'AI Usage Bar.app' liegt nicht neben diesem Skript."
  exit 1
fi

# Laufende Instanz beenden
pkill -f "AI Usage Bar.app" 2>/dev/null || true
sleep 1

# Nach /Applications kopieren
echo "==> Kopiere nach /Applications ..."
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

# Gatekeeper-Quarantäne entfernen (sonst 'nicht verifizierter Entwickler')
echo "==> Entferne Download-Quarantäne ..."
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

# Autostart beim Login einrichten (idempotent)
echo "==> Richte Autostart ein ..."
osascript -e 'tell application "System Events" to delete login item "AI Usage Bar"' 2>/dev/null || true
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/AI Usage Bar.app", hidden:true}' >/dev/null 2>&1 || true

# Starten
echo "==> Starte App ..."
open "$DEST"
sleep 2

echo ""
echo "Fertig! Oben rechts in der Menüleiste erscheint jetzt ein farbiger Ring,"
echo "der deinen Claude-Verbrauch der letzten 5 Stunden anzeigt."
echo "Fahr mit der Maus darüber, um Session- und Wochen-Verbrauch in Prozent zu sehen."
echo "Voraussetzung: Claude Code ist installiert und du bist eingeloggt."
echo "Falls 'Kein Login gefunden' erscheint: einmal 'claude' starten und einloggen."
