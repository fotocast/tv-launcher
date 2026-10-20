#!/bin/bash
# Baut die SwiftUI-App "TV Launcher" und legt sie in den Programme-Ordner.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Swift fehlt. Bitte zuerst ausführen:  xcode-select --install"
  exit 1
fi

echo "==> Baue App …"
swift build -c release --product VoiceApp
BIN="$(swift build -c release --product VoiceApp --show-bin-path)/VoiceApp"

APP="dist/TV Launcher.app"
rm -rf "$APP" "dist/The Voice.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/VoiceApp"
cp Resources/AppInfo.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
codesign --force --deep -s - "$APP"

if [ -w /Applications ]; then
  # Alte Version unter dem früheren Namen "The Voice" entfernen
  # Laufende App beenden, sonst öffnet "open" weiter die alte Version
  osascript -e 'quit app "TV Launcher"' >/dev/null 2>&1 || true
  osascript -e 'quit app "The Voice"' >/dev/null 2>&1 || true
  sleep 1
  rm -rf "/Applications/The Voice.app" "/Applications/TV Launcher.app"
  cp -R "$APP" /Applications/
  echo "==> Fertig: /Applications/TV Launcher.app"
  open "/Applications/TV Launcher.app"
else
  echo "==> Fertig: $(pwd)/$APP  (in den Programme-Ordner ziehen)"
  open "$APP"
fi
