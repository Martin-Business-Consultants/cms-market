# frozen_string_literal: true

# The business this site is for, as its market sees it: its industry, where
# and whom it serves, what it sells, how it wants to be seen, what it's after,
# and where its customers search from (a DataForSEO location, for the
# searches tracked). Kept in the core's Setting "market", under "profile";
# its website is the site's own (Settings › General).
class Market::Profile
  FIELDS = %w[industry naics_code service_area offerings audience positioning goals notes search_location].freeze
  # Local search: a ZIP (or postcode) and a radius in miles, checked as a grid of points across it.
  LOCAL_FIELDS = %w[local_zip local_country local_radius_miles local_grid maps_name].freeze
  # Who the business is: set at intake, else the site's own (Settings › General).
  IDENTITY_FIELDS = %w[business_name website].freeze
  RADII = [1, 2, 3, 5, 10, 15, 25].freeze
  GRIDS = [3, 5, 7].freeze
  LABELS = {"industry" => "Industry", "naics_code" => "NAICS code", "service_area" => "Where it serves", "offerings" => "What it sells",
            "audience" => "Who it serves", "positioning" => "How it wants to be seen", "goals" => "What it's after",
            "notes" => "Notes", "search_location" => "Where its customers search from",
            "maps_name" => "Name on Google Maps", "local_radius_miles" => "Radius", "business_name" => "Business name", "website" => "Website"}.freeze
  NEEDED = {"industry" => "industry", "service_area" => "service area", "offerings" => "what it sells",
            "audience" => "who it serves", "goals" => "goals"}.freeze

  def self.current = new(Setting.get(Market::Settings::KEY)["profile"])

  def initialize(data)
    @data = data.to_h.stringify_keys.slice(*FIELDS, *LOCAL_FIELDS, *IDENTITY_FIELDS, "local_lat", "local_lng", "local_place", "local_error", "ai_filled")
  end

  FIELDS.each { |field| define_method(field) { @data[field].presence } }

  def local_zip = @data["local_zip"].presence
  def local_country = (@data["local_country"].presence || "us").downcase
  def local_radius_miles = (@data["local_radius_miles"].presence || 10).to_f
  def local_grid = (@data["local_grid"].presence || 5).to_i.then { GRIDS.include?(it) ? it : 5 }
  # The name the business has on Google Maps, to find it among the results (its website finds it too).
  def maps_name = @data["maps_name"].presence || business_name
  def local_center = (@data["local_lat"] && @data["local_lng"]) ? [@data["local_lat"].to_f, @data["local_lng"].to_f] : nil
  def local_place = @data["local_place"].presence
  def local_error = @data["local_error"].presence
  def local? = local_center.present?

  def business_name = @data["business_name"].presence || Setting.get("general")["title"].presence || Site.host
  def website = @data["website"].presence || Site.public_base_url

  # The fields the AI filled at intake that no one has changed since: to check.
  def ai_filled = Array(@data["ai_filled"]) & @data.keys
  def domain = Market::Probe.normalize(website)

  # Most of what a plan needs is missing: time for the intake.
  def blank? = NEEDED.keys.count { @data[it].blank? } >= 3

  def gaps = NEEDED.reject { |field, _| @data[field].present? }.values + (domain ? [] : ["the site's address (Settings › General)"])

  # Saves what was sent; a new ZIP or country is located again (Market::Geocoder).
  def self.update(params, geocoder = Market::Geocoder)
    params = params.to_h.stringify_keys.slice(*FIELDS, *LOCAL_FIELDS, *IDENTITY_FIELDS)
    params["website"] = params["website"].to_s.strip.chomp("/").then { (it.empty? || it.match?(%r{\Ahttps?://}i)) ? it : "https://#{it}" } if params.key?("website")
    before = current
    params["search_location"] = params["search_location"].to_s.split(",").map(&:strip).compact_blank.join(",") if params.key?("search_location")
    params["naics_code"] = params["naics_code"].to_s.gsub(/\D/, "").first(6) if params.key?("naics_code")
    params["local_zip"] = params["local_zip"].to_s.strip.upcase.presence if params.key?("local_zip")
    params["local_radius_miles"] = params["local_radius_miles"].to_f.then { RADII.include?(it.to_i) ? it.to_i : 10 } if params["local_radius_miles"].present?
    params["local_grid"] = params["local_grid"].to_i.then { GRIDS.include?(it) ? it : 5 } if params["local_grid"].present?
    profile = before.stored.merge(params.transform_values { it.is_a?(String) ? it.strip.presence : it })
    # A field a person sets is theirs: no longer the AI's to check.
    profile["ai_filled"] = Array(profile["ai_filled"]) - params.select { |field, value| value.to_s.strip != before.stored[field].to_s }.keys if params.any?
    if profile["local_zip"] != before.local_zip || (profile["local_country"] || "us") != before.local_country
      profile.merge!(locate(profile["local_zip"], profile["local_country"] || "us", geocoder))
    end
    Setting.set(Market::Settings::KEY, "profile" => profile)
    current
  end

  def self.locate(zip, country, geocoder)
    return {"local_lat" => nil, "local_lng" => nil, "local_place" => nil, "local_error" => nil} if zip.blank?

    found = geocoder.locate(zip, country: country)
    {"local_lat" => found[:lat], "local_lng" => found[:lng], "local_place" => found[:place], "local_error" => nil}
  rescue Market::Geocoder::Error => error
    {"local_lat" => nil, "local_lng" => nil, "local_place" => nil, "local_error" => error.message}
  end

  def stored = @data.dup

  def to_h = FIELDS.index_with { @data[it].presence }

  # Filled in by the intake's AI: only the fields still empty, marked to check.
  def self.fill_in(values)
    stored = current.stored
    empty = values.to_h.stringify_keys.select { |field, value| value.present? && stored[field].blank? }
    Setting.set(Market::Settings::KEY, "profile" => stored.merge(empty).merge("ai_filled" => (Array(stored["ai_filled"]) | empty.keys)))
    empty.keys
  end

  def local_h
    {zip: local_zip, country: local_country, radius_miles: local_radius_miles, grid: local_grid, maps_name: maps_name,
     center: local_center && {lat: local_center[0], lng: local_center[1]}, place: local_place, error: local_error}
  end
end
