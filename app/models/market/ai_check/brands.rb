# frozen_string_literal: true

# The businesses an AI answer could name: the site's own (its business name,
# its name on Google Maps, its domain) and each competitor's (name, domain).
# Finds which an answer names and in what order, from its text and any
# business cards it showed; cards for businesses not watched count too.
class Market::AiCheck::Brands
  SUFFIXES = /\b(llc|inc|ltd|co|company|corp|corporation|pllc|pc|dds|the)\b/

  Brand = Data.define(:name, :domain, :competitor_id, :own, :patterns)

  def initialize(profile: Market::Profile.current, competitors: Market::Competitor.ordered.to_a)
    @own_domain = profile.domain
    @brands = [brand([profile.business_name, profile.maps_name], profile.domain, nil, true),
      *competitors.map { brand([it.name], it.domain, it.id, false) }].compact
  end

  def own_domain?(domain)
    domain = domain.to_s
    @own_domain.present? && (domain == @own_domain || domain.end_with?(".#{@own_domain}"))
  end

  # [{"name", "domain", "competitor_id", "own", "rank"}] in the order the answer names them.
  def named_in(text, businesses = [])
    plain = normalize(text)
    found = @brands.filter_map do |brand|
      at = brand.patterns.filter_map { plain.index(it) }.min
      [brand, at] if at
    end
    cards = Array(businesses).each_with_index.filter_map do |card, index|
      domain = Market::Probe.normalize(card["domain"].presence || card["url"])
      title = card["title"].to_s.strip
      next if title.empty? && domain.nil?

      brand = @brands.find { (domain && it.domain && (domain == it.domain || domain.end_with?(".#{it.domain}"))) || it.patterns.include?(normalize(title)) }
      [brand || Brand.new(name: title.presence || domain, domain: domain, competitor_id: nil, own: false, patterns: []), -1_000_000 + index]
    end
    (cards + found).sort_by(&:last).uniq { it.first.name.downcase }.each_with_index.map do |(brand, _), index|
      {"name" => brand.name, "domain" => brand.domain, "competitor_id" => brand.competitor_id, "own" => brand.own, "rank" => index + 1}.compact
    end
  end

  private

  def brand(names, domain, competitor_id, own)
    patterns = names.compact_blank.map { normalize(it) }.reject { it.strip.length < 3 }
    patterns << domain.to_s.downcase if domain.present?
    patterns << domain.to_s.split(".").first if domain.present? && domain.to_s.split(".").first.length >= 6
    patterns = patterns.compact_blank.uniq
    Brand.new(name: names.compact_blank.first || domain, domain: domain, competitor_id: competitor_id, own: own, patterns: patterns) if patterns.any?
  end

  def normalize(text)
    # Words and domains, a full stop kept only inside a domain ("acme.com", not "Acme.").
    " #{text.to_s.downcase.unicode_normalize(:nfkd).gsub(/[^a-z0-9.\s]/, " ").gsub(/\.(?![a-z0-9])/, " ").gsub(SUFFIXES, " ").squeeze(" ").strip} "
      .then { it.strip.empty? ? "" : it }
  end
end
