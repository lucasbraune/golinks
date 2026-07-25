ENV['BUNDLE_GEMFILE'] ||= File.expand_path('Gemfile', __dir__)
require 'bundler/setup'
require 'sinatra'
require 'csv'

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

# Reload on every request so edits to the CSV apply without a restart.
# Each entry is { url:, search_url: }; search_url is an optional template
# containing "%s", used when the query is "<name> <search terms>".
def links
  rows = CSV.read(LINKS_FILE, headers: true).reject { |row| row['name'].nil? }.map do |row|
    [row['name'], { url: row['url'], search_url: row['search_url'] }]
  end.to_h
  { 'go' => { url: "http://localhost:#{PORT}", search_url: nil } }.merge(rows)
end

# Returns the URL to redirect to for a query, or nil to show the link list.
# The first whitespace-separated token is the link name; the rest is the
# optional search terms.
def redirect_target(query, current_links)
  query = query.to_s.strip
  return nil if query.empty?

  entry = current_links[query]
  return entry[:url] if entry

  keyword, terms = query.split(' ', 2)
  entry = current_links[keyword]
  if entry && entry[:search_url] && terms && !terms.strip.empty?
    return entry[:search_url].sub('%s') { Rack::Utils.escape(terms.strip) }
  end

  nil
end

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
  current_links = links
  target = redirect_target(query, current_links)
  if target
    redirect target, 302
  else
    # One row per url, names within a row sorted, rows sorted by their first name.
    grouped = current_links
              .group_by { |_name, entry| entry[:url] }
              .transform_values { |pairs| pairs.sort_by { |name, _entry| name } }
              .sort_by { |_url, pairs| pairs.first.first }
    erb :index, locals: { grouped: grouped, links_file: LINKS_FILE }
  end
end
