#!/bin/bash
# Baut den Server auf diesem Mac (für den Intel-Mac-mini) und installiert ihn
# auf dem Mac mini als Dienst, der beim Anmelden automatisch startet.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -f scripts/config.sh ]; then
  echo "Missing scripts/config.sh – copy scripts/config.example.sh to scripts/config.sh and fill it in."
  exit 1
fi
source scripts/config.sh
TARGET="$MINI_USER@$MINI_HOST"

if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Swift fehlt. Bitte zuerst ausführen:  xcode-select --install"
  exit 1
fi

echo "==> Baue Server für den Mac mini (Intel) …"
swift build -c release --product VoiceServer --arch x86_64
BIN="$(swift build -c release --product VoiceServer --arch x86_64 --show-bin-path)/VoiceServer"
bash scripts/sign-server.sh "$BIN"

echo "==> Prüfe SSH-Zugang zu $TARGET …"
if ! ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new "$TARGET" true 2>/dev/null; then
  echo "    Einmalig: SSH-Schlüssel hinterlegen (Passwort des Mac mini eingeben)."
  [ -f ~/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519
  ssh-copy-id -i ~/.ssh/id_ed25519.pub "$TARGET"
fi

echo "==> Kopiere Dateien …"
ssh "$TARGET" 'mkdir -p ~/TheVoiceServer/Public ~/Library/LaunchAgents ~/Library/Logs'
scp -q "$BIN" "$TARGET:TheVoiceServer/VoiceServer.new"
scp -q -r Public/. "$TARGET:TheVoiceServer/Public/"

echo "==> Richte Dienst ein …"
ssh "$TARGET" bash -s -- "$PORT" "$BROWSER" "$SPACE_DELAY" <<'REMOTE'
set -e
PORT="$1"; BROWSER="$2"; SPACE_DELAY="$3"
cd ~/TheVoiceServer
mv -f VoiceServer.new VoiceServer
chmod +x VoiceServer
LABEL="io.github.fotocast.tvlauncher.server"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$HOME/TheVoiceServer/VoiceServer</string>
    <string>--port</string><string>$PORT</string>
    <string>--browser</string><string>$BROWSER</string>
    <string>--space-delay</string><string>$SPACE_DELAY</string>
    <string>--public</string><string>$HOME/TheVoiceServer/Public</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/TheVoiceServer.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/TheVoiceServer.log</string>
</dict>
</plist>
EOF
DOMAIN="gui/$(id -u)"
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
sleep 1
if ! launchctl bootstrap "$DOMAIN" "$PLIST"; then
  echo "FEHLER: Dienst konnte nicht gestartet werden."
  echo "Ist am Mac mini ein Benutzer angemeldet (Bildschirm entsperrt bzw. automatische Anmeldung)?"
  exit 1
fi
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then
    echo "Server läuft auf dem Mac mini (Port $PORT)."
    exit 0
  fi
  sleep 1
done
echo "Server antwortet nicht. Log ansehen: tail ~/Library/Logs/TheVoiceServer.log"
exit 1
REMOTE

echo "==> Prüfe Erreichbarkeit von diesem Mac …"
if curl -fsS -m 5 "http://$MINI_HOST:$PORT/api/health" >/dev/null; then
  echo "    OK: http://$MINI_HOST:$PORT"
else
  echo "    Nicht erreichbar. Falls am Mac mini eine Firewall-Meldung erscheint: 'Erlauben' klicken."
fi
