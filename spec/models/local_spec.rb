# frozen_string_literal: true

require "rails_helper"
require_relative "../support/market_helpers"

RSpec.describe "Market local search" do
  before { site_address }

  it "finds a ZIP's centre once, when it changes, and says why when it can't" do
    transport = MarketHelpers::FakeTransport.new([200, JSON.generate([{"lat" => "42.9632040", "lon" => "-85.6528489", "display_name" => "49503, Grand Rapids, Michigan"}])])
    expect(Market::Geocoder.locate("49503", transport: transport)).to eq(lat: 42.963204, lng: -85.6528489, place: "49503, Grand Rapids, Michigan")
    expect(transport.calls.first.first).to include("postalcode=49503", "countrycodes=us")
    expect { Market::Geocoder.locate("00000", transport: MarketHelpers::FakeTransport.new([200, "[]"])) }.to raise_error(Market::Geocoder::Error, /No place found for 00000/)

    profile = Market::Profile.update({"local_zip" => " 49503 ", "local_radius_miles" => "5", "local_grid" => "3", "maps_name" => "Acme Plumbing GR"}, MarketHelpers::FakeGeocoder)
    expect(profile).to have_attributes(local_zip: "49503", local_radius_miles: 5.0, local_grid: 3, maps_name: "Acme Plumbing GR", local_center: [42.9632, -85.6528])
    expect(profile).to be_local

    failing = Module.new { def self.locate(*, **) = raise(Market::Geocoder::Error, "Couldn't look up 99999") }
    expect(Market::Profile.update({"local_zip" => "99999"}, failing)).to have_attributes(local?: false, local_error: "Couldn't look up 99999")
  end

  it "lays a grid across the radius, north to south, west to east" do
    points = Market::LocalGrid.points([42.0, -85.0], radius_miles: 10, size: 3)

    expect(points.size).to eq(9)
    expect(points[4]).to have_attributes(row: 1, col: 1, lat: 42.0, lng: -85.0)
    expect(points.first.lat).to be_within(0.001).of(42.0 + 10 / 69.0)
    expect(points.first.lng).to be < -85.0
    expect(points.last.lat).to be < 42.0
    expect(Market::LocalGrid.zoom(10)).to eq(13)
  end

  describe "a pull with a ZIP" do
    let!(:rival) { Market::Competitor.create!(name: "Rival", website: "https://rival.example") }

    before do
      connect_search
      Market::Profile.update({"local_zip" => "49503", "local_radius_miles" => "10", "local_grid" => "3"}, MarketHelpers::FakeGeocoder)
      Market::Keyword.track("plumber")
    end

    # North of the centre the site is first; across the middle row it's sixth; to the south it isn't on the map.
    def maps(_keyword, lat, _lng)
      if lat > 42.97 then [{"position" => 1, "title" => "Acme Plumbing", "domain" => "acme.example"}, {"position" => 2, "title" => "Rival", "domain" => "rival.example"}]
      elsif lat > 42.95 then [{"position" => 1, "title" => "Rival", "domain" => "rival.example"}, {"position" => 6, "title" => "Acme Plumbing", "domain" => "www.acme.example"}]
      else [{"position" => 1, "title" => "Rival", "domain" => "rival.example"}, {"position" => 2, "title" => "Drain Kings"}]
      end
    end

    it "searches from the ZIP and checks each search on Maps from every point of the grid, queued, and makes the scan when every point is in" do
      fake = MarketHelpers::FakeApi.new(maps: method(:maps))
      Market::SearchPull.create!.run!(api: fake)

      expect(fake.calls).to include("queue:maps_point:9", "queue:ranking:1")
      expect(Market::LocalScan.count).to eq(0)
      expect(Market::QueuedTask.fetch_ready!(api: fake)).to eq(0)
      expect(fake.calls.count { it == "queued_result:maps_point" }).to eq(9)
      expect(Market::Ranking.last.location).to eq("49503 (42.9632,-85.6528)")
      scan = Market::LocalScan.last
      expect(scan).to have_attributes(zip: "49503", grid: 3, found_points: 6, top3_share: 0.33, average_position: ((3 * 1 + 3 * 6 + 3 * 21) / 9.0).round(1))
      expect(scan.rows.map { |row| row.map { it["position"] } }).to eq([[1, 1, 1], [6, 6, 6], [nil, nil, nil]])
      expect(scan.leaders.first).to eq("title" => "Rival", "domain" => "rival.example", "top3_points" => 9)

      finding = Market::Finding.find_by!(key: "local:#{Market::Keyword.first.id}")
      expect(finding).to have_attributes(kind: "local_weak", severity: "medium", channel: "local")
      expect(finding.title).to include("map top 3 for “plumber” at 3 of 9 points within 10 miles of 49503")
      expect(finding.evidence["weak_points"].size).to eq(6)
      expect(Market::SearchPull.ceiling).to be >= 9 * Market::Search::Api::CEILINGS[:maps]
    end

    it "says when the business isn't on the map anywhere in the area, checked live when not saving money" do
      Market::Settings.update("queue" => "0")
      fake = MarketHelpers::FakeApi.new(maps: ->(*) { [{"position" => 1, "title" => "Rival", "domain" => "rival.example"}] })
      Market::SearchPull.create!.run!(api: fake)

      expect(fake.calls.count { it == "maps:plumber" }).to eq(9)

      expect(Market::Finding.find_by!(kind: "local_missing").title).to eq("Acme Plumbing isn't on Google Maps for “plumber” anywhere within 10 miles of 49503")
    end
  end
end
