# frozen_string_literal: true

require "rails_helper"
require_relative "../support/market_helpers"

RSpec.describe "Market", type: :request do
  include ActiveJob::TestHelper

  let(:admin) { create(:user, name: "Sam Seller") }
  let!(:rival) { Market::Competitor.create!(name: "Rival Plumbing", website: "https://rival.example", threat: "high") }

  def api_headers(user) = {"Authorization" => "Bearer #{user.api_token!.token}", "Accept" => "application/json"}

  before do
    switch_plugin :market, on: true
    site_address
    read_site(rival)
    read_site(rival, pages: 80, tools: %w[google_analytics google_ads])
    read_site(nil, pages: 12, tools: [], locations: 0)
    Market::Finding.refresh
  end

  it "is a 404 while the plugin is off" do
    switch_plugin :market, on: false
    sign_in_as admin

    get market_overview_path
    expect(response).to have_http_status(:not_found)
  end

  describe "the admin" do
    before { sign_in_as admin }

    it "shows every screen" do
      opportunity = Market::Opportunity.create!(title: "Publish town pages", channel: "local")
      Market::Plan.create!(state: "ready", summary: "The towns are open.", positioning: "Same-day.", keyword_suggestions: ["plumber springfield"],
        competitor_suggestions: [{"name" => "Drain Kings", "website" => "https://drainkings.example"}], industry_suggestion: {"name" => "Residential plumbing"})
      Market::Keyword.track("plumber")
      [market_overview_path, market_findings_path, market_findings_path(state: "all"), market_competitors_path, market_competitor_path(rival),
        new_market_competitor_path, edit_market_competitor_path(rival), market_search_path, market_search_pulls_path, market_plan_path,
        edit_market_profile_path, settings_market_path, dashboard_path, market_maps_path, market_report_path, market_report_path(period: "12m"),
        market_search_path(sheet: "visibility:own"), market_search_path(sheet: "visibility:#{rival.id}"), market_search_path(sheet: "keyword:#{Market::Keyword.first.id}"),
        market_work_path(subject: "opportunity:#{opportunity.id}")].each do |path|
        get path
        expect(response).to have_http_status(:ok), "#{path}: #{response.status}"
      end
      get market_plan_path
      expect(response.body).to include("The towns are open.", "Drain Kings", "plumber springfield", opportunity.title)
    end

    it "compares the site with its competitors, a lit dot for each tool" do
      get market_competitors_path

      expect(response.body).to include("Acme Plumbing", "Rival Plumbing", "High threat")
      expect(response.body.scan(%(class="market-dot market-dot--on" title="Google Ads")).size).to eq(1)
    end

    it "adds a competitor, reads its website in the background, and won't add the same website twice" do
      expect { post market_competitors_path, params: {competitor: {name: "Drain Kings", website: "drainkings.example", kind: "direct", threat: "medium"}} }
        .to have_enqueued_job(Market::CheckJob)
      expect(Market::Competitor.find_by!(name: "Drain Kings").domain).to eq("drainkings.example")

      post market_competitors_path, params: {competitor: {name: "Rival again", website: "https://www.rival.example/"}}
      expect(flash[:notice]).to include("already watched")
      expect(Market::Competitor.count).to eq(2)
    end

    it "saves the profile, and tracks searches" do
      patch market_profile_path, params: {profile: {industry: "Plumbing", search_location: "Springfield , Illinois,United States"}}
      expect(Market::Profile.current).to have_attributes(industry: "Plumbing", search_location: "Springfield,Illinois,United States")

      post market_keywords_path, params: {keyword: {keywords: "plumber, emergency plumber\nplumber"}}
      expect(Market::Keyword.pluck(:keyword)).to contain_exactly("plumber", "emergency plumber")
    end

    it "starts a draft page for an opportunity and opens it" do
      opportunity = Market::Opportunity.create!(title: "Plumbing in Springfield", channel: "local")

      post market_opportunity_page_path(opportunity)

      page = opportunity.reload.page
      expect(page).to have_attributes(status: "draft", title: "Plumbing in Springfield")
      expect(response).to redirect_to(edit_page_path(page.path))
    end

    it "shows each search's grid on the map, and saves the ZIP and radius" do
      Market::Profile.update({"local_zip" => "49503", "local_grid" => "3"}, MarketHelpers::FakeGeocoder)
      keyword = Market::Keyword.track("plumber").first.first
      points = Market::LocalGrid.points([42.9632, -85.6528], radius_miles: 10, size: 3).each_with_index.map { |point, index| {point: point, results: [{"position" => index + 1, "title" => "Acme Plumbing"}, {"position" => index + 2, "title" => "Drain Kings", "rating" => 4.8, "reviews" => 300}]} }
      Market::LocalScan.from_results(keyword: keyword, profile: Market::Profile.current, answers: points).save!

      get market_maps_path
      expect(response.body).to include("3 × 3 points within 10 miles of 49503", "average <strong>5.0</strong>")
      expect(response.body.scan("market-grid__cell--top").size).to eq(3)

      get market_maps_path(keyword: keyword.id, point: "0-0")
      expect(response.body).to include("#1 here", "Acme Plumbing", "Who leads the area", "Drain Kings", "4.8★", "Watch Drain Kings", "Close the review gap")

      get edit_market_profile_path
      expect(response.body).to include("ZIP or postcode", "Centred on 49503, Grand Rapids")

      get "/api/market/search", headers: api_headers(admin)
      expect(response.parsed_body["tracked"].first["local"]).to include("zip" => "49503", "average_position" => 5.0, "found_points" => 9)
      expect(response.parsed_body["local_area"]).to include("zip" => "49503", "radius_miles" => 10.0)
    end

    it "starts with a short intake, and shows what the AI filled in" do
      get market_overview_path
      expect(response.body).to include("Get started")
      get new_market_intake_path
      expect(response).to have_http_status(:ok)

      switch_plugin :ai, on: true
      Ai::Settings.update("provider" => "opencode", "api_key" => "zen-key")
      expect { post market_intake_path, params: {intake: {business_name: "Acme Plumbing", website: "https://acme.example"}} }.to have_enqueued_job(Market::IntakeJob)
      expect(response).to redirect_to(market_intake_path)
      get market_intake_path
      expect(response.body).to include("Reading acme.example")

      Market::Intake.last.update!(state: "ready", summary: "A plumber.", filled: ["industry"], competitor_suggestions: [{"name" => "Drain Kings"}], keyword_suggestions: ["plumber"])
      Market::Profile.fill_in("industry" => "Plumbing")
      get market_intake_path
      expect(response.body).to include("A plumber.", "Drain Kings", "Searches to track")
      get edit_market_profile_path
      expect(response.body).to include("The AI filled in industry: check them")
    end

    it "saves the answers and sends you to the profile when the AI isn't set up" do
      post market_intake_path, params: {intake: {business_name: "Acme Plumbing"}}

      expect(response).to redirect_to(edit_market_profile_path)
      expect(flash[:alert]).to include("fill in the rest here")
    end

    it "lists the findings beside the open one, whose figures and actions are in the second column" do
      connect_search
      Market::SearchSnapshot.create!(domain: "acme.example", kind: "keywords", data: {"keywords" => []}, taken_at: Time.current)
      Market::SearchSnapshot.create!(competitor: rival, domain: "rival.example", kind: "keywords", taken_at: Time.current,
        data: {"keywords" => [{"keyword" => "drain cleaning", "position" => 2, "volume" => 900}]})
      Market::Finding.refresh
      gap = Market::Finding.find_by!(kind: "keyword_gap")

      get market_findings_path
      expect(response.body).to include(%(<turbo-frame id="market_findings" data-turbo-action="advance">))
      expect(response.body.scan("market-item--current").size).to eq(1)

      get market_findings_path(finding: gap.id)
      expect(response.body).to include(ERB::Util.html_escape(gap.title), "The figures", "Make it an opportunity", "Track these searches", "Rival Plumbing&#39;s website")
      expect(response.body).to include(%(<table class="data-table market-evidence-table">), "drain cleaning")

      post market_finding_opportunity_path(gap)
      expect(response).to redirect_to(market_findings_path(finding: gap.id))
      opportunity = Market::Opportunity.find_by!(finding_key: gap.key)
      expect(opportunity).to have_attributes(channel: "seo", title: gap.title)
      post market_finding_opportunity_path(gap)
      expect(Market::Opportunity.where(finding_key: gap.key).count).to eq(1)

      get market_findings_path(finding: gap.id)
      expect(response.body).to include("On the plan: open")
    end

    it "has the overview's tabs side by side with the open one, where it's acted on" do
      opportunity = Market::Opportunity.create!(title: "Publish town pages", channel: "local", impact: "high", effort: "low")
      change = Market::Reading.where.not(competitor_id: nil).latest_first.first

      get market_overview_path
      expect(response.body).to include(%(<turbo-frame id="market_overview" data-turbo-action="advance">), "What the data says", "Best opportunities", "What competitors changed")

      get market_overview_path(tab: "opportunities")
      expect(response.body).to include("Publish town pages", "Start a draft page", "Done")
      patch market_opportunity_path(opportunity), params: {opportunity: {state: "done"}, return_to: market_overview_path(tab: "opportunities", item: opportunity.id)}
      expect(response).to redirect_to(market_overview_path(tab: "opportunities", item: opportunity.id))
      expect(opportunity.reload.state).to eq("done")

      get market_overview_path(tab: "changes", item: change.id)
      expect(response.body).to include("Rival Plumbing changed their website", "Now runs Google Ads", "Make it an opportunity")
      post market_change_opportunity_path(change), params: {return_to: "//evil.example"}
      expect(response).to redirect_to(market_overview_path(tab: "changes", item: change.id))
      expect(Market::Opportunity.find_by!(finding_key: "change:#{change.id}").title).to eq("Answer Rival Plumbing's changes")
    end

    it "says what to do next about each competitor, and sizes one up with the AI" do
      get market_competitors_path
      expect(response.body).to include("Next step")

      get market_competitor_path(rival)
      expect(response.body).to include("Next steps", "Sizing them up")

      switch_plugin :ai, on: true
      Ai::Settings.update("provider" => "opencode", "api_key" => "zen-key")
      expect { post market_competitor_assessment_path(rival) }.to have_enqueued_job(Market::AssessmentJob)
      allow(Ai).to receive(:structured).and_return("summary" => "They win on location pages.", "strengths" => ["80 pages"], "weaknesses" => ["No booking"],
        "threat" => "medium", "threat_why" => "Close by", "moves" => [{"title" => "Add online booking", "channel" => "website", "detail" => "Book on the site.", "why" => "They have none", "impact" => "high", "effort" => "low"}])
      rival.reload.assess!

      get market_competitor_path(rival)
      expect(response.body).to include("They win on location pages.", "Add online booking", "Make it an opportunity")

      post market_competitor_move_path(rival, 0), params: {return_to: market_competitor_path(rival)}
      expect(Market::Opportunity.last).to have_attributes(title: "Add online booking", channel: "website")
      expect(response).to redirect_to(market_competitor_path(rival))

      patch market_competitor_assessment_path(rival)
      expect(rival.reload).to have_attributes(strengths: "80 pages", weaknesses: "No booking", threat: "medium")
    end

    it "opens a tracked search in a sheet, works it out with the AI, and sends a change to Approvals" do
      switch_plugin :ai, on: true
      switch_plugin :approvals, on: true
      Ai::Settings.update("provider" => "opencode", "api_key" => "zen-key")
      keyword = Market::Keyword.track("plumber").first.first
      subject = "keyword:#{keyword.id}"

      get market_search_path(sheet: subject)
      expect(response.body).to include("dialog--sheet", "The search “plumber”", "Work it out with AI")

      expect { post market_workups_path, params: {subject: subject, return_to: market_search_path(sheet: subject)} }.to have_enqueued_job(Market::WorkupJob)
      expect(response).to redirect_to(market_search_path(sheet: subject))
      allow(Ai).to receive(:structured).and_return("summary" => "Track the night ones.", "changes" => [
        {"kind" => "track_searches", "title" => "Track night searches", "why" => "Demand", "page_path" => "", "page_title" => "", "meta_title" => "", "meta_description" => "",
         "focus_keyword" => "", "json_ld" => "", "text_edits" => [], "slug" => "", "body_markdown" => "", "searches" => ["24 hour plumber"], "channel" => "seo"}
      ])
      workup = Market::Workup.last
      workup.run!

      get market_search_path(sheet: subject)
      expect(response.body).to include("Track the night ones.", "Track them")
      post market_workup_change_path(workup, 0), params: {return_to: market_search_path(sheet: subject)}
      expect(Market::Keyword.pluck(:keyword)).to include("24 hour plumber")
      get market_search_path(sheet: subject)
      expect(response.body).to include("Done")
    end

    it "reports the market's health and how it's moved" do
      Market::Keyword.track("plumber")
      get market_report_path
      expect(response.body).to include("Market health", "Search traffic", "Posting", "Content now", "market-bars")
    end

    it "gives an opportunity AI suggestions, not only a draft page" do
      switch_plugin :ai, on: true
      Ai::Settings.update("provider" => "opencode", "api_key" => "zen-key")
      opportunity = Market::Opportunity.create!(title: "Ask for reviews", channel: "reviews")
      get market_plan_path
      expect(response.body).to include("Work it out with AI")
      expect(response.body.scan("Start a draft page").size).to eq(0)
    end

    it "keeps secrets out of Settings › Market" do
      patch settings_market_path, params: {market: {dataforseo_login: "api@example.com", dataforseo_password: "secret-pass", monthly_budget_dollars: "40.50",
                                                    refresh: "weekly"}}
      settings = Market::Settings.current
      expect(settings).to have_attributes(dataforseo_password: "secret-pass", monthly_budget_cents: 4050, refresh: "weekly")

      get settings_market_path
      expect(response.body).not_to include("secret-pass")
      expect(response.body).not_to match(/anthropic/i)
      patch settings_market_path, params: {market: {dataforseo_password: "", monthly_budget_dollars: "10"}}
      expect(Market::Settings.current.dataforseo_password).to eq("secret-pass")
    end

    it "refuses a pull without DataForSEO, then pulls in the background" do
      post market_search_pulls_path
      expect(flash[:alert]).to include("Connect DataForSEO")

      connect_search
      expect { post market_search_pulls_path }.to have_enqueued_job(Market::SearchPullJob)
      post market_search_pulls_path
      expect(flash[:alert]).to include("already running")
    end
  end

  it "keeps authors to reading" do
    author = create(:user, admin: false, role: create(:role, permissions: %w[market:read]))
    sign_in_as author

    get market_overview_path
    expect(response).to have_http_status(:ok)
    post market_competitors_path, params: {competitor: {name: "Nope"}}
    expect(Market::Competitor.where(name: "Nope")).to be_empty
  end

  describe "the API, for agents and a local harness" do
    let(:headers) { api_headers(admin) }

    it "lists the findings worst first, and since a time only what changed" do
      get "/api/market/findings", headers: headers
      body = response.parsed_body
      as_of = body["as_of"]
      expect(body["findings"]).to all(include("key", "severity", "evidence", "sources", "changed_at"))

      get "/api/market/findings", params: {since: as_of}, headers: headers
      expect(response.parsed_body["findings"]).to be_empty

      travel 1.minute do
        finding = Market::Finding.open.first
        patch "/api/market/findings/#{finding.id}", params: {finding: {state: "dismissed"}}, headers: headers, as: :json
        expect(response.parsed_body["state"]).to eq("dismissed")

        get "/api/market/findings", params: {since: as_of}, headers: headers
        expect(response.parsed_body["findings"].map { it.values_at("key", "state") }).to eq([[finding.key, "dismissed"]])
      end

      get "/api/market/findings", params: {since: "yesterday-ish"}, headers: headers
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "gives the market at a glance, the competitors with their readings, and the search data" do
      get "/api/market", headers: headers
      expect(response.parsed_body["profile"]["business_name"]).to eq("Acme Plumbing")
      expect(response.parsed_body["competitor_changes"].first["changes"]).to include("Now runs Google Ads")

      get "/api/market/competitors", headers: headers
      body = response.parsed_body
      expect(body["own_website"]["facts"]["sitemap"]["pages"]).to eq(12)
      expect(body["competitors"].first).to include("name" => "Rival Plumbing", "tools" => ["Google Ads", "Google Analytics"])

      get "/api/market/search", headers: headers
      expect(response.parsed_body).to include("summary" => "No search data yet")
    end

    it "changes the profile, adds competitors and searches, and starts a page for an opportunity" do
      patch "/api/market/profile", params: {profile: {industry: "Plumbing"}}, headers: headers, as: :json
      expect(response.parsed_body["industry"]).to eq("Plumbing")

      post "/api/market/competitors", params: {competitor: {name: "Drain Kings", website: "https://drainkings.example"}}, headers: headers, as: :json
      expect(response).to have_http_status(:created)
      post "/api/market/competitors", params: {competitor: {name: "Same", website: "rival.example"}}, headers: headers, as: :json
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to include("error" => "refused")

      post "/api/market/keywords", params: {keyword: {keywords: "plumber\ndrain cleaning"}}, headers: headers, as: :json
      expect(response.parsed_body["added"].map { it["keyword"] }).to eq(["plumber", "drain cleaning"])

      post "/api/market/opportunities", params: {opportunity: {title: "Drain cleaning page", channel: "seo", impact: "high", effort: "low"}}, headers: headers, as: :json
      id = response.parsed_body["id"]
      post "/api/market/opportunities/#{id}/page", headers: headers, as: :json
      expect(response.parsed_body["page"]).to include("status" => "draft", "title" => "Drain cleaning page")
      post "/api/market/opportunities/#{id}/page", headers: headers, as: :json
      expect(response).to have_http_status(:conflict)
    end

    it "refuses what can't be done as things stand, and says why" do
      post "/api/market/search/pulls", headers: headers, as: :json
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["message"]).to include("Connect DataForSEO")

      switch_plugin :ai, on: true
      post "/api/market/plans", headers: headers, as: :json
      expect(response.parsed_body["message"]).to include("Settings › AI")

      Ai::Settings.update("provider" => "opencode", "api_key" => "zen-key")
      expect { post "/api/market/plans", headers: headers, as: :json }.to have_enqueued_job(Market::PlanJob)
      expect(response).to have_http_status(:accepted)
    end

    it "starts the intake and reads it back" do
      switch_plugin :ai, on: true
      Ai::Settings.update("provider" => "opencode", "api_key" => "zen-key")

      post "/api/market/intake", params: {intake: {business_name: "Acme Plumbing", website: "acme.example"}}, headers: headers, as: :json
      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body).to include("state" => "queued")
      expect(response.parsed_body["profile"]).to include("business_name" => "Acme Plumbing", "website" => "https://acme.example")

      get "/api/market/intake", headers: headers
      expect(response.parsed_body["answers"]).to include("business_name" => "Acme Plumbing")
    end

    it "answers the report, and runs work-ups and sends their changes on" do
      get "/api/market/report", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("parts", "visibility", "rankings", "maps", "posting", "content", "findings_by_week")

      post "/api/market/workups", params: {subject: "keyword:999"}, headers: headers
      expect(response.parsed_body["error"]).to eq("refused")

      switch_plugin :ai, on: true
      Ai::Settings.update("provider" => "opencode", "api_key" => "zen-key")
      keyword = Market::Keyword.track("plumber").first.first
      post "/api/market/workups", params: {subject: "keyword:#{keyword.id}"}, headers: headers
      expect(response).to have_http_status(:accepted)
      id = response.parsed_body.dig("workup", "id")
      Market::Workup.find(id).update!(state: "ready", answer: {"summary" => "x", "changes" => [{"kind" => "task", "title" => "Post weekly on the profile", "why" => "", "channel" => "local"}]})

      get "/api/market/workups/#{id}", headers: headers
      expect(response.parsed_body.dig("workup", "changes", 0)).to include("index" => 0, "kind" => "task", "sent" => nil)
      post "/api/market/workups/#{id}/changes/0", headers: headers
      expect(response).to have_http_status(:created)
      expect(Market::Opportunity.last.title).to eq("Post weekly on the profile")
    end

    it "holds every caller to its role: a reader can't change anything" do
      reader = create(:user, admin: false, role: create(:role, permissions: %w[market:read]))
      get "/api/market/findings", headers: api_headers(reader)
      expect(response).to have_http_status(:ok)
      post "/api/market/keywords", params: {keyword: {keywords: "plumber"}}, headers: api_headers(reader), as: :json
      expect(response).to have_http_status(:forbidden)
      post "/api/market/plans", headers: api_headers(reader), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "is listed in the manifest" do
      get "/api/manifest", headers: headers

      expect(response.body).to include("/api/market/findings", "/api/market/search")
    end
  end
end
