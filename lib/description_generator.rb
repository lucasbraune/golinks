# frozen_string_literal: true

require 'anthropic'
require 'json'
require 'metainspector'

module GoLinks
  # Generates a short human-readable description for a URL: fetches the page's
  # metadata, then asks Claude to turn it into a phrase suitable for the links
  # list. Network-bound and best-effort — every failure comes back as a
  # "failure" result rather than an exception, so a caller looping over many
  # links is never aborted by one bad URL.
  class DescriptionGenerator
    Result = Data.define(:status, :message) do
      def success? = status == 'success'
    end

    MODEL = 'claude-haiku-4-5-20251001'
    MAX_TOKENS = 200
    SYSTEM_PROMPT = "Generate a short phrase (up to 7 words) to describe the user's URL. Include the name of " \
                    'the business. Add more information if the name is not self-explanatory. In particular, ' \
                    'include a description of user content if the URL points to user content.'
    # A raw JSON Schema rather than an Anthropic::BaseModel: the model class route
    # gives a typed parsed_output but cannot express the status enum.
    RESPONSE_SCHEMA = {
      type: 'object',
      additionalProperties: false,
      properties: {
        status: { type: 'string', enum: %w[success failure] },
        message: { type: 'string' }
      },
      required: %w[status message]
    }.freeze

    FETCH_TIMEOUT = 15
    FETCH_RETRIES = 1
    # Without this, Google and YouTube serve German and YouTube's metadata comes back
    # localized. Deliberately not overriding User-Agent: MetaInspector's default is
    # what currently gets past the Cloudflare challenges on claude.ai and economist.com,
    # and a browser UA re-triggers them.
    FETCH_HEADERS = { 'Accept-Language' => 'en-US,en;q=0.9' }.freeze

    # client is injectable so tests can pass a stub instead of reaching the API.
    def initialize(client: nil)
      @client = client
    end

    def describe_link(url)
      message = client.messages.create(
        model: MODEL,
        max_tokens: MAX_TOKENS,
        # system_ has a trailing underscore in the Ruby SDK so it doesn't shadow Kernel#system.
        system_: SYSTEM_PROMPT,
        messages: [{ role: 'user', content: page_metadata(url) }],
        output_config: { format: { type: 'json_schema', schema: RESPONSE_SCHEMA } }
      )

      parsed = JSON.parse(message.content[0].text)
      Result.new(status: parsed['status'], message: parsed['message'])
    rescue StandardError => e
      # A fetch failure or an API error would otherwise abort a whole batch run,
      # so report it in the schema's own shape instead.
      Result.new(status: 'failure', message: "#{e.class}: #{e.message}")
    end

    private

    # Built lazily and reused, so a missing ANTHROPIC_API_KEY surfaces per call
    # (where describe_link's rescue catches it) rather than at load time.
    def client
      @client ||= Anthropic::Client.new
    end

    # Title and description only. Body text was tried and dropped: extracting it
    # well needs bespoke handling per site (SPAs return nothing, readability-style
    # extractors pick up donation banners and legal footers), while title plus
    # meta description is enough for a 7-word phrase.
    def page_metadata(url)
      page = MetaInspector.new(url.strip, timeout: FETCH_TIMEOUT, retries: FETCH_RETRIES,
                                          headers: FETCH_HEADERS, allow_non_html_content: false)
      JSON.pretty_generate(
        url: url.strip,
        final_url: page.url,
        title: page.best_title,
        description: page.best_description
      )
    end
  end
end
