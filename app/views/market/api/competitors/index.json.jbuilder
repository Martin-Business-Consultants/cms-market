# frozen_string_literal: true

json.summary "#{@competitors.size} #{"competitor".pluralize(@competitors.size)}"
json.own_website do
  @own ? json.partial!("market/api/competitors/reading", reading: @own) : json.nil!
end
json.competitors @competitors do |competitor|
  json.partial! "market/api/competitors/competitor", competitor: competitor
  reading = @readings[competitor.id]
  json.latest_reading_line market_reading_line(reading)
  json.tools market_tool_labels(reading)
  json.latest_reading do
    reading ? json.partial!("market/api/competitors/reading", reading: reading) : json.nil!
  end
end
