# frozen_string_literal: true

ENV['BUNDLE_GEMFILE'] ||= File.expand_path('Gemfile', __dir__)
require 'bundler/setup'
require 'json'
require 'sinatra'
require_relative 'lib/link_repository'
require_relative 'lib/api_helpers'

PORT = ENV.fetch('PORT', 51242).to_i
# Binding all interfaces makes the port reachable from the local network (not
# just this machine). Host authorization (below) rejects requests whose Host
# header isn't recognized, but the port itself is open.
set :bind, '0.0.0.0'
set :port, PORT

# Links live in data/links.csv by default; GOLINKS_LINKS_FILE overrides the
# path (the tests point it at a fixture). A relative value is resolved against
# this file's directory; an absolute one is used as-is.
LINKS_FILE = File.expand_path(ENV.fetch('GOLINKS_LINKS_FILE', 'data/links.csv'), __dir__)
# Aliases are a second CSV, not a column of links.csv: one row per alias
# (link,alias), so a link can have any number of aliases without needing a
# packed multi-value field.
ALIASES_FILE = File.expand_path(ENV.fetch('GOLINKS_ALIASES_FILE', 'data/aliases.csv'), __dir__)

repository = GoLinks::LinkRepository.new(links_file: LINKS_FILE, aliases_file: ALIASES_FILE, port: PORT)

helpers do
  def h(text)
    Rack::Utils.escape_html(text)
  end

  # Shortens text for display only; callers keep the full string for hrefs etc.
  def truncate(text, length = 80)
    return text if text.nil? || text.length <= length

    "#{text[0, length - 1]}…"
  end
end

# Management routes live under /links so a stored name can never collide with
# them (see GoLinks::LinkRepository::RESERVED_NAME_PATTERNS). Defined before the
# catch-all route below, since Sinatra matches routes in definition order and
# "/*" would otherwise swallow every path here too.
get '/links' do
  entries = repository.get_links.map do |l|
    { name: l.name, url: l.url, search_url: l.search_url, aliases: l.aliases, editable: l.name != 'links' }
  end
  erb :index, locals: { entries: entries }
end

get '/links/new' do
  erb :link_form, locals: {
    heading: 'Add a link', action: '/links/new',
    name: '', url: '', search_url: '', aliases: [], error: nil, original_name: nil
  }
end

post '/links/new' do
  repository.create_link(GoLinks::ApiHelpers.link_from_params(params))
  redirect '/links'
rescue ArgumentError, GoLinks::LinkRepository::InvalidNameError => e
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

  erb :link_form, locals: {
    heading: 'Edit link', action: "/links/#{link.name}/edit",
    name: link.name, url: link.url, search_url: link.search_url, aliases: link.aliases,
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

# The link name (and optional "<space>search terms") comes from the URL path,
# so http://go/wiki and http://go/yt rory sutherland work from any browser or
# from curl. path_info always begins with "/", which [1..] drops.
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
  else
    redirect '/links'
  end
end
