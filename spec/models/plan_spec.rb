# frozen_string_literal: true

require "rails_helper"
require_relative "../support/market_helpers"

RSpec.describe Market::Plan do
  let!(:rival) { Market::Competitor.create!(name: "Rival", website: "https://rival.example", threat: "high") }
  let(:plan) { described_class.create! }

  before do
    site_address
    Market::Settings.update("anthropic_api_key" => "sk-test")
    Market::Profile.update("industry" => "Plumbing", "service_area" => "Springfield")
    read_site(rival, locations: 15)
    Market::Opportunity.create!(title: "Claim the Google Business Profile", channel: "local")
    Market::Keyword.track("plumber")
  end

  let(:answer) do
    {"summary" => "Rival owns the towns around Springfield.", "positioning" => "The plumber who shows up the same day.",
     "industry" => {"name" => "Residential plumbing", "naics_code" => "238220", "why" => "Homes"},
     "competitors_to_check" => [{"name" => "Rival", "website" => "rival.example", "why" => "listed"}, {"name" => "Drain Kings", "website" => "drainkings.example", "why" => "drains"}],
     "keywords_to_track" => ["plumber", "Emergency plumber springfield"],
     "opportunities" => [
       {"channel" => "local", "title" => "Publish a page for each town served", "detail" => "One per town.", "evidence" => "Rival has 15", "impact" => "high", "effort" => "medium", "horizon" => "now"},
       {"channel" => "local", "title" => "claim the google business profile", "detail" => "", "evidence" => "", "impact" => "high", "effort" => "low", "horizon" => "now"},
       {"channel" => "nonsense", "title" => "Start a newsletter", "detail" => "", "evidence" => "", "impact" => "huge", "effort" => "low", "horizon" => "later"}
     ]}
  end

  it "is drafted by Claude from everything known, adding new opportunities and suggestions to check" do
    transport = MarketHelpers::FakeTransport.new(claude_answer(answer))
    plan.run!(claude: Market::Claude.new(transport: transport))

    request = transport.calls.first.first
    expect(request).to include(model: "claude-opus-5-5", fallbacks: "default")
    expect(request.dig(:output_config, :format, :type)).to eq("json_schema")
    prompt = request[:messages].first[:content]
    expect(prompt).to include("Business: Acme Plumbing", "Rival (direct, high threat)", "\"locations\":15", "Claim the Google Business Profile")

    expect(plan.reload).to have_attributes(state: "ready", summary: "Rival owns the towns around Springfield.")
    expect(plan.opportunities.order(:id).map(&:title)).to eq(["Publish a page for each town served", "Start a newsletter"])
    expect(plan.opportunities.find_by!(title: "Start a newsletter")).to have_attributes(channel: "seo", impact: "medium")
    expect(plan.new_competitor_suggestions.map { it["name"] }).to eq(["Drain Kings"])
    expect(plan.new_keyword_suggestions).to eq(["emergency plumber springfield"])
    expect(plan).to be_industry_suggestion_new
  end

  it "keeps why it failed, and changes nothing" do
    plan.run!(claude: Market::Claude.new(transport: MarketHelpers::FakeTransport.new([401, JSON.generate({"error" => {"message" => "bad key"}})])))

    expect(plan.reload).to have_attributes(state: "failed", error: "Anthropic didn't accept the API key in Settings › Market")
    expect(Market::Opportunity.count).to eq(1)
  end
end
