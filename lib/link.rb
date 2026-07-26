Link = Data.define(:name, :url, :search_url, :aliases) do
  # The alphabet for names and aliases: slash-separated segments, each made of
  # letters, digits, ".", "_", and "-", starting with a letter or digit. This
  # forbids spaces (and "+", "?", "%", leading/trailing/double slashes), which
  # is what makes URL parsing unambiguous: in a decoded request path like
  # "yt rory sutherland", everything up to the first space must be the name
  # and the rest the search terms — see redirect_target in server.rb.
  NAME_PATTERN = %r{\A[a-z0-9][a-z0-9._-]*(?:/[a-z0-9][a-z0-9._-]*)*\z}i

  # Validates everything about a link that doesn't depend on what else is
  # stored or on any application-level naming policy (blank fields, the name
  # alphabet, alias shape). Reserved names and uniqueness against other
  # stored links are
  # LinkRepository#create_link's job instead: reserved names because the
  # canonical "links" self-link — itself a reserved name — is built by
  # constructing a Link directly (see ensure_self_link!), bypassing
  # create_link's checks; uniqueness because only the repository knows what
  # else exists.
  def initialize(name:, url:, search_url: nil, aliases: [])
    raise ArgumentError, 'Name is required.' if name.nil? || name.empty?
    raise ArgumentError, 'Destination URL is required.' if url.nil? || url.empty?
    raise ArgumentError, 'An alias name is required.' if aliases.any?(&:empty?)
    raise ArgumentError, "An alias can't be the same as the link's name." if aliases.include?(name)
    raise ArgumentError, 'Aliases must be unique.' if aliases.uniq.length != aliases.length

    invalid = ([name] + aliases).find { |n| !NAME_PATTERN.match?(n) }
    if invalid
      raise ArgumentError,
            "“#{invalid}” isn't a valid name — use letters, numbers, and . _ - / (no spaces)."
    end

    super
  end
end
