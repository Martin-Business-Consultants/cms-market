# frozen_string_literal: true

require "net/http"

# Where a ZIP or postcode is: its centre's latitude and longitude, from
# OpenStreetMap's Nominatim (free, one request at a time, a named agent).
# Used once when the profile's ZIP changes, never per search.
module Market::Geocoder
  class Error < StandardError; end

  ENDPOINT = "https://nominatim.openstreetmap.org/search"

  def self.locate(zip, country: "us", transport: method(:fetch))
    query = URI.encode_www_form(postalcode: zip, countrycodes: country.to_s.downcase, format: "json", limit: 1)
    status, body = transport.call("#{ENDPOINT}?#{query}")
    raise Error, "Couldn't look up #{zip}: OpenStreetMap answered #{status}" unless status.to_i == 200

    place = Array(JSON.parse(body.to_s)).first or raise Error, "No place found for #{zip} in #{country.to_s.upcase}"
    {lat: place["lat"].to_f.round(7), lng: place["lon"].to_f.round(7), place: place["display_name"].to_s.truncate(200)}
  rescue JSON::ParserError
    raise Error, "Couldn't look up #{zip}: OpenStreetMap's answer wasn't readable"
  end

  def self.fetch(url)
    uri = URI(url)
    request = Net::HTTP::Get.new(uri, "User-Agent" => "Libre Publish market (#{Site.host})", "Accept" => "application/json")
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 8, read_timeout: 15) do |http|
      response = http.request(request)
      [response.code.to_i, response.body]
    end
  rescue Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError => error
    raise Error, "Couldn't reach OpenStreetMap to look up the ZIP: #{error.class.name.demodulize}"
  end
end
