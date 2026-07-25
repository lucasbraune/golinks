# End-to-end tests for the golinks server: every example drives a real HTTP
# request through the routes. Run from the repo root with:
#   ruby test/server_test.rb
# GOLINKS_LINKS_FILE points the server at a fixed fixture so the assertions
# don't depend on the live data/links.csv. It must be set before server.rb is
# required, since it is read when the app loads.
ENV['GOLINKS_LINKS_FILE'] = File.expand_path('fixtures/links.csv', __dir__)

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
end
