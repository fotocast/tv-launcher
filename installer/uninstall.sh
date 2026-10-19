#!/bin/bash
# Removes TV Launcher (app and/or server) from this Mac.
#   sudo bash "/Library/Application Support/TV Launcher/uninstall.sh"
# Saved shows (~/Library/Application Support/TheVoiceServer) are kept.
set -u
LABEL="io.github.fotocast.tvlauncher.server"
USER_NAME="${1:-${SUDO_USER:-$(stat -f%Su /dev/console)}}"
USER_HOME="$(dscl . -read "/Users/$USER_NAME" NFSHomeDirectory | awk '{print $2}')"

launchctl bootout "gui/$(id -u "$USER_NAME")/$LABEL" 2>/dev/null || true
rm -f "$USER_HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$USER_HOME/TheVoiceServer"
rm -rf "/Applications/TV Launcher.app"
rm -rf "/Library/Application Support/TV Launcher"
pkgutil --forget io.github.fotocast.tvlauncher.pkg.app >/dev/null 2>&1 || true
pkgutil --forget io.github.fotocast.tvlauncher.pkg.server >/dev/null 2>&1 || true
echo "TV Launcher was removed. Your saved shows are still in $USER_HOME/Library/Application Support/TheVoiceServer."
