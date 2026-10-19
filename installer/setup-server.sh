#!/bin/bash
# Sets up the TV Launcher server for one user (the Mac connected to the TV).
# Run as root by the installer package (postinstall); can also be run by hand:
#   sudo bash "/Library/Application Support/TV Launcher/Server/setup-server.sh" [user]
#
# - copies the server and the web app to ~/TheVoiceServer
# - creates and starts ~/Library/LaunchAgents/io.github.fotocast.tvlauncher.server.plist
# - browser: keeps the previous setting, otherwise Firefox → Google Chrome → Safari
set -u
SRC="$(cd "$(dirname "$0")" && pwd)"
LABEL="io.github.fotocast.tvlauncher.server"
PORT=8081
SPACE_DELAY=10

USER_NAME="${1:-$(stat -f%Su /dev/console)}"
if [ -z "$USER_NAME" ] || [ "$USER_NAME" = "root" ] || [ "$USER_NAME" = "loginwindow" ]; then
  echo "No user is logged in. Log in and run:"
  echo "  sudo bash \"$SRC/setup-server.sh\" <user>"
  exit 0
fi
USER_ID="$(id -u "$USER_NAME")"
USER_HOME="$(dscl . -read "/Users/$USER_NAME" NFSHomeDirectory | awk '{print $2}')"
GROUP="$(id -gn "$USER_NAME")"
DIR="$USER_HOME/TheVoiceServer"
PLIST="$USER_HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$USER_HOME/Library/Logs/TheVoiceServer.log"

# Browser: keep an existing setting
BROWSER=""
if [ -f "$PLIST" ]; then
  i=0
  while ARG="$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:$i" "$PLIST" 2>/dev/null)"; do
    if [ "$ARG" = "--browser" ]; then
      BROWSER="$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:$((i + 1))" "$PLIST" 2>/dev/null)"
      break
    fi
    i=$((i + 1))
  done
fi
if [ -z "$BROWSER" ]; then
  for app in Firefox "Google Chrome"; do
    if [ -d "/Applications/$app.app" ] || [ -d "$USER_HOME/Applications/$app.app" ]; then
      BROWSER="$app"
      break
    fi
  done
  BROWSER="${BROWSER:-Safari}"
fi
echo "User: $USER_NAME, browser: $BROWSER, port: $PORT"

# Stop a running server
launchctl bootout "gui/$USER_ID/$LABEL" 2>/dev/null || true
sleep 1

mkdir -p "$DIR/Public" "$USER_HOME/Library/LaunchAgents" "$USER_HOME/Library/Logs"
cp -f "$SRC/VoiceServer" "$DIR/VoiceServer"
chmod 755 "$DIR/VoiceServer"
rm -rf "$DIR/Public"
cp -R "$SRC/Public" "$DIR/Public"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$DIR/VoiceServer</string>
    <string>--port</string><string>$PORT</string>
    <string>--browser</string><string>$BROWSER</string>
    <string>--space-delay</string><string>$SPACE_DELAY</string>
    <string>--public</string><string>$DIR/Public</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF
chown -R "$USER_NAME:$GROUP" "$DIR" "$PLIST"
touch "$LOG" && chown "$USER_NAME:$GROUP" "$LOG"

if ! launchctl bootstrap "gui/$USER_ID" "$PLIST"; then
  echo "Could not start the server now – it will start the next time $USER_NAME logs in."
  exit 0
fi
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then
    echo "Server is running (port $PORT)."
    exit 0
  fi
  sleep 1
done
echo "Server is not answering yet. Log: $LOG"
exit 0
