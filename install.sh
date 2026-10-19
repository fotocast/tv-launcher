#!/bin/bash
# Installiert alles in einem Rutsch:
#   1. Server auf dem Mac mini
#   2. App "TV Launcher" auf diesem Mac
set -euo pipefail
cd "$(dirname "$0")"
bash scripts/install-server.sh
bash scripts/build-app.sh
