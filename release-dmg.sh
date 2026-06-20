#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Baut "AI Usage Bar.app" und packt sie zusammen mit install.sh
# und README in ein verteilbares DMG (dist/AI Usage Bar.dmg).
#
# Nutzt create-dmg falls vorhanden (schöneres Fenster),
# sonst hdiutil als Fallback (immer verfügbar, kein brew nötig).
# ─────────────────────────────────────────────────────────────

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/AIUsageBar.swift"
ICON="$DIR/AppIcon.icns"

APP_NAME="AI Usage Bar"
VOL_NAME="AI Usage Bar"
VERSION="1.0"            # bei neuem Release nur hier hochzählen
STAGING="$DIR/dist/dmg-staging"
APP="$STAGING/$APP_NAME.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"
DMG="$DIR/dist/$APP_NAME.dmg"

# ── 1. Staging aufräumen ─────────────────────────────────────
echo "==> Räume Staging auf ..."
rm -rf "$STAGING" "$DMG"
mkdir -p "$MACOS" "$RES"

# ── 2. App kompilieren (optimiert) ───────────────────────────
echo "==> Kompiliere (optimiert) ..."
swiftc -O -o "$MACOS/AIUsageBar" "$SRC"

# ── 3. Icon einbinden ────────────────────────────────────────
ICON_PLIST_KEY=""
if [ -f "$ICON" ]; then
  cp "$ICON" "$RES/AppIcon.icns"
  ICON_PLIST_KEY="    <key>CFBundleIconFile</key>        <string>AppIcon</string>"
fi

# ── 4. Info.plist schreiben (LSUIElement = kein Dock-Icon) ────
echo "==> Schreibe Info.plist ..."
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>AI Usage Bar</string>
    <key>CFBundleDisplayName</key>     <string>AI Usage Bar</string>
    <key>CFBundleExecutable</key>      <string>AIUsageBar</string>
    <key>CFBundleIdentifier</key>      <string>de.it-heyne.aiusagebar</string>
    <key>CFBundleVersion</key>         <string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
$ICON_PLIST_KEY
</dict>
</plist>
PLIST

# ── 5. Ad-hoc signieren (kostenlos, Apple-Silicon-Stabilität) ─
echo "==> Signiere (ad-hoc) ..."
codesign --force --deep --sign - "$APP" 2>/dev/null || true

# ── 6. install.sh beilegen + README als PDF erzeugen ─────────
echo "==> Lege install.sh bei ..."
cp "$DIR/dist-files/install.sh" "$STAGING/install.sh"
chmod +x "$STAGING/install.sh"

echo "==> Erzeuge README.pdf (nativ, ohne Abhängigkeiten) ..."
MD2PDF_BIN="$(mktemp -t md2pdf)"
swiftc -O -o "$MD2PDF_BIN" "$DIR/md2pdf.swift"
"$MD2PDF_BIN" "$DIR/dist-files/README.md" "$STAGING/README.pdf"
rm -f "$MD2PDF_BIN"

# ── 7. DMG bauen ─────────────────────────────────────────────
echo "==> Baue DMG ..."
if command -v create-dmg >/dev/null 2>&1; then
  create-dmg \
    --volname "$VOL_NAME" \
    --window-pos 200 120 \
    --window-size 640 380 \
    --icon-size 96 \
    --icon "$APP_NAME.app" 160 170 \
    --icon "install.sh"    320 170 \
    --icon "README.pdf"    480 170 \
    --no-internet-enable \
    "$DMG" "$STAGING"
else
  echo "    (create-dmg nicht gefunden – nutze hdiutil)"
  hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGING" \
    -ov -format UDZO "$DMG" >/dev/null
fi

# Staging-Ordner aufräumen (nicht mit ins Verzeichnis legen)
rm -rf "$STAGING"

echo ""
echo "✅  Fertig: $DMG"
echo "    Verteile diese eine Datei. Der Nutzer öffnet sie und"
echo "    führt einmal 'install.sh' aus (Details siehe README im DMG)."
