#!/bin/bash
# Baut das Installer-Paket dist/TV-Launcher-<Version>.pkg für beide Seiten:
#   - App (Fernbedienung) → /Applications/TV Launcher.app
#   - Server (Mac am Fernseher) → ~/TheVoiceServer + Dienst (per postinstall für den angemeldeten Benutzer)
# Universal (Intel + Apple Silicon), ab macOS 13.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/AppInfo.plist)"
BUILD="$(date +%Y%m%d%H%M)"
WORK="dist/installer-work"
OUT="dist/TV-Launcher-$VERSION.pkg"

echo "==> Baue App und Server (Intel + Apple Silicon) …"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$WORK"
APP_ROOT="$WORK/app-root"
SRV_ROOT="$WORK/server-root"
SUPPORT="Library/Application Support/TV Launcher"

echo "==> App-Bundle …"
APP="$APP_ROOT/Applications/TV Launcher.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP_ROOT/$SUPPORT"
cp "$BIN_DIR/VoiceApp" "$APP/Contents/MacOS/VoiceApp"
# Debug-Symbole entfernen (enthalten lokale Pfade des Build-Rechners)
strip -S -x "$APP/Contents/MacOS/VoiceApp"
cp Resources/AppInfo.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep -s - "$APP"
cp installer/uninstall.sh "$APP_ROOT/$SUPPORT/uninstall.sh"

echo "==> Server …"
mkdir -p "$SRV_ROOT/$SUPPORT/Server"
cp "$BIN_DIR/VoiceServer" "$SRV_ROOT/$SUPPORT/Server/VoiceServer"
strip -S -x "$SRV_ROOT/$SUPPORT/Server/VoiceServer"
bash scripts/sign-server.sh "$SRV_ROOT/$SUPPORT/Server/VoiceServer"
cp -R Public "$SRV_ROOT/$SUPPORT/Server/Public"
cp installer/setup-server.sh "$SRV_ROOT/$SUPPORT/Server/setup-server.sh"
cp installer/uninstall.sh "$SRV_ROOT/$SUPPORT/uninstall.sh"
chmod 755 "$SRV_ROOT/$SUPPORT/Server/setup-server.sh" "$SRV_ROOT/$SUPPORT/uninstall.sh" "$APP_ROOT/$SUPPORT/uninstall.sh"
find "$WORK" -name .DS_Store -delete
xattr -cr "$WORK"
# Sicherheitsnetz: keine Pfade mit dem Benutzernamen des Build-Rechners im Paket
if grep -rqa "/Users/$(id -un)" "$WORK"; then
  echo "FEHLER: Paket enthält lokale Pfade (/Users/$(id -un))."
  grep -rla "/Users/$(id -un)" "$WORK"
  exit 1
fi

echo "==> Pakete …"
# App nicht "verschieben", falls irgendwo schon eine Kopie liegt
pkgbuild --analyze --root "$APP_ROOT" "$WORK/app-components.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$WORK/app-components.plist"
pkgbuild --root "$APP_ROOT" --component-plist "$WORK/app-components.plist" --install-location / \
  --scripts installer/app-scripts --identifier io.github.fotocast.tvlauncher.pkg.app --version "$VERSION" \
  "$WORK/app.pkg" >/dev/null
pkgbuild --root "$SRV_ROOT" --install-location / \
  --scripts installer/server-scripts --identifier io.github.fotocast.tvlauncher.pkg.server --version "$VERSION" \
  "$WORK/server.pkg" >/dev/null

cat > "$WORK/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>TV Launcher</title>
  <welcome file="welcome.html" mime-type="text/html"/>
  <conclusion file="conclusion.html" mime-type="text/html"/>
  <options customize="always" require-scripts="false" hostArchitectures="x86_64,arm64"/>
  <domains enable_localSystem="true"/>
  <volume-check>
    <allowed-os-versions><os-version min="13.0"/></allowed-os-versions>
  </volume-check>
  <choices-outline>
    <line choice="app"/>
    <line choice="server"/>
  </choices-outline>
  <choice id="app" title="App (remote control)" start_selected="true"
          description="The Mac app to start and control playback. For the Mac you sit at.">
    <pkg-ref id="io.github.fotocast.tvlauncher.pkg.app"/>
  </choice>
  <choice id="server" title="Server (Mac connected to the TV)" start_selected="false"
          description="Only select this on the Mac connected to the TV. Starts at login, opens videos in the browser and serves the iPhone web app (port 8081).">
    <pkg-ref id="io.github.fotocast.tvlauncher.pkg.server"/>
  </choice>
  <pkg-ref id="io.github.fotocast.tvlauncher.pkg.app" version="$VERSION">app.pkg</pkg-ref>
  <pkg-ref id="io.github.fotocast.tvlauncher.pkg.server" version="$VERSION">server.pkg</pkg-ref>
</installer-gui-script>
XML

productbuild --distribution "$WORK/distribution.xml" --resources installer/resources \
  --package-path "$WORK" "$OUT" >/dev/null
rm -rf "$WORK"
echo "==> Fertig: $(pwd)/$OUT"
