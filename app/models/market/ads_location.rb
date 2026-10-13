# frozen_string_literal: true

# The Google Ads location the business's search volume is measured in: its
# city, found once in Google Ads' list of locations for the country (free)
# from the profile's search location ("Grand Rapids,Michigan,United States")
# or the place its ZIP was found at, and kept until the profile changes.
class Market::AdsLocation
  TYPES = ["City", "Municipality", "Neighborhood", "Postal Code"].freeze

  def initialize(profile: Market::Profile.current, settings: Market::Settings.current)
    @profile = profile
    @settings = settings
  end

  # The location name, or nil when it can't be found (the volume stays country-wide).
  def name(api)
    iso = Market::Search::Api::COUNTRY_CODES[@settings.country] or return
    key = [iso, @profile.search_location, @profile.local_place].join("|")
    cached = Setting.get(Market::Settings::KEY)["ads_location"].to_h
    return cached["name"] if cached["key"] == key && cached.key?("name")

    found = find(api.ads_locations(iso))
    Setting.set(Market::Settings::KEY, "ads_location" => {"key" => key, "name" => found})
    found
  end

  private

  # The first of the profile's places that's a city in the list, in the same region when it says one.
  def find(locations)
    words = [*@profile.search_location.to_s.split(","), *@profile.local_place.to_s.split(",")].map { it.strip }.compact_blank
    return if words.empty?

    cities = locations.select { it["location_type"].in?(TYPES) && it["location_type"] != "Postal Code" }
    words.each do |word|
      matches = cities.select { it["location_name"].to_s.split(",").first.to_s.casecmp?(word) }
      next if matches.empty?

      best = matches.find { |location| words.any? { location["location_name"].to_s.split(",")[1].to_s.strip.casecmp?(it) } } || matches.first
      return best["location_name"]
    end
    nil
  end
end
