# golinks

A tiny Sinatra server that redirects short "go-links" (like `wiki`) to full URLs.

## Install

```sh
./install.sh
```

Run it as your normal user (nothing needs root). It:

1. checks Ruby is available via the rbenv shim at `~/.rbenv/shims/ruby` and
   installs the gems listed in `Gemfile` into `vendor/bundle` inside this repo,
   so they don't depend on or pollute your global gem set;
2. installs the per-user LaunchAgent that runs the server as you — see [Run as
   a background service](#run-as-a-background-service) — and then opens
   <http://localhost:51242> in Chrome, where the link list walks through the one
   remaining step: adding the `go` shortcut (see [Use as a Chrome search
   engine](#use-as-a-chrome-search-engine)). Chrome specifically, because those
   steps walk through Chrome's own settings screen, so that's where following
   them means being; without Chrome installed it falls back to your default
   browser and says so.

rbenv itself must already be installed with a Ruby version selected (`rbenv
install` / `rbenv global`). Gems are tied to the Ruby version they were
installed with, so re-run `./install.sh` after switching Ruby versions.

Once installed and the Chrome keyword is set up, type in Chrome's address bar:

```
go wiki                 -> Wikipedia
go yt rory sutherland   -> YouTube search
go                      -> the list of all links
```

## Start the server

```sh
ruby server.rb
```

This listens on http://localhost:8080 — the development port. The installed
background service runs on **51242** instead (an uncommon high port, chosen to
avoid collisions and because binding the tidier port 80 needs root), so a server
you start by hand to try something out doesn't fight the one already answering
`go` links in the background. That also means 51242 is the port the Chrome
shortcut points at, since the service is the server that's always up.

Requests whose `Host` header isn't a recognized local name are rejected with
`403`, so the app is only ever reached as localhost. To use a different port, set
the `PORT` environment variable:

```sh
PORT=3000 ruby server.rb
```

Stop it with `Ctrl-C`.

To run it automatically at login instead, see [Run as a background
service](#run-as-a-background-service) below.

## Development

Run the test suite:

```sh
ruby test/server_test.rb
```

Lint with [RuboCop](https://rubocop.org) (installed via the Gemfile's
`development` group):

```sh
bundle exec rubocop
```

`.rubocop.yml` documents where and why this repo's config departs from
RuboCop's defaults.

## Endpoints

| Request | Response |
|---|---|
| `GET /<name>` | `302` redirect to that link's URL |
| `GET /<name> <terms>` | `302` redirect to the link's search URL with `<terms>` filled in, if the link defines one |
| `GET /links` | `200` HTML page listing all links |
| `GET /` (or an unrecognized path) | `302` redirect to `/links` |

The link name comes from the URL **path**, so it works in any browser or with
`curl` — not just Chrome. Everything up to the first space is the name; the
rest is the search terms. That split is unambiguous because names can't
contain spaces: a name (or alias) is made of letters, digits, `.`, `_`, and
`-`, optionally in several `/`-separated segments (e.g. `a/b`). So
`GET /a/b c and d/e` looks up the link named `a/b` with search terms
`c and d/e`.

Links are defined in `data/links.csv`, one per line, with columns `name,url,search_url`.
`search_url` is optional; when present it is a template containing `%s`, which is
replaced by the URL-encoded search terms. For example, with

```csv
yt,https://www.youtube.com,https://www.youtube.com/results?search_query=%s
```

`http://localhost:51242/yt` opens YouTube's home page and
`http://localhost:51242/yt rory sutherland` opens
`https://www.youtube.com/results?search_query=rory+sutherland`. (51242 here and
below is the background service's port; a server started by hand with `ruby
server.rb` is on 8080.)

The file is reloaded on every request, so edits apply without restarting the
server. A canonical `links` entry points back at this server's own list page,
so `go links` shows the link list (it is re-inserted automatically if deleted).

### Adding, editing, and aliasing links

Links can be managed by editing `data/links.csv` directly, or from the browser
at `go links`: **Add link** at the top adds a new one, and hovering a row reveals
an edit button (&#9998;) at the right of its destination that opens an edit
page (which also has a **Delete this link** action). Edits write straight to
`data/links.csv` and, like manual edits, apply immediately.

A link can have any number of aliases &mdash; alternate names that resolve to
the exact same destination, e.g. `yt` for `youtube`. Aliases are shown as
outlined chips next to a link's name, and both the add and edit pages have an
**Aliases** section to add or remove them. They live in a second file,
`data/aliases.csv`, one per line, with columns `link,alias`:

```csv
link,alias
youtube,yt
```

`go yt` then behaves exactly like `go youtube`, including with search terms.

The filter box above the list narrows it down as you type, fuzzy-matching
against names, aliases, and destination URLs (via [Fuse.js](https://fusejs.io),
loaded as a version-pinned ES module from jsDelivr). Press `/` from anywhere
on the page to jump to it, and `Esc` to clear it; an empty box shows every
link again. The best match is highlighted as you type, and `Enter` goes
straight to it (`Cmd`/`Ctrl` `Enter` opens it in a new tab), so the usual trip
is a few characters and `Enter`. The up and down arrows step between the
visible names when you want a different one, and `Esc` steps back out — to the
search box from a link, then clearing the query.

The control in the footer cycles the colour theme between `system`, `light`
and `dark`. It starts on `system`, which follows the OS setting; an explicit
choice is remembered per browser in `localStorage` (no preference stored means
"follow the system", so clearing site data resets it). The theme is applied by a
blocking inline script in `<head>` on every page — a deferred or module script
would paint the system theme first and then correct itself, which is visible as a
flash on every load. Only that read-and-apply is inline; the toggle button is
wired up by `public/js/theme-toggle.js`.

## Use as a Chrome search engine

A keyword search engine is what makes the links usable from the address bar:
type `go wiki` instead of a full URL. Add one under Chrome Settings > Search
engine > Manage search engines and site search > Site search > Add:

- **Search engine:** `Go Links`
- **Shortcut:** `go`
- **URL with %s in place of query:** `http://localhost:51242/%s`

The link list shows these same two steps in a callout at the top of the page,
with each value as a click-to-copy button — Chrome won't let a page link to
`chrome://settings/searchEngines`, so copying and pasting is as direct as it
gets. The callout appears in every browser, not just Chrome: the steps only apply
to Chrome, but which browsers share that settings screen is a moving target
(Brave, Arc and Chromium send Chrome's User-Agent verbatim, while Edge and Opera
carry `Chrome/` in theirs but have their own screen), and guessing it wrong hides
the one thing a new install needs.

Dismiss the callout with the &times; once setup is done; `setup instructions` in
the footer brings it back, and stays there whether or not the callout is showing.
Dismissal is remembered per browser in `localStorage`, which is the right
granularity, since the Chrome entry itself is per browser.

Then `go wiki` takes you to Wikipedia and `go yt rory sutherland` searches
YouTube. Chrome encodes the spaces in multi-word searches as `+`; the server
decodes the path query-style, so `+` becomes a space just like `%20` (the one
edge case: a literal `+` in search terms must be typed as `%2B`). The port in the
URL has to match the server the shortcut is meant to reach, which is the
background service — `51242`, set in the LaunchAgent (see below), not
`server.rb`'s development default of `8080`.

## Run as a background service

A per-user launchd LaunchAgent
(`launchd/com.lucasbraune.golinks.plist.template`) starts the server at your
login, running as you (no root), on port `51242`, and restarts it if it crashes.
The plist template is where that port is chosen — `server.rb` itself defaults to
`8080`, the development port. `./install.sh` repeats `51242` to check and open the
agent once it's installed, so changing the port means editing both files and
re-running the installer. `./install.sh` sets the agent up; to (re)install it
directly:

```sh
./launchd/install.sh
```

This generates `~/Library/LaunchAgents/com.lucasbraune.golinks.plist` from the
template (substituting this repo's actual path and your `$HOME`, since launchd
does not expand `~` or `$HOME` itself), then loads it. Re-run it any time —
after moving the repo, or after editing the template — to regenerate the plist
and reload the service.

To stop and disable it:

```sh
launchctl bootout gui/$(id -u)/com.lucasbraune.golinks
rm ~/Library/LaunchAgents/com.lucasbraune.golinks.plist
```

Logs are written to `~/Library/Logs/golinks.log` and `golinks.error.log`.

The agent launches the `launchd/golinks` wrapper rather than Ruby directly, so
macOS labels the background item "golinks" instead of "ruby". The wrapper runs
Ruby via the rbenv shim, so it follows rbenv version switches; gems are
per-Ruby-version, so re-run `./install.sh` after switching Ruby.
