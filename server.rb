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
# Aliases are a second CSV, not a column of links.csv: one row per alias
# (link,alias), so a link can have any number of aliases without needing a
# packed multi-value field. An alias behaves exactly like its link everywhere
# — `links` below resolves it to the identical { url:, search_url: } entry.
ALIASES_FILE = File.expand_path(ENV.fetch('GOLINKS_ALIASES_FILE', 'data/aliases.csv'), __dir__)

# "go" is the synthetic self-link (see `links` below), not a CSV row, so it
# can't be edited or deleted. "new" is reserved so a stored name can never
# shadow the GET/POST /new route below. A name ending in "/edit" is reserved
# for the same reason, against GET/POST /:name/edit — Sinatra matches that
# route before the catch-all "/*" and would win, making such a name
# unreachable by path.
RESERVED_NAMES = ['go', 'new'].freeze
RESERVED_SUFFIX = '/edit'

# Raw rows from the CSV, in file order. Each is { name:, url:, search_url: }.
# A trailing blank line in the CSV parses as an all-nil row; drop it.
def read_links
  CSV.read(LINKS_FILE, headers: true).reject { |row| row['name'].nil? }.map do |row|
    { name: row['name'], url: row['url'], search_url: row['search_url'] }
  end
end

# Rewrites the whole links CSV. Written to a temp file and renamed into place
# so a concurrent request never reads a half-written file. There's no locking
# beyond that — fine for one person editing their own links, not for
# concurrent writers.
def write_links(rows)
  tmp = "#{LINKS_FILE}.tmp"
  CSV.open(tmp, 'w') do |csv|
    csv << %w[name url search_url]
    rows.each { |row| csv << [row[:name], row[:url], row[:search_url]] }
  end
  File.rename(tmp, LINKS_FILE)
end

# Raw rows from the aliases CSV. Each is { link:, alias: }. `link` names the
# canonical link the alias points to; it isn't validated against links.csv
# here, so a dangling alias (pointing at a link that's since been renamed or
# deleted) is simply ignored by `links`, not an error.
def read_aliases
  CSV.read(ALIASES_FILE, headers: true).reject { |row| row['alias'].nil? }.map do |row|
    { link: row['link'], alias: row['alias'] }
  end
end

def write_aliases(rows)
  tmp = "#{ALIASES_FILE}.tmp"
  CSV.open(tmp, 'w') do |csv|
    csv << %w[link alias]
    rows.each { |row| csv << [row[:link], row[:alias]] }
  end
  File.rename(tmp, ALIASES_FILE)
end

# Reload on every request so edits to the CSVs — by hand, or via the
# management routes below — apply without a restart. Each entry is
# { url:, search_url: }; search_url is an optional template containing "%s",
# used when the query is "<name> <search terms>". Aliases are merged in last,
# each resolving to its link's entry, so "go/yt" behaves exactly like
# "go/youtube".
def links
  canonical = read_links.map { |r| [r[:name], { url: r[:url], search_url: r[:search_url] }] }.to_h
  aliased = read_aliases.each_with_object({}) do |a, memo|
    entry = canonical[a[:link]]
    memo[a[:alias]] = entry if entry
  end
  { 'go' => { url: "http://localhost:#{PORT}", search_url: nil } }.merge(canonical).merge(aliased)
end

# Every name currently resolvable: every canonical link's name, plus every
# alias. A link's primary name and its aliases are both just names in this
# same one namespace — a link can't be named what an alias already is, or
# vice versa, since there'd be no way to tell which entry "go/<name>" means.
def all_names(link_rows, alias_rows)
  link_rows.map { |r| r[:name] } + alias_rows.map { |a| a[:alias] }
end

# Returns an error message, or nil if `name` is acceptable to save — as a
# link's primary name or as one of its aliases; both go through this same
# check. `taken` is every name this candidate must not collide with: normally
# all_names(...), minus whatever this save is intentionally replacing (a
# link's own old name and its own old aliases), so re-submitting a link
# unchanged doesn't collide with itself.
def validate_name(name, taken)
  return 'Name is required.' if name.empty?
  return "“#{name}” is a reserved name." if RESERVED_NAMES.include?(name)
  return "A name can't end in “#{RESERVED_SUFFIX}”." if name.end_with?(RESERVED_SUFFIX)
  return "“#{name}” already exists." if taken.include?(name)

  nil
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

# Management routes for links.csv/aliases.csv, at /new and /:name/edit so a
# stored name can never collide with them (see RESERVED_NAMES/RESERVED_SUFFIX
# above). There's no standalone list page — editing happens inline from "/"
# via each link's edit button, and adding via the "Add link" button there.
# Defined before the catch-all route below, since Sinatra matches routes in
# definition order and "/*" would otherwise swallow every path here too.
get '/new' do
  erb :link_form, locals: {
    heading: 'Add a link', action: '/new',
    original_name: nil, name: '', url: '', search_url: '', aliases: [], error: nil
  }
end

post '/new' do
  link_rows = read_links
  alias_rows = read_aliases
  name = params['name'].to_s.strip
  url = params['url'].to_s.strip
  search_url = params['search_url'].to_s.strip
  raw_aliases = Array(params['aliases'])
  alias_names = raw_aliases.map(&:strip).reject(&:empty?)

  taken = all_names(link_rows, alias_rows)
  error = validate_name(name, taken)
  error ||= 'Destination URL is required.' if url.empty?
  error ||= alias_names.map { |a| validate_name(a, taken) }.compact.first
  error ||= "An alias can't be the same as the link's name." if alias_names.include?(name)
  error ||= 'Aliases must be unique.' if alias_names.uniq.length != alias_names.length

  if error
    return erb :link_form, locals: {
      heading: 'Add a link', action: '/new',
      original_name: nil, name: name, url: url, search_url: search_url, aliases: raw_aliases, error: error
    }
  end

  link_rows << { name: name, url: url, search_url: search_url.empty? ? nil : search_url }
  write_links(link_rows)
  alias_names.each { |a| alias_rows << { link: name, alias: a } }
  write_aliases(alias_rows)
  redirect '/'
end

get '/:name/edit' do
  link_rows = read_links
  entry = link_rows.find { |r| r[:name] == params['name'] }
  halt 404, "No link named “#{h(params['name'])}”." unless entry

  own_aliases = read_aliases.select { |a| a[:link] == entry[:name] }.map { |a| a[:alias] }.sort

  erb :link_form, locals: {
    heading: 'Edit link', action: "/#{Rack::Utils.escape_path(entry[:name])}/edit",
    original_name: entry[:name], name: entry[:name], url: entry[:url],
    search_url: entry[:search_url], aliases: own_aliases, error: nil
  }
end

post '/:name/edit' do
  link_rows = read_links
  alias_rows = read_aliases
  original_name = params['name']
  entry = link_rows.find { |r| r[:name] == original_name }
  halt 404, "No link named “#{h(original_name)}”." unless entry

  new_name = params['new_name'].to_s.strip
  url = params['url'].to_s.strip
  search_url = params['search_url'].to_s.strip
  raw_aliases = Array(params['aliases'])
  alias_names = raw_aliases.map(&:strip).reject(&:empty?)

  # What this save may reclaim without it counting as a collision: the link's
  # own current name and its own current aliases.
  own_old_names = [original_name] + alias_rows.select { |a| a[:link] == original_name }.map { |a| a[:alias] }
  taken = all_names(link_rows, alias_rows) - own_old_names

  error = validate_name(new_name, taken)
  error ||= 'Destination URL is required.' if url.empty?
  error ||= alias_names.map { |a| validate_name(a, taken) }.compact.first
  error ||= "An alias can't be the same as the link's name." if alias_names.include?(new_name)
  error ||= 'Aliases must be unique.' if alias_names.uniq.length != alias_names.length

  if error
    return erb :link_form, locals: {
      heading: 'Edit link', action: "/#{Rack::Utils.escape_path(original_name)}/edit",
      original_name: original_name, name: new_name, url: url, search_url: search_url,
      aliases: raw_aliases, error: error
    }
  end

  entry[:name] = new_name
  entry[:url] = url
  entry[:search_url] = search_url.empty? ? nil : search_url
  write_links(link_rows)

  # Replace this link's aliases wholesale with the submitted set, keyed under
  # its (possibly new) name — simpler than diffing, and correctly carries
  # aliases across a rename instead of leaving them dangling on the old name.
  alias_rows.reject! { |a| a[:link] == original_name }
  alias_names.each { |a| alias_rows << { link: new_name, alias: a } }
  write_aliases(alias_rows)

  redirect '/'
end

delete '/:name' do
  link_rows = read_links
  name = params['name']
  halt 404, "No link named “#{h(name)}”." unless link_rows.reject! { |r| r[:name] == name }

  write_links(link_rows)
  alias_rows = read_aliases
  alias_rows.reject! { |a| a[:link] == name }
  write_aliases(alias_rows)

  redirect '/'
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
    # One row per canonical link, plus its aliases (each row of aliases.csv is
    # one alias — a link can have any number). "go" is synthetic, not a CSV
    # row, so it's not editable and has no aliases of its own.
    aliases_by_link = read_aliases.group_by { |a| a[:link] }
    entries = [{ name: 'go', url: "http://localhost:#{PORT}", search_url: nil, editable: false }] +
              read_links.map { |r| r.merge(editable: true) }
    entries.each { |e| e[:aliases] = (aliases_by_link[e[:name]] || []).map { |a| a[:alias] }.sort }
    entries.sort_by! { |e| e[:name] }
    erb :index, locals: { entries: entries }
  end
end
