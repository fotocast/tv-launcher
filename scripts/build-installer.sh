#!/bin/bash
# Baut zwei einfache Installer (deutsch/englisch je nach Sprache des Macs):
#   dist/TV-Launcher-App-<Version>.pkg    → /Applications/TV Launcher.app (öffnet sich danach)
#   dist/TV-Launcher-Server-<Version>.pkg → Mac am Fernseher: ~/TheVoiceServer + Dienst, Bluetooth-Assistent aus,
#                                           öffnet Systemeinstellungen → Bedienungshilfen
# Universal (Intel + Apple Silicon), ab macOS 13.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/AppInfo.plist)"
BUILD="$(date +%Y%m%d%H%M)"
WORK="dist/installer-work"

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
cp -R Resources/*.lproj "$APP/Contents/Resources/"
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

# Ein Installer pro Seite – ohne Auswahl, damit nichts schiefgehen kann
make_installer() {   # $1 = app|server, $2 = Titel, $3 = Ausgabedatei
  cat > "$WORK/$1-distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>$2</title>
  <welcome file="welcome.html" mime-type="text/html"/>
  <conclusion file="conclusion.html" mime-type="text/html"/>
  <options customize="never" require-scripts="false" hostArchitectures="x86_64,arm64"/>
  <domains enable_localSystem="true"/>
  <volume-check>
    <allowed-os-versions><os-version min="13.0"/></allowed-os-versions>
  </volume-check>
  <choices-outline><line choice="main"/></choices-outline>
  <choice id="main" title="$2"><pkg-ref id="io.github.fotocast.tvlauncher.pkg.$1"/></choice>
  <pkg-ref id="io.github.fotocast.tvlauncher.pkg.$1" version="$VERSION">$1.pkg</pkg-ref>
</installer-gui-script>
XML
  productbuild --distribution "$WORK/$1-distribution.xml" --resources "installer/resources/$1" \
    --package-path "$WORK" "$3" >/dev/null
  echo "==> Fertig: $(pwd)/$3"
}

rm -f dist/TV-Launcher-*.pkg
make_installer app "TV Launcher" "dist/TV-Launcher-App-$VERSION.pkg"
make_installer server "TV Launcher Server" "dist/TV-Launcher-Server-$VERSION.pkg"
rm -rf "$WORK"
