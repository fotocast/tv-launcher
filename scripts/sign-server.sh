#!/bin/bash
# Signiert den Server mit einem eigenen, festen Zertifikat (statt ad-hoc).
# Dadurch bleibt die Berechtigung "Bedienungshilfen" am Mac mini auch nach
# einer Neuinstallation gültig – bei ad-hoc-Signatur ändert sie sich bei jedem Bau.
#
# Das Zertifikat wird beim ersten Mal erzeugt und liegt in einem eigenen
# Schlüsselbund auf diesem Mac (nicht im Anmelde-Schlüsselbund):
#   ~/Library/Application Support/TheVoiceBuild/
# Wird dieser Ordner gelöscht, entsteht ein neues Zertifikat und die
# Berechtigung muss am Mac mini einmal neu erteilt werden.
#
# Aufruf: bash scripts/sign-server.sh <Pfad zur VoiceServer-Datei>
set -euo pipefail
BIN="$1"
IDENTIFIER="io.github.fotocast.tvlauncher.server"
NAME="The Voice Server Signing"
DIR="$HOME/Library/Application Support/TheVoiceBuild"
KC="$DIR/signing.keychain-db"
PWFILE="$DIR/keychain-password"

if [ ! -f "$KC" ]; then
  echo "    Erzeuge einmalig ein Signatur-Zertifikat …"
  mkdir -p "$DIR"
  chmod 700 "$DIR"
  openssl rand -hex 24 > "$PWFILE"
  chmod 600 "$PWFILE"
  PW="$(cat "$PWFILE")"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
EOF
  openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
  openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -passout "pass:$PW"
  security create-keychain -p "$PW" "$KC"
  security set-keychain-settings "$KC"   # nicht automatisch sperren
  security unlock-keychain -p "$PW" "$KC"
  security import "$TMP/id.p12" -k "$KC" -P "$PW" -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PW" "$KC" >/dev/null
fi

PW="$(cat "$PWFILE")"
security unlock-keychain -p "$PW" "$KC"

# codesign findet die Identität nur, wenn der Schlüsselbund in der Suchliste steht:
# kurz hinzufügen, signieren, danach die alte Liste wiederherstellen.
OLD_LIST=()
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line#\"}"; line="${line%\"}"
  [ -n "$line" ] && OLD_LIST+=("$line")
done < <(security list-keychains -d user)
security list-keychains -d user -s "${OLD_LIST[@]}" "$KC"
STATUS=0
codesign --force -s "$NAME" -i "$IDENTIFIER" "$BIN" 2>/dev/null || STATUS=$?
security list-keychains -d user -s "${OLD_LIST[@]}"

if [ "$STATUS" -ne 0 ]; then
  echo "    Signieren mit Zertifikat fehlgeschlagen – nutze ad-hoc-Signatur."
  echo "    (Dann muss die Berechtigung 'Bedienungshilfen' nach jeder Installation neu erteilt werden.)"
  codesign --force -s - -i "$IDENTIFIER" "$BIN"
fi
