# End-to-end tests for the golinks server: every example drives a real HTTP
# request through the routes. Run from the repo root with:
#   ruby test/server_test.rb
# GOLINKS_LINKS_FILE/GOLINKS_ALIASES_FILE point the server at fixed fixtures so
# the assertions don't depend on the live data/*.csv. Must be set before
# server.rb is required, since it reads them when the app loads.
ENV['GOLINKS_LINKS_FILE'] = File.expand_path('fixtures/links.csv', __dir__)
ENV['GOLINKS_ALIASES_FILE'] = File.expand_path('fixtures/aliases.csv', __dir__)
LINKS_FIXTURE_PATH = ENV['GOLINKS_LINKS_FILE']
ALIASES_FIXTURE_PATH = ENV['GOLINKS_ALIASES_FILE']
ORIGINAL_LINKS_FIXTURE = File.read(LINKS_FIXTURE_PATH)
ORIGINAL_ALIASES_FIXTURE = File.read(ALIASES_FIXTURE_PATH)

require_relative '../server'
require 'minitest/autorun'
require 'rack/test'

describe 'golinks server' do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  # Rack::Test defaults to the host "example.org", which Sinatra's host
  # authorization rejects with 403; use a permitted loopback host.
  def default_host
    '127.0.0.1'
  end

  def location
    last_response.headers['Location']
  end

  # The /links routes write the fixture CSVs; restore them after every
  # example so tests stay order-independent (a no-op for read-only examples).
  after do
    File.write(LINKS_FIXTURE_PATH, ORIGINAL_LINKS_FIXTURE)
    File.write(ALIASES_FIXTURE_PATH, ORIGINAL_ALIASES_FIXTURE)
  end

  describe 'the link list' do
    it 'is shown at the root path' do
      get '/'
      assert last_response.ok?
      assert_includes last_response.body, 'wiki'
      refute last_response.redirect?
      assert_nil location
    end

    it 'is shown for an unknown name' do
      get '/definitely-not-a-real-link'
      assert last_response.ok?
      assert_nil location
    end
  end

  describe 'direct name lookup' do
    it 'redirects a known name to its url' do
      get '/wiki'
      assert last_response.redirect?
      assert_equal 302, last_response.status
      assert_equal 'https://www.wikipedia.org', location
    end

    it 'matches a name that contains a slash' do
      get '/a/b'
      assert_equal 302, last_response.status
      assert_equal 'https://example.com/a/b', location
    end

    it 'ignores trailing spaces' do
      get '/wiki%20%20%20'
      assert_equal 302, last_response.status
      assert_equal 'https://www.wikipedia.org', location
    end
  end

  describe 'search terms' do
    it 'fills the search url from %20-encoded spaces' do
      get '/wiki%20rory%20sutherland'
      assert_equal 302, last_response.status
      assert_equal 'https://en.wikipedia.org/w/index.php?search=rory+sutherland', location
    end

    it 'treats "+" in the path as a space, as Chrome encodes its keyword' do
      get '/wiki+rory+sutherland'
      assert_equal 302, last_response.status
      assert_equal 'https://en.wikipedia.org/w/index.php?search=rory+sutherland', location
    end

    it 'combines a slashed name with slashed and spaced terms' do
      # "go/a/b c and d/e" -> name "a/b", search terms "c and d/e".
      get '/a/b%20c%20and%20d/e'
      assert_equal 302, last_response.status
      assert_equal 'https://example.com/a/b?q=c+and+d%2Fe', location
    end

    it 'falls through to the list when the name has no search url' do
      get '/plain%20whatever'
      assert last_response.ok?
      refute last_response.redirect?
      assert_nil location
    end
  end

  describe 'aliases' do
    it 'resolves an alias exactly like its link' do
      get '/w'
      assert_equal 302, last_response.status
      assert_equal 'https://www.wikipedia.org', location
    end

    it 'fills the search url through an alias too' do
      get '/w%20rory%20sutherland'
      assert_equal 'https://en.wikipedia.org/w/index.php?search=rory+sutherland', location
    end

    it 'lists an alias next to its link on the main page' do
      get '/'
      assert_includes last_response.body, 'chip-alias'
      assert_includes last_response.body, '>w<'
    end
  end

  describe 'managing links' do
    it 'creates a link and makes it live immediately' do
      post '/new', name: 'ddg', url: 'https://duckduckgo.com', search_url: 'https://duckduckgo.com/?q=%s'
      assert_equal 302, last_response.status
      assert_equal 'http://127.0.0.1/', location

      get '/'
      assert_includes last_response.body, 'ddg'

      get '/ddg'
      assert_equal 302, last_response.status
      assert_equal 'https://duckduckgo.com', location

      get '/ddg%20cats'
      assert_equal 'https://duckduckgo.com/?q=cats', location
    end

    it 'creates a link with aliases' do
      post '/new', name: 'ddg', url: 'https://duckduckgo.com', aliases: ['dd', 'duck']
      get '/dd'
      assert_equal 302, last_response.status
      assert_equal 'https://duckduckgo.com', location
      get '/duck'
      assert_equal 'https://duckduckgo.com', location
    end

    it 'ignores blank alias fields' do
      post '/new', name: 'ddg', url: 'https://duckduckgo.com', aliases: ['dd', '', '  ']
      rows = CSV.read(ALIASES_FIXTURE_PATH, headers: true)
      assert_equal ['dd'], rows.select { |r| r['link'] == 'ddg' }.map { |r| r['alias'] }
    end

    it 'treats a blank search_url as absent' do
      post '/new', name: 'ddg', url: 'https://duckduckgo.com', search_url: ''
      row = CSV.read(LINKS_FIXTURE_PATH, headers: true).find { |r| r['name'] == 'ddg' }
      assert_nil row['search_url']
    end

    it 'rejects a blank name' do
      post '/new', name: '', url: 'https://duckduckgo.com'
      assert last_response.ok? # re-renders the form, not a redirect
      assert_includes last_response.body, 'required'

      get '/'
      refute_includes last_response.body, 'duckduckgo'
    end

    it 'rejects a blank url' do
      post '/new', name: 'ddg', url: ''
      assert_includes last_response.body, 'required'
    end

    it 'rejects a duplicate name' do
      post '/new', name: 'wiki', url: 'https://example.com'
      assert_includes last_response.body, 'already exists'
    end

    it 'rejects a name that collides with an existing alias' do
      post '/new', name: 'w', url: 'https://example.com'
      assert_includes last_response.body, 'already exists'
    end

    it 'rejects an alias that collides with an existing name' do
      post '/new', name: 'ddg', url: 'https://duckduckgo.com', aliases: ['wiki']
      assert_includes last_response.body, 'already exists'
    end

    it "rejects an alias equal to the link's own name" do
      post '/new', name: 'ddg', url: 'https://duckduckgo.com', aliases: ['ddg']
      assert_includes last_response.body, 'be the same'
    end

    it 'rejects duplicate aliases within the same submission' do
      post '/new', name: 'ddg', url: 'https://duckduckgo.com', aliases: ['dd', 'dd']
      assert_includes last_response.body, 'unique'
    end

    it 'rejects the reserved name "go"' do
      post '/new', name: 'go', url: 'https://example.com'
      assert_includes last_response.body, 'reserved'
    end

    it 'rejects the reserved name "new"' do
      post '/new', name: 'new', url: 'https://example.com'
      assert_includes last_response.body, 'reserved'
    end

    it 'rejects a name ending in "/edit"' do
      post '/new', name: 'foo/edit', url: 'https://example.com'
      assert_includes last_response.body, 'end in “/edit”'
    end

    it 'edits a link, changing its destination' do
      post '/wiki/edit', new_name: 'wiki', url: 'https://simple.wikipedia.org'
      assert_equal 302, last_response.status
      assert_equal 'http://127.0.0.1/', location

      get '/wiki'
      assert_equal 'https://simple.wikipedia.org', location
    end

    it 'adds and removes aliases on an existing link' do
      post '/wiki/edit', new_name: 'wiki', url: 'https://www.wikipedia.org', aliases: ['w', 'encyclopedia']
      get '/encyclopedia'
      assert_equal 302, last_response.status

      post '/wiki/edit', new_name: 'wiki', url: 'https://www.wikipedia.org', aliases: ['w']
      get '/encyclopedia'
      refute_equal 302, last_response.status
      get '/w'
      assert_equal 302, last_response.status
    end

    it 'renames a link; the old name stops working, the new one works, and its alias follows' do
      post '/wiki/edit', new_name: 'wp', url: 'https://www.wikipedia.org', aliases: ['w']
      get '/wiki'
      refute_equal 302, last_response.status
      get '/wp'
      assert_equal 302, last_response.status
      assert_equal 'https://www.wikipedia.org', location
      get '/w'
      assert_equal 302, last_response.status
      assert_equal 'https://www.wikipedia.org', location
    end

    it 'rejects renaming a link onto an existing name' do
      post '/wiki/edit', new_name: 'a/b', url: 'https://www.wikipedia.org'
      assert_includes last_response.body, 'already exists'
    end

    it 'lets a link keep its own existing alias when re-saved unchanged' do
      post '/wiki/edit', new_name: 'wiki', url: 'https://www.wikipedia.org', aliases: ['w']
      refute_includes last_response.body, 'already exists'
      assert_equal 302, last_response.status
    end

    it '404s editing a name that does not exist' do
      get '/does-not-exist/edit'
      assert_equal 404, last_response.status
    end

    it 'deletes a link and its aliases' do
      delete '/wiki'
      assert_equal 302, last_response.status
      assert_equal 'http://127.0.0.1/', location

      get '/wiki'
      refute_equal 302, last_response.status # falls through to the list, not found
      get '/w'
      refute_equal 302, last_response.status # its alias stops working too

      get '/'
      refute_includes last_response.body, '>wiki<'
    end

    it '404s deleting a name that does not exist' do
      delete '/does-not-exist'
      assert_equal 404, last_response.status
    end
  end
end
