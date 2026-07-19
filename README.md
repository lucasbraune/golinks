# golinks

A tiny Sinatra server that redirects short "go-links" (like `wiki`) to full URLs.

## Dependencies

- **Ruby 3.x.** Check with `ruby --version`.
- **The Sinatra gems:** `sinatra`, `puma`, and `rackup`. Install them with:

  ```sh
  gem install sinatra puma rackup
  ```

  These are installed per Ruby version, so if you switch Ruby versions you need
  to run this again for the new one.

- **rbenv (only for the background service).** The service runs Ruby via the
  rbenv shim at `~/.rbenv/shims/ruby` (called from the `golinks` wrapper script),
  so that path must exist and rbenv must be installed. If you don't use rbenv,
  either edit the `golinks` wrapper to point at your `ruby` (find it with
  `which ruby`), or skip the service and start the server manually. This is not
  required if you only run the server by hand with `ruby server.rb`.

## Start the server

```sh
ruby server.rb
```

The server listens on http://localhost:51242 by default (an uncommon high port,
chosen to avoid collisions). It binds to `127.0.0.1` only, so it is not reachable
from the network. To use a different port, set the `PORT` environment variable:

```sh
PORT=8080 ruby server.rb
```

Stop it with `Ctrl-C`.

To run it automatically at login instead, see [Run as a background
service](#run-as-a-background-service) below.

## Endpoints

| Request | Response |
|---|---|
| `GET /?query=<name>` | `302` redirect to that link's URL |
| `GET /?query=<name> <terms>` | `302` redirect to the link's search URL with `<terms>` filled in, if the link defines one |
| `GET /` (or an unrecognized query) | `200` HTML page listing all links |

The first whitespace-separated token is the link name and the rest is the
search terms.

Links are defined in `links.csv`, one per line, with columns `name,url,search_url`.
`search_url` is optional; when present it is a template containing `%s`, which is
replaced by the URL-encoded search terms. For example, with

```csv
yt,https://www.youtube.com,https://www.youtube.com/results?search_query=%s
```

`go yt` opens YouTube's home page and `go yt rory sutherland` opens
`https://www.youtube.com/results?search_query=rory+sutherland`.

The file is reloaded on every request, so edits apply without restarting the
server. A built-in `go` entry points back to this server, so `go go` shows the
link list.

## Use as a Chrome search engine

Go to Chrome Settings > Search Engine. Add a site search with:

- **Shortcut:** `go`
- **URL:** `http://localhost:51242?query=%s`

The port in the URL must match the one the server is running on (the default is
`51242`).

Then typing `go wiki` in the address bar takes you to Wikipedia, `go yt rory
sutherland` searches YouTube, and `go go` shows the list of all links. The
server must be running for this to work.

## Run as a background service

On macOS, a launchd LaunchAgent starts the server at login and restarts it if it
crashes. The agent file `com.lucasbraune.golinks.plist` lives in this repository;
install it by copying it into `~/Library/LaunchAgents/`:

```sh
cp com.lucasbraune.golinks.plist ~/Library/LaunchAgents/
```

The plist uses absolute paths (launchd does not expand `~` or `$HOME` in it), so
if you cloned this repo somewhere other than `~/dev/golinks`, edit the paths in
the copied plist to match.

Load / reload / unload it:

```sh
# Load (start now + at every login)
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.lucasbraune.golinks.plist

# Reload after editing the plist
launchctl bootout gui/$(id -u)/com.lucasbraune.golinks
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.lucasbraune.golinks.plist

# Stop and disable
launchctl bootout gui/$(id -u)/com.lucasbraune.golinks
```

Logs are written to `~/Library/Logs/golinks.log` and `golinks.error.log`.

The plist runs the `golinks` wrapper script, which in turn runs Ruby via the
rbenv shim (`~/.rbenv/shims/ruby`) rather than a specific version path, so it
keeps working when you upgrade Ruby with rbenv. The wrapper is named `golinks`
so the service shows up as "golinks" (not "ruby") in System Settings > General >
Login Items & Extensions. Note that gems are per-Ruby-version: after switching to
a new Ruby, reinstall the dependencies (`gem install sinatra puma rackup`) for
that version.
