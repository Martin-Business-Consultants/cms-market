# frozen_string_literal: true

# The points a local search is checked from: a square grid of size × size
# across a radius around a centre (rows north to south, columns west to
# east), and the Maps zoom that fits it.
module Market::LocalGrid
  MILES_PER_DEGREE = 69.0

  Point = Data.define(:row, :col, :lat, :lng)

  def self.points(center, radius_miles:, size:)
    lat, lng = center
    step = size > 1 ? radius_miles * 2.0 / (size - 1) : 0
    (0...size).flat_map do |row|
      (0...size).map do |col|
        north = radius_miles - row * step
        east = col * step - radius_miles
        Point.new(row: row, col: col, lat: (lat + north / MILES_PER_DEGREE).round(7),
          lng: (lng + east / (MILES_PER_DEGREE * Math.cos(lat * Math::PI / 180))).round(7))
      end
    end
  end

  # Google Maps' zoom for a search at a point: closer in for a small radius.
  def self.zoom(radius_miles)
    case radius_miles
    when ..2 then 15
    when ..5 then 14
    when ..10 then 13
    else 12
    end
  end
end
