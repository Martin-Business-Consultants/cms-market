# frozen_string_literal: true

require "rails_helper"

RSpec.describe Market::SlippyMap do
  let(:map) { described_class.new(center: [42.9632, -85.6528], radius_miles: 10) }

  it "centres the area, fits the radius, and covers the square with tiles" do
    expect(map.position(42.9632, -85.6528)).to eq([50.0, 50.0])
    expect(map.span(20)).to be_between(60, 100)
    north, = map.position(42.9632 + 10 / 69.0, -85.6528).reverse
    expect(north).to be < 50
    expect(map.tiles).not_to be_empty
    expect(map.tiles.map(&:url)).to all(match(%r{\Ahttps://tile\.openstreetmap\.org/#{map.zoom}/\d+/\d+\.png\z}))
    expect(map.tiles.map(&:left).min).to be <= 0
    expect(map.tiles.map { it.left + it.size }.max).to be >= 100
  end
end
