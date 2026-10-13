# frozen_string_literal: true

# The business this site is for, as its market sees it: its industry, where
# and whom it serves, what it sells, how it wants to be seen, what it's after,
# and where its customers search from (a DataForSEO location, for the
# searches tracked). Kept in the core's Setting "market", under "profile";
# its website is the site's own (Settings › General).
class Market::Profile
  FIELDS = %w[industry naics_code service_area offerings audience positioning goals notes search_location].freeze
  LABELS = {"industry" => "Industry", "naics_code" => "NAICS code", "service_area" => "Where it serves", "offerings" => "What it sells",
            "audience" => "Who it serves", "positioning" => "How it wants to be seen", "goals" => "What it's after",
            "notes" => "Notes", "search_location" => "Where its customers search from"}.freeze
  NEEDED = {"industry" => "industry", "service_area" => "service area", "offerings" => "what it sells",
            "audience" => "who it serves", "goals" => "goals"}.freeze

  def self.current = new(Setting.get(Market::Settings::KEY)["profile"])

  def initialize(data)
    @data = data.to_h.stringify_keys.slice(*FIELDS)
  end

  FIELDS.each { |field| define_method(field) { @data[field].presence } }

  def business_name
    Setting.get("general")["title"].presence || Site.host
  end

  def website = Site.public_base_url
  def domain = Market::Probe.normalize(website)

  def gaps = NEEDED.reject { |field, _| @data[field].present? }.values + (domain ? [] : ["the site's address (Settings › General)"])

  def self.update(params)
    params = params.to_h.stringify_keys.slice(*FIELDS)
    params["search_location"] = params["search_location"].to_s.split(",").map(&:strip).compact_blank.join(",") if params.key?("search_location")
    params["naics_code"] = params["naics_code"].to_s.gsub(/\D/, "").first(6) if params.key?("naics_code")
    profile = current.to_h.merge(params.transform_values { it.to_s.strip.presence })
    Setting.set(Market::Settings::KEY, "profile" => profile)
    current
  end

  def to_h = FIELDS.index_with { @data[it].presence }
end
