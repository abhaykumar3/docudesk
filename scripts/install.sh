#!/bin/bash
# Builds DocuDesk in release mode and installs it into /Applications.
# Usage: scripts/install.sh
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh release

DEST="/Applications/DocuDesk.app"
if pgrep -x DocuDesk >/dev/null; then
    echo "Quitting the running copy of DocuDesk…"
    osascript -e 'quit app "DocuDesk"' || true
    sleep 2
fi

# Replacing the app never touches your data: documents live in the workspace folder you chose.
rm -rf "$DEST"
ditto build/DocuDesk.app "$DEST"
echo "Installed $DEST"
open "$DEST"
