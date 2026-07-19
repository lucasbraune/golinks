#!/bin/sh
# Installs the golinks LaunchAgent so the server starts automatically at
# login. Safe to re-run after moving the repo or editing the plist template.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
DEST="$HOME/Library/LaunchAgents/com.lucasbraune.golinks.plist"

sed -e "s|__REPO_DIR__|$REPO_DIR|g" -e "s|__HOME__|$HOME|g" \
  "$SCRIPT_DIR/com.lucasbraune.golinks.plist.template" > "$DEST"

if launchctl bootout "gui/$(id -u)/com.lucasbraune.golinks" >/dev/null 2>&1; then
  # launchd needs a moment to release the port after unloading.
  sleep 1
fi
launchctl bootstrap "gui/$(id -u)" "$DEST"

echo "Installed and started the golinks LaunchAgent from $REPO_DIR"
echo "Logs: $HOME/Library/Logs/golinks.log / golinks.error.log"
