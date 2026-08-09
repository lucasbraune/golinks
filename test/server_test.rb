# frozen_string_literal: true

# End-to-end tests for the golinks server: every example drives a real HTTP
# request through the routes. Run from the repo root with:
#   ruby test/server_test.rb
# GOLINKS_LINKS_FILE/GOLINKS_ALIASES_FILE point the server at fixed fixtures so
# the assertions don't depend on the live data/*.csv. Must be set before
# server.rb is required, since it reads them when the app loads.
require 'fileutils'
require 'tmpdir'

# The /links routes write to whatever those env vars point at, so point them at
# throwaway copies in a tmpdir rather than at test/fixtures/*.csv directly. The
# checked-in fixtures are then only ever read, which matters because a run that
# dies mid-example used to leave them mutated — and since the pristine contents
# were captured once at load, every later run "reset" to the mutated copy and
# failed in ways that looked nothing like the actual cause.
FIXTURE_SOURCE = File.expand_path('fixtures', __dir__)
FIXTURE_DIR = Dir.mktmpdir('golinks-test-')
# Registered before minitest/autorun's own at_exit, and at_exit runs last-in
# first-out, so the suite finishes before this removes the directory.
at_exit { FileUtils.remove_entry(FIXTURE_DIR, true) }

LINKS_FIXTURE_PATH = File.join(FIXTURE_DIR, 'links.csv')
ALIASES_FIXTURE_PATH = File.join(FIXTURE_DIR, 'aliases.csv')
ENV['GOLINKS_LINKS_FILE'] = LINKS_FIXTURE_PATH
ENV['GOLINKS_ALIASES_FILE'] = ALIASES_FIXTURE_PATH

# Read-and-write rather than FileUtils.cp: cp carries the source's permission
# bits across, so a read-only checked-in fixture would produce a read-only copy
# that neither the next reset nor the server could write.
def reset_fixtures!
  File.write(LINKS_FIXTURE_PATH, File.read(File.join(FIXTURE_SOURCE, 'links.csv')))
  File.write(ALIASES_FIXTURE_PATH, File.read(File.join(FIXTURE_SOURCE, 'aliases.csv')))
end

# Seed once up front so the files exist before anything can read them, not just
# before the first example.
reset_fixtures!

require_relative '../server'
require 'csv'
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

  # Re-copy before every example so tests stay order-independent (a no-op for
  # read-only examples) — the writes land in the tmpdir, never in the repo.
  before do
    reset_fixtures!
  end

  describe 'the link list' do
    it 'is shown at /links' do
      get '/links'
      assert_predicate last_response, :ok?
      assert_includes last_response.body, 'wiki'
      refute_predicate last_response, :redirect?
      assert_nil location
    end

    it 'redirects the root path to /links' do
      get '/'
      assert_equal 302, last_response.status
      assert_equal 'http://127.0.0.1/links', location
    end

    it 'redirects an unknown name to the list, with the query as a filter' do
      get '/definitely-not-a-real-link'
      assert_equal 302, last_response.status
      assert_equal 'http://127.0.0.1/links?q=definitely-not-a-real-link', location
    end

    it 'escapes a query with spaces and separators into ?q=' do
      get '/no%20such%20link%20&%20more'
      assert_equal 302, last_response.status
      assert_equal 'http://127.0.0.1/links?q=no+such+link+%26+more', location
    end

    it 'pre-fills the filter box from ?q=' do
      get '/links?q=dis'
      assert_predicate last_response, :ok?
      assert_match(/<input type="search" id="search" value="dis"/, last_response.body)
    end

    it 'embeds the entries as JSON for the client-side search filter' do
      get '/links'
      data = JSON.parse(last_response.body[%r{<script type="application/json" id="entries-data">(.*?)</script>}m, 1])
      assert_includes data.map { |entry| entry['name'] }, 'wiki'
    end

    # The theme has to be applied before the first paint, so this script must
    # stay blocking and in <head>. Marking it defer/async/module would still
    # "work" but would reintroduce a flash of the wrong theme on every load.
    ['/links', '/links/new'].each do |path|
      it "loads the theme script blocking in <head> on #{path}" do
        get path
        head = last_response.body[%r{<head>(.*?)</head>}m, 1]
        assert_includes head, '/theme.js'
        refute_match(/theme\.js[^>]*(?:defer|async|type=)/, head)
      end
    end
  end

  describe 'direct name lookup' do
    it 'redirects a known name to its url' do
      get '/wiki'
      assert_predicate last_response, :redirect?
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

    it "falls through to the list filter when the link can't search" do
      # "plain" resolves but has no search_url, so terms after its name can't
      # be turned into anything — same fallthrough as an unknown name.
      get '/plain%20whatever'
      assert_equal 302, last_response.status
      assert_equal 'http://127.0.0.1/links?q=plain+whatever', location
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
      get '/links'
      assert_includes last_response.body, 'chip-alias'
      assert_includes last_response.body, '>w<'
    end
  end

  describe 'managing links' do
    it 'creates a link and makes it live immediately' do
      post '/links/new', new_name: 'ddg', url: 'https://duckduckgo.com', search_url: 'https://duckduckgo.com/?q=%s'
      assert_equal 302, last_response.status
      assert_equal 'http://127.0.0.1/links', location

      get '/links'
      assert_includes last_response.body, 'ddg'

      get '/ddg'
      assert_equal 302, last_response.status
      assert_equal 'https://duckduckgo.com', location

      get '/ddg%20cats'
      assert_equal 'https://duckduckgo.com/?q=cats', location
    end

    it 'creates a link with aliases' do
      post '/links/new', new_name: 'ddg', url: 'https://duckduckgo.com', aliases: %w[dd duck]
      get '/dd'
      assert_equal 302, last_response.status
      assert_equal 'https://duckduckgo.com', location
      get '/duck'
      assert_equal 'https://duckduckgo.com', location
    end

    it 'ignores blank alias fields' do
      post '/links/new', new_name: 'ddg', url: 'https://duckduckgo.com', aliases: ['dd', '', '  ']
      rows = CSV.read(ALIASES_FIXTURE_PATH, headers: true)
      assert_equal(['dd'], rows.select { |r| r['link'] == 'ddg' }.map { |r| r['alias'] })
    end

    it 'treats a blank search_url as absent' do
      post '/links/new', new_name: 'ddg', url: 'https://duckduckgo.com', search_url: ''
      row = CSV.read(LINKS_FIXTURE_PATH, headers: true).find { |r| r['name'] == 'ddg' }
      assert_nil row['search_url']
    end

    it 'rejects a blank name' do
      post '/links/new', new_name: '', url: 'https://duckduckgo.com'
      assert_predicate last_response, :ok? # re-renders the form, not a redirect
      assert_includes last_response.body, 'required'

      get '/links'
      refute_includes last_response.body, 'duckduckgo'
    end

    it 'rejects a blank url' do
      post '/links/new', new_name: 'ddg', url: ''
      assert_includes last_response.body, 'required'
    end

    it 'rejects a duplicate name' do
      post '/links/new', new_name: 'wiki', url: 'https://example.com'
      assert_includes last_response.body, 'already exists'
    end

    it 'rejects a name that collides with an existing alias' do
      post '/links/new', new_name: 'w', url: 'https://example.com'
      assert_includes last_response.body, 'already exists'
    end

    it 'rejects an alias that collides with an existing name' do
      post '/links/new', new_name: 'ddg', url: 'https://duckduckgo.com', aliases: ['wiki']
      assert_includes last_response.body, 'already exists'
    end

    it "rejects an alias equal to the link's own name" do
      post '/links/new', new_name: 'ddg', url: 'https://duckduckgo.com', aliases: ['ddg']
      assert_includes last_response.body, 'be the same'
    end

    it 'rejects duplicate aliases within the same submission' do
      post '/links/new', new_name: 'ddg', url: 'https://duckduckgo.com', aliases: %w[dd dd]
      assert_includes last_response.body, 'unique'
    end

    it 'rejects the reserved name "links"' do
      post '/links/new', new_name: 'links', url: 'https://example.com'
      assert_includes last_response.body, 'reserved'
    end

    it 'rejects the reserved name "new"' do
      post '/links/new', new_name: 'new', url: 'https://example.com'
      assert_includes last_response.body, 'reserved'
    end

    it 'rejects a name starting with "links/"' do
      post '/links/new', new_name: 'links/foo', url: 'https://example.com'
      assert_includes last_response.body, 'reserved'
    end

    it 'rejects a name containing a space' do
      post '/links/new', new_name: 'bad name', url: 'https://example.com'
      assert_includes last_response.body, 'valid name'
    end

    it 'rejects an alias containing a space' do
      post '/links/new', new_name: 'ddg', url: 'https://duckduckgo.com', aliases: ['duck duck']
      assert_includes last_response.body, 'valid name'
    end

    it 'accepts a name with slashes, dots, dashes, and underscores' do
      post '/links/new', new_name: 'team/my_go-link.v2', url: 'https://example.com'
      assert_equal 302, last_response.status
      get '/team/my_go-link.v2'
      assert_equal 'https://example.com', location
    end

    it 'edits a link, changing its destination' do
      post '/links/wiki/edit', new_name: 'wiki', url: 'https://simple.wikipedia.org'
      assert_equal 302, last_response.status
      assert_equal 'http://127.0.0.1/links', location

      get '/wiki'
      assert_equal 'https://simple.wikipedia.org', location
    end

    it 'adds and removes aliases on an existing link' do
      post '/links/wiki/edit', new_name: 'wiki', url: 'https://www.wikipedia.org', aliases: %w[w encyclopedia]
      get '/encyclopedia'
      assert_equal 302, last_response.status

      post '/links/wiki/edit', new_name: 'wiki', url: 'https://www.wikipedia.org', aliases: ['w']
      get '/encyclopedia'
      assert_equal 'http://127.0.0.1/links?q=encyclopedia', location # no longer a known name
      get '/w'
      assert_equal 302, last_response.status
    end

    it 'renames a link; the old name stops working, the new one works, and its alias follows' do
      post '/links/wiki/edit', new_name: 'wp', url: 'https://www.wikipedia.org', aliases: ['w']
      get '/wiki'
      assert_equal 'http://127.0.0.1/links?q=wiki', location # old name no longer resolves
      get '/wp'
      assert_equal 302, last_response.status
      assert_equal 'https://www.wikipedia.org', location
      get '/w'
      assert_equal 302, last_response.status
      assert_equal 'https://www.wikipedia.org', location
    end

    it 'rejects renaming a link onto an existing name' do
      post '/links/wiki/edit', new_name: 'a/b', url: 'https://www.wikipedia.org'
      assert_includes last_response.body, 'already exists'
    end

    it 'lets a link keep its own existing alias when re-saved unchanged' do
      post '/links/wiki/edit', new_name: 'wiki', url: 'https://www.wikipedia.org', aliases: ['w']
      refute_includes last_response.body, 'already exists'
      assert_equal 302, last_response.status
    end

    it '404s editing a name that does not exist' do
      get '/links/does-not-exist/edit'
      assert_equal 404, last_response.status
    end

    it '404s posting an edit for a name that does not exist' do
      post '/links/does-not-exist/edit', new_name: 'does-not-exist', url: 'https://example.com'
      assert_equal 404, last_response.status
    end

    it 'deletes a link and its aliases' do
      post '/links/wiki/delete'
      assert_equal 302, last_response.status
      assert_equal 'http://127.0.0.1/links', location

      get '/wiki'
      assert_equal 'http://127.0.0.1/links?q=wiki', location # not found; query becomes a filter
      get '/w'
      assert_equal 'http://127.0.0.1/links?q=w', location # its alias stops working too

      get '/links'
      refute_includes last_response.body, '>wiki<'
    end

    it '404s deleting a name that does not exist' do
      post '/links/does-not-exist/delete'
      assert_equal 404, last_response.status
    end

    # The per-link management routes use a splat (*name), not :name, so
    # slash-named links are editable too — :name would stop at the "/".
    describe 'a slash-named link' do
      it 'shows its edit form' do
        get '/links/a/b/edit'
        assert_predicate last_response, :ok?
        assert_includes last_response.body, 'a/b'
      end

      it 'can be edited' do
        post '/links/a/b/edit', new_name: 'a/b', url: 'https://example.com/changed'
        assert_equal 302, last_response.status
        get '/a/b'
        assert_equal 'https://example.com/changed', location
      end

      it 'can be deleted' do
        post '/links/a/b/delete'
        assert_equal 302, last_response.status
        get '/a/b'
        assert_equal 'http://127.0.0.1/links?q=a%2Fb', location # gone; query becomes a filter
      end
    end
  end
end
