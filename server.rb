ENV['BUNDLE_GEMFILE'] ||= File.expand_path('Gemfile', __dir__)
require 'bundler/setup'
require 'sinatra'
require 'csv'

PORT = ENV.fetch('PORT', 51242).to_i
set :bind, '127.0.0.1'
set :port, PORT

LINKS_FILE = File.expand_path('data/links.csv', __dir__)

# Reload on every request so edits to the CSV apply without a restart.
# Each entry is { url:, search_url: }; search_url is an optional template
# containing "%s", used when the query is "<name> <search terms>".
def links
  rows = CSV.read(LINKS_FILE, headers: true).map do |row|
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

  def go(query)
    current_links = links
    target = redirect_target(query, current_links)
    if target
      redirect target, 302
    else
      grouped = current_links.group_by { |_name, entry| entry[:url] }
      erb :index, locals: { grouped: grouped, links_file: LINKS_FILE }
    end
  end
end

get '/' do
  go params['query']
end
