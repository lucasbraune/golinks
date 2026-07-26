# frozen_string_literal: true

module GoLinks
  module ApiHelpers
    # Builds a Link from a submitted add/edit form. Raises ArgumentError with a
    # user-facing message if the submission is structurally invalid (see
    # Link.new in lib/link.rb) — callers rescue that alongside
    # LinkRepository::InvalidNameError to re-render the form with the error.
    def self.link_from_params(params)
      search_url = params['search_url'].to_s.strip
      Link.new(
        name: params['new_name'].to_s.strip,
        url: params['url'].to_s.strip,
        search_url: search_url.empty? ? nil : search_url,
        aliases: Array(params['aliases']).map(&:strip).reject(&:empty?)
      )
    end

    # Locals for re-rendering the add/edit form after a failed submission. Echoes
    # back exactly what was submitted, blanks included, so the user doesn't lose
    # their place.
    def self.link_form_locals(params, heading:, action:, original_name:, error:)
      {
        heading: heading, action: action, original_name: original_name, error: error,
        name: params['new_name'].to_s.strip, url: params['url'].to_s.strip,
        search_url: params['search_url'].to_s.strip, aliases: Array(params['aliases'])
      }
    end

    # Returns the URL to redirect to for a query, or nil to fall through to the
    # list. Everything up to the first space is the link name and the rest is the
    # optional search terms — unambiguous because Link::NAME_PATTERN forbids
    # spaces in names (slashes are fine; the split is on spaces only).
    def self.redirect_target(query, links)
      query = query.to_s.strip
      return nil if query.empty?

      name, terms = query.split(' ', 2)

      link = links.find { |l| l.name == name || l.aliases.include?(name) }
      return nil unless link
      return link.url if terms.nil? || terms.strip.empty?
      return nil unless link.search_url # terms given, but this link can't search

      link.search_url.sub('%s') { Rack::Utils.escape(terms.strip) }
    end
  end
end
