# frozen_string_literal: true

ENV['BUNDLE_GEMFILE'] ||= File.expand_path('Gemfile', __dir__)
require 'bundler/setup'
# Before anything reads ENV. Values already set in the real environment win
# over .env, so an exported PORT or ANTHROPIC_API_KEY still overrides the file.
require 'dotenv/load'
require 'json'
require 'sinatra'
require_relative 'lib/link_repository'
require_relative 'lib/api_helpers'
require_relative 'lib/description_generator'

# 8080 is the development default — what `ruby server.rb` picks up. The installed
# background service deliberately runs somewhere else (PORT=51242, set by the
# LaunchAgent in launchd/), so starting a server by hand to try something out
# doesn't collide with the one already answering `go` links in the background. That
# also means 51242 is the port the Chrome site-search entry points at, since the
# agent is the server that's always up.
PORT = ENV.fetch('PORT', 8080).to_i
# Sinatra's host authorization rejects any request whose Host header isn't a
# recognized local name, so the app is only ever reached as localhost.
set :bind, '0.0.0.0'
set :port, PORT
# Static files ship with only Last-Modified, which lets Chrome cache them
# heuristically — an edited .js or .css then keeps serving the old copy across
# reloads, which looks exactly like the new code being broken. Everything here
# is read off local disk, so always revalidate.
set :static_cache_control, [:no_cache]

# Links live in data/links.csv by default; GOLINKS_LINKS_FILE overrides the
# path (the tests point it at a fixture). A relative value is resolved against
# this file's directory; an absolute one is used as-is.
LINKS_FILE = File.expand_path(ENV.fetch('GOLINKS_LINKS_FILE', 'data/links.csv'), __dir__)
# Aliases are a second CSV, not a column of links.csv: one row per alias
# (link,alias), so a link can have any number of aliases without needing a
# packed multi-value field.
ALIASES_FILE = File.expand_path(ENV.fetch('GOLINKS_ALIASES_FILE', 'data/aliases.csv'), __dir__)

repository = GoLinks::LinkRepository.new(links_file: LINKS_FILE, aliases_file: ALIASES_FILE, port: PORT)
# Cheap to build: DescriptionGenerator itself lazy-loads its Anthropic client
description_generator = GoLinks::DescriptionGenerator.new

helpers do
  def h(text)
    Rack::Utils.escape_html(text)
  end

  # Shortens text for display only; callers keep the full string for hrefs etc.
  def truncate(text, length = 80)
    return text if text.nil? || text.length <= length

    "#{text[0, length - 1]}…"
  end

  # Serializes obj for embedding in a <script type="application/json"> island.
  # "</" is escaped so a value containing a literal "</script>" can't close
  # the tag early and run whatever follows it as markup.
  def json_script(obj)
    obj.to_json.gsub('</', '<\/')
  end

  # One of the literal strings the setup callout asks you to type into Chrome's
  # settings, as a click-to-copy control. A <button>, not a link: copying is an
  # action and none of these navigate anywhere. That's not just a preference for
  # the chrome://settings one — a page is not allowed to navigate to a chrome://
  # URL at all, which is the reason the whole component is built around copying
  # rather than linking.
  #
  # tabindex="-1" for the same reason the alias chips and destination urls in
  # views/links.erb carry it: keeping every one of these in the tab order put
  # four stops in front of the search box, which is the thing a keyboard user
  # came to the page for — and the four strings are all readable on screen
  # anyway, so what tabbing to them would buy is a shortcut for retyping, not
  # access to anything. Copying is left to the mouse. Still a button, so it's
  # still announced and activatable as one under a screen reader.
  def copyable(text)
    escaped = h(text)
    # The accessible name says what activating it does; the visible string is
    # only the thing being copied.
    attrs = %(class="copyable" data-copyable tabindex="-1" aria-label="Copy #{escaped}")
    %(<button type="button" #{attrs}>#{escaped}</button>)
  end
end

# Management routes live under /links so a stored name can never collide with
# them (see GoLinks::LinkRepository::RESERVED_NAME_PATTERNS). Defined before the
# catch-all route below, since Sinatra matches routes in definition order and
# "/*" would otherwise swallow every path here too.
get '/links' do
  entries = repository.get_links.map do |l|
    { name: l.name, url: l.url, search_url: l.search_url, description: l.description,
      aliases: l.aliases, editable: l.name != 'links' }
  end
  # q pre-fills the filter, so a name that didn't resolve arrives here as a
  # search rather than being thrown away (see the catch-all route below).
  erb :links, locals: { entries: entries, query: params['q'].to_s }
end

# Backs the "Generate" button on the add/edit form. Under /links so it can
# never collide with a stored name (see RESERVED_NAME_PATTERNS), and POST so
# it isn't something a browser can be talked into prefetching — it costs an
# API call.
post '/links/describe' do
  content_type :json
  url = params['url'].to_s.strip
  halt 400, { error: 'Add a destination URL first.' }.to_json if url.empty?

  result = description_generator.describe_link(url)
  if result.success?
    { description: result.message }.to_json
  else
    # result.message carries the raw exception text, which is useful in the log
    # and useless in the form. Send the user something they can act on instead.
    logger.warn("describe_link failed for #{url}: #{result.message}")
    halt 502, { error: "Couldn't read that page. Write a description yourself." }.to_json
  end
# Every exit from this route is JSON, including an unexpected one: Sinatra would
# otherwise render its HTML error page, and the caller — which asked for JSON and
# has no use for markup — would fail on the parse instead of showing the error.
# halt uses throw, not raise, so the halts above pass through untouched.
rescue StandardError => e
  logger.error("describe_link crashed for #{params['url']}: #{e.class}: #{e.message}")
  halt 500, { error: 'Something broke while generating. Write a description yourself.' }.to_json
end

get '/links/new' do
  @title = 'Add a link'
  erb :link_form, locals: {
    heading: 'Add a link', action: '/links/new',
    name: '', url: '', search_url: '', description: '', aliases: [], error: nil, original_name: nil
  }
end

post '/links/new' do
  repository.create_link(GoLinks::ApiHelpers.link_from_params(params))
  redirect '/links'
rescue ArgumentError, GoLinks::LinkRepository::InvalidNameError => e
  @title = 'Add a link'
  erb :link_form, locals: GoLinks::ApiHelpers.link_form_locals(
    params, heading: 'Add a link', action: '/links/new', original_name: nil, error: e.message
  )
end

# The per-link routes use a named splat (*name), not :name — a plain :name
# stops at "/" and would make slash-named links (e.g. "a/b") unreachable
# here. The splat is anchored by the trailing /edit or /delete, so there is
# exactly one valid capture for any name, even one that itself ends in
# "/edit" (Mustermann backtracks: "/links/a/edit/edit" -> name "a/edit").
get '/links/*name/edit' do
  link = repository.get_links.find { |l| l.name == params['name'] }
  halt 404, "No link named “#{h(params['name'])}”." unless link

  @title = 'Edit link'
  erb :link_form, locals: {
    heading: 'Edit link', action: "/links/#{link.name}/edit",
    name: link.name, url: link.url, search_url: link.search_url,
    description: link.description, aliases: link.aliases,
    error: nil, original_name: link.name
  }
end

# The route's *name capture is the link's *old* name; `new_name` (the form
# field) is the name going forward, which may differ from it on a rename.
post '/links/*name/edit' do
  old_name = params['name']
  halt 404, "No link named “#{h(old_name)}”." unless repository.get_links.any? { |l| l.name == old_name }

  repository.create_link(GoLinks::ApiHelpers.link_from_params(params), replacing: old_name)
  redirect '/links'
rescue ArgumentError, GoLinks::LinkRepository::InvalidNameError => e
  @title = 'Edit link'
  erb :link_form, locals: GoLinks::ApiHelpers.link_form_locals(
    params, heading: 'Edit link', action: "/links/#{old_name}/edit",
            original_name: old_name, error: e.message
  )
end

post '/links/*name/delete' do
  name = params['name']
  halt 404, "No link named “#{h(name)}”." unless repository.get_links.any? { |l| l.name == name }

  repository.delete_link(name: name)
  redirect '/links'
end

# The link name (and optional "<space>search terms") comes from the URL path, so
# http://localhost:8080/wiki and http://localhost:8080/yt rory sutherland work from
# any browser or from curl — the Chrome shortcut is only a shorthand for typing one
# of these. path_info always begins with "/", which [1..] drops.
get '/*' do
  # Puma leaves PATH_INFO percent-encoded; unescape decodes it query-style, so
  # both "%20" and "+" become spaces. "+" is how Chrome's keyword encodes spaces
  # in its %s substitution, so this one path form serves both direct typing and
  # the Chrome keyword — no query string needed. (A literal "+" in search terms
  # must therefore be typed as "%2B".)
  query = Rack::Utils.unescape(request.path_info)[1..]
  target = GoLinks::ApiHelpers.redirect_target(query, repository.get_links)
  if target
    redirect target, 302
  elsif query.to_s.strip.empty?
    redirect '/links'
  else
    # No link matched. Rather than discard what was typed, hand it to the list's
    # filter — the search indexes descriptions as well as names, so "budgeting"
    # finds the link you meant even though nothing is called that. build_query
    # so "&", "#" and spaces survive the trip.
    redirect "/links?#{Rack::Utils.build_query(q: query.strip)}"
  end
end
