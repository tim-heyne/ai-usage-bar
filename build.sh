#!/bin/bash
set -euo pipefail

# Baut "AI Usage Bar.app" nach /Applications/
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/AIUsageBar.swift"
ICON="$DIR/AppIcon.icns"
APP="/Applications/AI Usage Bar.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

echo "Baue $APP ..."
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

# Kompilieren (optimiert)
swiftc -O -o "$MACOS/AIUsageBar" "$SRC"

# Icon einbinden, falls vorhanden
ICON_PLIST_KEY=""
if [ -f "$ICON" ]; then
  cp "$ICON" "$RES/AppIcon.icns"
  ICON_PLIST_KEY="    <key>CFBundleIconFile</key>        <string>AppIcon</string>"
fi

# Info.plist – LSUIElement = kein Dock-Icon
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>AI Usage Bar</string>
    <key>CFBundleDisplayName</key>     <string>AI Usage Bar</string>
    <key>CFBundleExecutable</key>      <string>AIUsageBar</string>
    <key>CFBundleIdentifier</key>      <string>de.it-heyne.aiusagebar</string>
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
$ICON_PLIST_KEY
</dict>
</plist>
PLIST

# Ad-hoc signieren (verhindert Gatekeeper-Meckern beim lokalen Start)
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "Fertig: $APP"
