# frozen_string_literal: true

require "rails_helper"
require_relative "../support/market_helpers"

RSpec.describe Market::Intake do
  # A probe answering the home page and a couple of pages without the network.
  class FakeIntakeProbe
    def domain = "acme.example"
    def facts = {"home_page" => {"title" => "Acme Plumbing | Grand Rapids plumbers"}, "sitemap" => {"sample" => ["https://acme.example/about", "https://acme.example/blog/x"]}}
    def page_text(path) = (path == "/") ? "24/7 emergency plumbing across Grand Rapids." : "Family-run since 1998."
  end

  let(:answer) do
    {"summary" => "A family-run plumber in Grand Rapids.", "industry" => "Residential plumbing", "naics_code" => "238220",
     "service_area" => "Grand Rapids and Kent County", "offerings" => "Emergency plumbing, drains, water heaters", "audience" => "Homeowners",
     "positioning" => "Family-run, 24/7", "goals" => "More emergency calls", "search_location" => "Grand Rapids,Michigan,United States",
     "maps_name" => "Acme Plumbing", "local_radius_miles" => 15,
     "competitors_to_check" => [{"name" => "Rival Plumbing", "website" => "rival.example", "why" => "Same area"}],
     "keywords_to_track" => ["Emergency plumber grand rapids", "water heater repair grand rapids"], "to_check" => ["The service area beyond Kent County"]}
  end

  before do
    site_address
    switch_plugin :ai, on: true
    Ai::Settings.update("provider" => "opencode", "api_key" => "zen-key")
  end

  it "saves the answers, then the AI fills in only what's empty, marked to check" do
    Market::Profile.update("audience" => "Landlords")
    asked = nil
    allow(Ai).to receive(:structured) { |**request| asked = request; answer }

    intake = described_class.start({"business_name" => "Acme Plumbing", "website" => "acme.example", "local_zip" => "49503", "about" => "Family plumbers"}, geocoder: MarketHelpers::FakeGeocoder)
    expect(intake.state).to eq("queued")
    intake.run!(probe: FakeIntakeProbe.new)

    profile = Market::Profile.current
    expect(profile).to have_attributes(business_name: "Acme Plumbing", website: "https://acme.example", local_zip: "49503", notes: "Family plumbers",
      industry: "Residential plumbing", audience: "Landlords", local_radius_miles: 15.0)
    expect(intake.reload).to have_attributes(state: "ready", summary: "A family-run plumber in Grand Rapids.")
    expect(intake.filled).to include("industry", "service_area", "offerings", "maps_name", "local_radius_miles")
    expect(intake.filled).not_to include("audience")
    expect(profile.ai_filled).to match_array(intake.filled)
    expect(intake.new_competitor_suggestions).to eq([{"name" => "Rival Plumbing", "website" => "https://rival.example", "why" => "Same area"}])
    expect(intake.new_keyword_suggestions).to eq(["emergency plumber grand rapids", "water heater repair grand rapids"])
    expect(asked[:prompt]).to include("24/7 emergency plumbing across Grand Rapids.", "The text of https://acme.example/about", "Business name: Acme Plumbing")
    expect(asked[:prompt]).not_to include("blog/x")

    Market::Profile.update("industry" => "Plumbing")
    expect(Market::Profile.current.ai_filled).not_to include("industry")
  end

  it "keeps the answers and says why when the AI isn't set up" do
    Ai::Settings.update("remove_api_key" => "1")

    intake = described_class.start({"business_name" => "Acme Plumbing"})

    expect(intake).to have_attributes(state: "failed")
    expect(intake.error).to include("Settings › AI")
    expect(Market::Profile.current.business_name).to eq("Acme Plumbing")
  end
end
