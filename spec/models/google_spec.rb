# frozen_string_literal: true

require "rails_helper"
require_relative "../support/market_helpers"

helpers = Rails.root.join("plugins/google/spec/support/google_helpers.rb")
require helpers.to_s if helpers.exist?

# Market with the Google plugin (cms-google) connected: Search Console,
# Analytics and the Business Profile in findings, the report and the AI's brief.
RSpec.describe "Market with Google", type: :request do
  let(:admin) { create(:user) }

  before do
    skip "the Google plugin isn't installed" unless defined?(::Google::Sync) && defined?(GoogleHelpers)
    extend GoogleHelpers
    switch_plugin :market, on: true
    switch_plugin :google, on: true
    site_address
    fake_google
    connect_google
    Google::Sync.load_choices
    Google::Sync.run!
    Page.create!(slug: "emergency", title: "Emergency plumbing", status: "published", locale: "en")
  end

  after { Google::Client.transport = nil }

  it "finds pages shown a lot but clicked little, searches close to the top, pages that don't convert, and unanswered reviews" do
    Market::Finding.refresh
    kinds = Market::Finding.open.pluck(:kind)
    expect(kinds).to include("gsc_low_clicks", "gsc_striking_distance", "ga_leaky_pages", "gbp_unanswered_reviews")
    low = Market::Finding.find_by!(kind: "gsc_low_clicks")
    expect(low.evidence).to include("page_path" => "emergency", "impressions" => 1500, "searches" => ["emergency plumber"])
    expect(low.related).to eq([:page, Page.find_by!(slug: "emergency")])
  end

  it "tells the AI Google's real figures for the page and search it works on" do
    keyword = Market::Keyword.track("emergency plumber").first.first
    brief = Market::Workup::Brief.new("keyword:#{keyword.id}").to_s
    expect(brief).to include("Google Search Console, last 28 days (real figures): 280 clicks", "This search in Search Console: emergency plumber",
      "Google Analytics, last 28 days: 560 sessions, 28 key events")

    page = Page.find_by!(slug: "emergency")
    expect(Market::Workup::Brief.new("page:#{page.id}").to_s).to include("Searches /emergency is found for: emergency plumber", "Landing page /emergency: 90 sessions, 0 key events")
  end

  it "shows Google on the report, Search and Maps, and opens a page in the sheet" do
    sign_in_as admin
    get market_report_path
    expect(response.body).to include("Clicks from Google", "Visits and enquiries", "From the Business Profile", "Enquiries")

    get market_search_path
    expect(response.body).to include("Google Search Console", "Close to the top", "Shown a lot, clicked little", "emergency plumber")

    page = Page.find_by!(slug: "emergency")
    get market_search_path(sheet: "page:#{page.id}")
    expect(response.body).to include("Found on Google for", "emergency plumber", "Suggestions")

    keyword = Market::Keyword.track("plumber").first.first
    Market::LocalScan.from_results(keyword: keyword, profile: Market::Profile.update({"local_zip" => "49503", "local_grid" => "3"}, MarketHelpers::FakeGeocoder),
      answers: Market::LocalGrid.points([42.96, -85.65], radius_miles: 5, size: 3).map { {point: it, results: []} }).save!
    get market_maps_path(keyword: keyword.id)
    expect(response.body).to include("Business Profile, 28 days", "84 calls", "Answer 1 Google review")

    Market::Finding.refresh
    get market_findings_path(finding: Market::Finding.find_by!(kind: "gsc_low_clicks").id)
    expect(response.body).to include("Edit the page")
  end
end
