#!/bin/sh
# Installs golinks: gems, then the per-user LaunchAgent that runs the server.
set -eu

if [ "$(id -u)" -eq 0 ]; then
  echo "error: run this as your normal user, not with sudo. It installs gems" >&2
  echo "       and a LaunchAgent into your account; nothing needs root." >&2
  exit 1
fi

DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
RUBY="$HOME/.rbenv/shims/ruby"

if [ ! -x "$RUBY" ]; then
  echo "error: $RUBY not found. Install rbenv and select a Ruby version with it (rbenv install / rbenv global), then re-run this script." >&2
  exit 1
fi

echo "Installing gems into $DIR/vendor/bundle..."
(cd "$DIR" && "$RUBY" -S bundle config set --local path 'vendor/bundle' && "$RUBY" -S bundle install)

echo
"$DIR/launchd/install.sh"

sleep 1
STATUS=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:51242/ || true)
if [ "$STATUS" = "200" ]; then
  echo
  echo "Verified: http://localhost:51242/ answers."
else
  echo
  echo "warning: http://localhost:51242/ did not answer yet (got '$STATUS'). The"
  echo "agent may still be starting; check ~/Library/Logs/golinks.error.log if it"
  echo "persists."
fi

cat <<'EOF'

Next, add golinks as a Chrome search engine:

  1. Go to chrome://settings/searchEngines (or Settings > Search engine >
     Manage search engines and site search).
  2. Under "Site search", click "Add".
  3. Shortcut: go
     URL:      http://localhost:51242/%s
  4. Save.

Then typing "go wiki" in Chrome's address bar takes you to Wikipedia,
"go yt rory sutherland" searches YouTube, and "go" alone shows the list of
all links.
EOF