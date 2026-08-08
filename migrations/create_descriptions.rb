# frozen_string_literal: true

# One-off backfill: give every stored link a description.
#
#   bundle exec ruby migrations/create_descriptions.rb
#
# Safe to re-run. Links that already have a description are left alone, so a
# rerun only fills in whatever failed last time (a site that was down, an API
# error) and never overwrites something written by hand.

require 'bundler/setup'
require 'dotenv/load'
require_relative '../lib/link_repository'
require_relative '../lib/description_generator'

LINKS_FILE = File.expand_path(ENV.fetch('GOLINKS_LINKS_FILE', '../data/links.csv'), __dir__)
ALIASES_FILE = File.expand_path(ENV.fetch('GOLINKS_ALIASES_FILE', '../data/aliases.csv'), __dir__)
PORT = ENV.fetch('PORT', 51_242).to_i

repository = GoLinks::LinkRepository.new(
  links_file: LINKS_FILE, aliases_file: ALIASES_FILE, port: PORT
)
generator = GoLinks::DescriptionGenerator.new

def described?(link)
  !link.description.to_s.strip.empty?
end

links = repository.get_links
puts "#{links.size} links in #{LINKS_FILE}"

filled = skipped = failed = 0

links.each do |link|
  if described?(link)
    puts "  skip   #{link.name.ljust(18)} already described"
    skipped += 1
    next
  end

  # The canonical "links" self-link is built by the repository itself and its
  # name is reserved, so create_link refuses to save it (see
  # RESERVED_NAME_PATTERNS). Nothing to do here.
  if link.name == 'links'
    puts "  skip   #{link.name.ljust(18)} repository-managed self-link"
    skipped += 1
    next
  end

  result = generator.describe_link(link.url)
  unless result.success?
    puts "  FAIL   #{link.name.ljust(18)} #{result.message}"
    failed += 1
    next
  end

  # One save per link rather than one at the end: a run interrupted halfway
  # keeps the descriptions it already paid for.
  repository.create_link(link.with(description: result.message), replacing: link.name)
  puts "  ok     #{link.name.ljust(18)} #{result.message}"
  filled += 1
end

puts
puts "filled #{filled}, skipped #{skipped}, failed #{failed}"
