# frozen_string_literal: true

json.partial! "market/api/competitors/competitor", competitor: @competitor
json.latest_reading_line market_reading_line(@readings.first)
json.readings @readings do |reading|
  json.partial! "market/api/competitors/reading", reading: reading
end
