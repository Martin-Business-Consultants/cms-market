# frozen_string_literal: true

require "rails_helper"
require_relative "../support/market_helpers"

RSpec.describe Market::Reading do
  let(:rival) { Market::Competitor.create!(name: "Rival", website: "www.rival.example/") }

  it "keeps a competitor's website and what changed since, in plain words" do
    expect(rival.website).to eq("https://www.rival.example")
    expect(read_site(rival).differences).to be_empty

    later = read_site(rival, pages: 70, posts: 14, tools: %w[google_analytics google_ads], title: "Rival Plumbing | Same-day")
    expect(later.differences).to include("Home page title: “Rival Plumbing” → “Rival Plumbing | Same-day”", "Now runs Google Ads",
      "+30 pages (now 70)", "+4 posts (now 14)")
    expect(rival.latest_reading).to eq(later)
  end

  it "reads the site's own address for the site, and leaves small moves alone" do
    site_address
    read_site(nil, pages: 100)
    own = read_site(nil, pages: 104, tools: [])

    expect(own).to have_attributes(own?: true, domain: "acme.example", differences: ["No longer runs Google Analytics"])
    expect(described_class.own_latest).to eq(own)
  end

  it "keeps why when nothing could be read, and doesn't compare against it" do
    failed = described_class.take(rival, probe: MarketHelpers::FakeProbe.new("rival.example",
      {"domain" => "rival.example", "home_page" => {"error" => "Timeout"}, "sitemap" => {"error" => "none found"}}))

    expect(failed).not_to be_read
    expect(failed.error).to include("Timeout")
    expect(read_site(rival).differences).to be_empty
  end

  it "answers each competitor's latest in one query" do
    other = Market::Competitor.create!(name: "Other", website: "https://other.example")
    read_site(rival)
    newest = read_site(rival)
    theirs = read_site(other)

    expect(described_class.latest_for([rival, other])).to eq(rival.id => newest, other.id => theirs)
  end

  it "won't watch two competitors on one website" do
    rival
    duplicate = Market::Competitor.new(name: "Again", website: "http://rival.example/contact")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:website].first).to include("Rival")
    expect(Market::Competitor.matching(name: "x", website: "rival.example")).to eq(rival)
  end
end
