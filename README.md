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
   a background service](#run-as-a-background-service) — and prints the steps
   for adding the `go` keyword to Chrome (see [Use as a Chrome search
   engine](#use-as-a-chrome-search-engine)).

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

The server listens on http://localhost:51242 by default (an uncommon high
port, chosen to avoid collisions and because binding the tidier port 80 needs
root). It binds all interfaces (`0.0.0.0`), so the port is reachable from the
local network; requests whose `Host` header isn't a recognized local name are
rejected with `403`, which blocks casual access, but the port itself is open.
To use a different port, set the `PORT` environment variable:

```sh
PORT=8080 ruby server.rb
```

Stop it with `Ctrl-C`.

To run it automatically at login instead, see [Run as a background
service](#run-as-a-background-service) below.

## Endpoints

| Request | Response |
|---|---|
| `GET /<name>` | `302` redirect to that link's URL |
| `GET /<name> <terms>` | `302` redirect to the link's search URL with `<terms>` filled in, if the link defines one |
| `GET /` (or an unrecognized path) | `200` HTML page listing all links |

The link name comes from the URL **path**, so it works in any browser or with
`curl` — not just Chrome. Everything up to the first space is the name (so a
name may itself contain slashes, e.g. `a/b`); the rest is the search terms. For
example `GET /a/b c and d/e` looks up the link named `a/b` with search terms
`c and d/e`.

Links are defined in `data/links.csv`, one per line, with columns `name,url,search_url`.
`search_url` is optional; when present it is a template containing `%s`, which is
replaced by the URL-encoded search terms. For example, with

```csv
yt,https://www.youtube.com,https://www.youtube.com/results?search_query=%s
```

`http://localhost:51242/yt` opens YouTube's home page and
`http://localhost:51242/yt rory sutherland` opens
`https://www.youtube.com/results?search_query=rory+sutherland`.

The file is reloaded on every request, so edits apply without restarting the
server. A built-in `go` entry points back to this server, so `go go` shows the
link list.

## Use as a Chrome search engine

A keyword search engine is what makes the links usable from the address bar:
type `go wiki` instead of a full URL. Add one under Chrome Settings > Search
engine > Site search > Add:

- **Shortcut:** `go`
- **URL:** `http://localhost:51242/%s`

Then `go wiki` takes you to Wikipedia and `go yt rory sutherland` searches
YouTube. Chrome encodes the spaces in multi-word searches as `+`; the server
decodes the path query-style, so `+` becomes a space just like `%20` (the one
edge case: a literal `+` in search terms must be typed as `%2B`). The port in
the URL must match the one the server runs on (default `51242`).

## Run as a background service

A per-user launchd LaunchAgent
(`launchd/com.lucasbraune.golinks.plist.template`) starts the server at your
login, running as you (no root), and restarts it if it crashes. `./install.sh`
sets it up; to (re)install it directly:

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
