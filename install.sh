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

# The agent installed just above. Its port is set in
# launchd/com.lucasbraune.golinks.plist.template, which is where the service's port
# is chosen — server.rb's own default is 8080, the development port — so keep this
# in step if you change it there.
URL="http://localhost:51242"

sleep 1
# -L because "/" is the catch-all route with an empty query, which is a 302 to
# /links by design (typing "go" alone shows the list). Without it a healthy
# server reports its redirect as a failure.
STATUS=$(curl -sL -o /dev/null -w '%{http_code}' --max-time 5 "$URL/" || true)
if [ "$STATUS" = "200" ]; then
  echo
  echo "Verified: $URL/ answers."
else
  echo
  echo "warning: $URL/ did not answer yet (got '$STATUS'). The"
  echo "agent may still be starting; check ~/Library/Logs/golinks.error.log if it"
  echo "persists."
fi

# Deliberately a pointer rather than a third copy of the setup steps: the page walks
# through them with the values as click-to-copy buttons, and it fills in the port it
# is actually running on. Unquoted heredoc so $URL expands — there is nothing else in
# here for the shell to interpret.
cat <<EOF

One step left — teaching Chrome the "go" shortcut. Opening the link list now; the
instructions are at the top of the page, with each value as a click-to-copy button:

  $URL

Then typing "go wiki" in Chrome's address bar takes you to Wikipedia,
"go yt rory sutherland" searches YouTube, and "go" alone shows the list of
all links.
EOF

# Gated on the check above: opening the page before the agent answers just shows a
# connection error, which reads as the install itself having failed.
#
# Chrome by name rather than whatever the default browser is, because the steps on
# that page are steps through Chrome's own settings screen: following them means
# being in Chrome, so that's where the install should leave you. stderr is dropped
# because the failure here is expected and handled: `open -a` prints "Unable to find
# application" when Chrome isn't installed, which is noise next to the note below. A
# command in an `if` condition is exempt from `set -e`; the fallback isn't, hence its
# `|| true` — the URL is printed above either way, so a machine with no http://
# handler at all shouldn't fail the whole install on its last line.
if [ "$STATUS" = "200" ]; then
  if ! open -a "Google Chrome" "$URL" 2>/dev/null; then
    echo
    echo "note: Google Chrome not found, so the link list is opening in your default"
    echo "      browser instead. The links work from any browser, but the setup steps"
    echo "      shown at the top of the page walk through Chrome's settings, so"
    echo "      they're only worth following there."
    open "$URL" || true
  fi
fi