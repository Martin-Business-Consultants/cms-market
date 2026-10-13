# frozen_string_literal: true

# A square map of the business's area, drawn from standard web map tiles
# (OpenStreetMap's, as plain images: no script), with anything placed on it
# by latitude and longitude. Everything is in percent of the square, so it
# scales with the column it sits in. Web Mercator, 256-pixel tiles.
class Market::SlippyMap
  TILE = 256
  SIZE = 768
  TILES = "https://tile.openstreetmap.org/%<z>d/%<x>d/%<y>d.png"
  ATTRIBUTION = "© OpenStreetMap contributors"
  ATTRIBUTION_URL = "https://www.openstreetmap.org/copyright"
  EARTH = 156_543.03392 # metres per pixel at the equator, zoom 0

  Tile = Data.define(:url, :left, :top, :size)

  attr_reader :zoom

  # Fits a circle of `radius_miles` round `center` ([lat, lng]) with a little room.
  def initialize(center:, radius_miles:)
    @lat, @lng = center
    diameter = radius_miles.to_f * 1609.344 * 2 * 1.3
    @zoom = Math.log2(EARTH * Math.cos(@lat * Math::PI / 180) * SIZE / [diameter, 200].max).floor.clamp(3, 17)
    @center_x, @center_y = pixel(@lat, @lng)
    @left = @center_x - SIZE / 2.0
    @top = @center_y - SIZE / 2.0
  end

  # The tiles covering the square, each placed in percent.
  def tiles
    count = 2**@zoom
    (floor(@left)..floor(@left + SIZE - 1)).flat_map do |x|
      (floor(@top)..floor(@top + SIZE - 1)).filter_map do |y|
        next if y.negative? || y >= count

        Tile.new(url: format(TILES, z: @zoom, x: x % count, y: y), left: percent(x * TILE - @left), top: percent(y * TILE - @top), size: percent(TILE))
      end
    end
  end

  # Where a point sits, [left %, top %].
  def position(lat, lng)
    x, y = pixel(lat.to_f, lng.to_f)
    [percent(x - @left), percent(y - @top)]
  end

  # How wide a distance is on the map, in percent.
  def span(miles) = percent(miles.to_f * 1609.344 / metres_per_pixel)

  private

  def metres_per_pixel = EARTH * Math.cos(@lat * Math::PI / 180) / 2**@zoom

  def pixel(lat, lng)
    scale = TILE * 2**@zoom
    sin = Math.sin(lat.clamp(-85.05, 85.05) * Math::PI / 180)
    [(lng + 180) / 360.0 * scale, (0.5 - Math.log((1 + sin) / (1 - sin)) / (4 * Math::PI)) * scale]
  end

  def floor(pixels) = (pixels / TILE).floor
  def percent(pixels) = (pixels * 100.0 / SIZE).round(3)
end
