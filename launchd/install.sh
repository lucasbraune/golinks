#!/bin/sh
# Installs the golinks LaunchAgent so the server starts automatically at login,
# running as you (no root), on port 51242 — the plist template is where that port
# is chosen, and it's the port the Chrome shortcut points at. Safe to re-run after
# moving the repo or editing the plist template.
set -eu

LABEL=com.lucasbraune.golinks

if [ "$(id -u)" -eq 0 ]; then
  echo "error: run this as your normal user, not with sudo — the agent must" >&2
  echo "       be installed in your own launchd session." >&2
  exit 1
fi

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
DEST="$HOME/Library/LaunchAgents/$LABEL.plist"

sed -e "s|__REPO_DIR__|$REPO_DIR|g" -e "s|__HOME__|$HOME|g" \
  "$SCRIPT_DIR/$LABEL.plist.template" > "$DEST"

if launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  # launchd needs a moment to release the port after unloading.
  sleep 1
fi
launchctl bootstrap "gui/$(id -u)" "$DEST"

echo "Installed and started the golinks LaunchAgent from $REPO_DIR"
echo "Logs: $HOME/Library/Logs/golinks.log / golinks.error.log"
