#!/bin/sh
# Installs golinks: gems, then the background LaunchAgent, then prints
# instructions for adding golinks as a Chrome search engine.
set -eu

DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
RUBY="$HOME/.rbenv/shims/ruby"

if [ ! -x "$RUBY" ]; then
  echo "error: $RUBY not found. Install rbenv and select a Ruby version with it (rbenv install / rbenv global), then re-run this script." >&2
  exit 1
fi

echo "Installing gems into $DIR/vendor/bundle..."
(cd "$DIR" && "$RUBY" -S bundle config set --local path 'vendor/bundle' && "$RUBY" -S bundle install)

"$DIR/launch-agent/install.sh"

PORT="${PORT:-51242}"
cat <<EOF

Next, add golinks as a Chrome search engine:

  1. Go to chrome://settings/searchEngines (or Settings > Search engine >
     Manage search engines and site search).
  2. Under "Site search", click "Add".
  3. Shortcut: go
     URL:      http://localhost:$PORT?query=%s
  4. Save.

Then typing "go wiki" in Chrome's address bar takes you to Wikipedia, and
"go" alone shows the list of all links.
EOF
