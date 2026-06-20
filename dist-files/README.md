# AI Usage Bar – Menüleisten-App

Zeigt deinen aktuellen Claude-Verbrauch direkt in der macOS-Menüleiste.

Klick auf das Menüleisten-Element zeigt Details (Balken, Prozent, wann sich das Limit zurücksetzt).

## Voraussetzungen
- Mac mit **Apple Silicon** (M1/M2/M3/M4), macOS 13 oder neuer
- **Claude Code** ist installiert und du bist eingeloggt
  (die App liest deinen Login lokal aus – es werden keine Zugangsdaten übertragen oder gespeichert)

## Installation
1. Das **DMG per Doppelklick öffnen**.
2. Im Finder Rechtsklick auf **install.sh** → *Öffnen mit* → *Terminal*
   – oder im Terminal: `bash "/Pfad/zu/install.sh"`
3. Fertig. Die App erscheint in der Menüleiste und startet künftig automatisch beim Login.

Falls in der Menüleiste **„Claude ⚠ / Kein Login gefunden"** steht: einmal `claude` im Terminal
starten und einloggen, dann im App-Menü *Jetzt aktualisieren* wählen.

## Deinstallation
```bash
osascript -e 'tell application "System Events" to delete login item "AI Usage Bar"'
rm -rf "/Applications/AI Usage Bar.app"
```

## Hinweise
- Die App fragt einen inoffiziellen Endpoint ab (dieselbe Quelle wie `/usage` in Claude Code).
  Funktion kann sich theoretisch ändern, falls Anthropic den Endpoint anpasst.
- Aktualisierung: automatisch alle 10 Minuten und beim Öffnen des Menüs (max. 1×/Minute).

## Lizenz & Haftungsausschluss
Dieses Projekt steht unter der **MIT-Lizenz** (siehe `LICENSE`).

Dies ist ein inoffizielles Community-Tool und steht **in keiner Verbindung zu Anthropic**.
„Claude" und „Anthropic" sind Marken ihrer jeweiligen Inhaber. Die App nutzt einen inoffiziellen
Endpoint, der sich jederzeit ändern oder wegfallen kann – die Funktion wird ohne Gewähr bereitgestellt.
