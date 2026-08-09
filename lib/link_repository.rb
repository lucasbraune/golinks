# frozen_string_literal: true

require 'csv'
require_relative 'link'

module GoLinks
  # Owns data/links.csv and data/aliases.csv, and the join between them. Every
  # method reads the files fresh and (for writes) rewrites them whole — fine for
  # one person editing their own links, not for concurrent writers.
  class LinkRepository
    # Raised by create_link when the incoming link's name or an alias is reserved
    # or already taken by another stored link. Validation that doesn't depend
    # on the repository's own naming policy or on what else is stored (blank
    # fields, alias shape) lives in Link.new instead — see lib/link.rb.
    class InvalidNameError < StandardError; end

    # Pinned rather than left to Encoding.default_external, which follows the
    # locale: launchd starts the agent with no LANG, so the default there is
    # US-ASCII and any non-ASCII description ("Cinema München") raises
    # CSV::InvalidEncodingError on the next read. "bom|" tolerates a byte-order
    # mark, which some editors add when saving the file by hand.
    READ_ENCODING = 'bom|utf-8'
    WRITE_ENCODING = 'utf-8'

    # A name matching any of these can never be saved as a link's name or
    # alias via create_link. "links" is also the name of the canonical self-link
    # (see ensure_self_link! below, which constructs it directly and so
    # bypasses this check), and "new" and the "links/*" namespace are reserved
    # so a stored link can never be confused with the /links/new and
    # /links/:name/* management routes in server.rb.
    RESERVED_NAME_PATTERNS = [/\Alinks\z/, /\Ago\z/, %r{\Alinks/}, /\Anew\z/].freeze

    def initialize(links_file:, aliases_file:, port:)
      @links_file = links_file
      @aliases_file = aliases_file
      @port = port
    end

    # All links, aliases attached, sorted by name.
    def get_links
      aliases_by_name = read_aliases_rows.group_by { |a| a[:link] }
      links = read_links_rows.map do |row|
        Link.new(
          name: row[:name], url: row[:url], search_url: row[:search_url],
          description: row[:description],
          aliases: (aliases_by_name[row[:name]] || []).map { |a| a[:alias] }.sort
        )
      end
      ensure_self_link!(links)
      links.sort_by(&:name)
    end

    def create_link(link, replacing: nil)
      candidates = [link.name] + link.aliases

      reserved = candidates.find { |name| RESERVED_NAME_PATTERNS.any? { |re| re.match?(name) } }
      raise InvalidNameError, "“#{reserved}” is a reserved name." if reserved

      links = get_links.reject { |l| l.name == replacing }
      taken = links.flat_map { |l| [l.name] + l.aliases }
      conflict = candidates.find { |name| taken.include?(name) }
      raise InvalidNameError, "“#{conflict}” already exists." if conflict

      links << link
      ensure_self_link!(links)
      write(links.sort_by(&:name))
      nil
    end

    def delete_link(name:)
      write(get_links.reject { |l| l.name == name }.sort_by(&:name))
      nil
    end

    private

    # The canonical "links" entry points back at this server's own list page,
    # so it shows up in the list like any other link. Only inserted on save
    # (not on every read) if something deleted it, so it reappears next time
    # anything is saved rather than needing special-casing everywhere.
    def ensure_self_link!(links)
      return if links.any? { |l| l.name == 'links' }

      links << Link.new(name: 'links', url: "http://localhost:#{@port}/links", aliases: ['go'])
    end

    def write(links)
      tmp = "#{@links_file}.tmp"
      CSV.open(tmp, 'w', encoding: WRITE_ENCODING) do |csv|
        csv << %w[name url search_url description]
        links.each { |l| csv << [l.name, l.url, l.search_url, l.description] }
      end
      File.rename(tmp, @links_file)

      tmp = "#{@aliases_file}.tmp"
      CSV.open(tmp, 'w', encoding: WRITE_ENCODING) do |csv|
        csv << %w[link alias]
        links.each { |l| l.aliases.each { |a| csv << [l.name, a] } }
      end
      File.rename(tmp, @aliases_file)
    end

    # A trailing blank line in the CSV parses as an all-nil row; drop it.
    # row['description'] is nil for a file written before the column existed,
    # which is the same as an empty description — no migration needed.
    def read_links_rows
      CSV.read(@links_file, headers: true, encoding: READ_ENCODING).reject { |row| row['name'].nil? }.map do |row|
        { name: row['name'], url: row['url'], search_url: row['search_url'],
          description: row['description'] }
      end
    end

    def read_aliases_rows
      CSV.read(@aliases_file, headers: true, encoding: READ_ENCODING).reject { |row| row['alias'].nil? }.map do |row|
        { link: row['link'], alias: row['alias'] }
      end
    end
  end
end
