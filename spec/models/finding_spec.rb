# frozen_string_literal: true

require "rails_helper"
require_relative "../support/market_helpers"

RSpec.describe Market::Finding do
  let!(:rival) { Market::Competitor.create!(name: "Rival", website: "https://rival.example") }

  before do
    site_address
    Market::Profile.update("industry" => "Plumbing", "service_area" => "Springfield", "offerings" => "Drains", "audience" => "Homes", "goals" => "Calls")
    connect_search
  end

  def search(competitor, kind, data, at: Time.current)
    Market::SearchSnapshot.create!(competitor: competitor, domain: competitor&.domain || "acme.example", kind: kind, data: data, taken_at: at)
  end

  def keywords(*rows) = {"keywords" => rows.map { |keyword, position, volume| {"keyword" => keyword, "position" => position, "volume" => volume} }}

  it "says what the readings, search data and rankings show, with the figures and where they came from" do
    read_site(nil, posts: 0, tools: [], locations: 0, recent: 0)
    read_site(rival, posts: 10, tools: %w[google_ads booking], locations: 12, recent: 5)
    search(nil, "keywords", keywords(["plumber", 8, 2000]))
    theirs = search(rival, "keywords", keywords(["plumber", 2, 2000], ["drain cleaning", 3, 900], ["sump pump", 6, 300], ["far away", 15, 5000]))
    search(nil, "overview", {"organic_traffic" => 1000}, at: 40.days.ago)
    search(nil, "overview", {"organic_traffic" => 600})
    search(nil, "competitors", {"competitors" => [{"domain" => "bigbox.example", "shared_keywords" => 40}, {"domain" => "www.rival.example", "shared_keywords" => 30}]})
    tracked = Market::Keyword.track("plumber").first.first
    tracked.rankings.create!(location: "US", position: 3, results: [{"position" => 1, "domain" => "rival.example"}], features: [], checked_at: 7.days.ago)
    tracked.rankings.create!(location: "US", position: 9, results: [{"position" => 2, "domain" => "rival.example"}], features: ["local_pack"], checked_at: 1.hour.ago)

    found = described_class.refresh.index_by(&:key)

    gap = found.fetch("keyword_gap:rival.example")
    expect(gap).to have_attributes(severity: "high", channel: "seo")
    expect(gap.evidence["keywords"].map { it["keyword"] }).to eq(["drain cleaning", "sump pump"])
    expect(gap.evidence["monthly_searches"]).to eq(1200)
    expect(gap.sources.map { it["id"] }).to include(theirs.id)
    expect(found.fetch("losing_ground").evidence).to include("organic_traffic_before" => 1000, "organic_traffic_now" => 600, "change_percent" => -40)
    expect(found.fetch("ranking_drops").evidence["drops"].map { it.slice("keyword", "was", "now") }).to eq([{"keyword" => "plumber", "was" => 3, "now" => 9}])
    expect(found.fetch("outranked").evidence["by_competitor"]).to eq("Rival" => 1)
    expect(found.keys).to include("map_pack", "competitor_ads", "location_pages", "content_freshness", "conversion_tools", "unwatched_search_competitors")
    expect(found.fetch("unwatched_search_competitors").evidence["sites"].map { it["domain"] }).to eq(["bigbox.example"])
    expect(found.keys).not_to include("profile_gaps", "stale_search", "no_competitors")
  end

  it "lives while it holds: changed_at moves only when it changes, and it resolves when it stops" do
    first = described_class.refresh(now: 3.days.ago).index_by(&:key)
    expect(first.keys).to contain_exactly("stale_site", "stale_search")

    same = described_class.refresh(now: 2.days.ago).find_by!(key: "stale_search")
    expect(same.changed_at.to_i).to eq(first["stale_search"].changed_at.to_i)
    expect(same.last_seen_at.to_i).to eq(2.days.ago.to_i)

    search(nil, "overview", {"organic_traffic" => 10})
    described_class.refresh(now: 1.day.ago)
    expect(described_class.find_by!(key: "stale_search")).to have_attributes(state: "resolved")
  end

  it "stays dismissed while it holds" do
    described_class.refresh
    finding = described_class.find_by!(key: "stale_site")
    finding.dismiss(by: create(:user, name: "Sam"))
    described_class.refresh

    expect(finding.reload).to have_attributes(state: "dismissed", dismissed_by_name: "Sam")
    expect(described_class.open.pluck(:key)).not_to include("stale_site")
  end
end
