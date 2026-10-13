# frozen_string_literal: true

require "rails_helper"
require_relative "../support/market_helpers"

RSpec.describe "Market search" do
  before { site_address }

  describe Market::Search::Client do
    let(:waits) { [] }

    before { connect_search }

    def client(*answers)
      @transport = MarketHelpers::FakeTransport.new(*answers)
      described_class.new(setting: Market::Settings.current, transport: @transport, wait: ->(seconds) { waits << seconds })
    end

    it "answers a task's result, with what it cost in the ledger" do
      result = client([200, dataforseo([{"items" => []}], cost: 0.0123)]).post("dataforseo_labs/google/domain_rank_overview/live", {target: "acme.example"},
        target: "acme.example", ceiling: 0.05)

      expect(result).to eq([{"items" => []}])
      expect(@transport.calls.first.first(2)).to eq([:post, URI("https://api.dataforseo.com/v3/dataforseo_labs/google/domain_rank_overview/live")])
      expect(Market::SearchRequest.last).to have_attributes(status_code: 20000, cost: 0.0123.to_d, attempts: 1, target: "acme.example")
      expect(Market::Settings.current.spent_this_month).to eq(0.0123.to_d)
    end

    it "tries again what may pass, waiting longer each time" do
      result = client([503, "busy"], [200, dataforseo(nil, code: 50401, message: "timeout")], [200, dataforseo([1])]).post("x/live", {}, target: "t", ceiling: 0.01)

      expect(result).to eq([1])
      expect(waits).to eq([2, 4])
      expect(Market::SearchRequest.last.attempts).to eq(3)
    end

    it "gives up after three tries, and records why" do
      failing = client(*Array.new(3) { described_class::Transient.new("Couldn't reach DataForSEO: SocketError") })

      expect { failing.post("x/live", {}, target: "t", ceiling: 0.01) }.to raise_error(described_class::Transient, /SocketError/)
      expect(Market::SearchRequest.last).to have_attributes(attempts: 3, error: "Couldn't reach DataForSEO: SocketError")
    end

    it "fails at once on a wrong login, no funds or a bad field, each as itself" do
      expect { client([200, dataforseo(nil, code: 40100, message: "no", top_code: 40100)]).post("x/live", {}, target: "t", ceiling: 0.01) }.to raise_error(described_class::AuthError)
      expect { client([401, ""]).post("x/live", {}, target: "t", ceiling: 0.01) }.to raise_error(described_class::AuthError)
      expect { client([200, dataforseo(nil, code: 40210, message: "insufficient funds")]).post("x/live", {}, target: "t", ceiling: 0.01) }.to raise_error(described_class::FundsError)
      expect { client([200, dataforseo(nil, code: 40501, message: "invalid field")]).post("x/live", {}, target: "t", ceiling: 0.01) }.to raise_error(described_class::InvalidError)
      expect { client([200, dataforseo(nil, code: 40204, message: "access denied")]).post("x/live", {}, target: "t", ceiling: 0.01) }.to raise_error(described_class::UnavailableError)
      expect(waits).to be_empty
      expect(Market::SearchRequest.count).to eq(5)
    end

    it "asks nothing that could go over the month's budget" do
      Market::Settings.update("monthly_budget_cents" => 10)
      Market::SearchRequest.create!(endpoint: "earlier", cost: 0.09, created_at: Time.current)

      expect { client.post("dataforseo_labs/google/ranked_keywords/live", {}, target: "acme.example", ceiling: 0.25) }
        .to raise_error(described_class::BudgetError, /\$0.01 left/)
      expect(@transport.calls).to be_empty
    end

    it "sets a queued task, fetches it when done, and says when it isn't yet" do
      created = JSON.generate({"status_code" => 20000, "cost" => 0.004, "tasks" => [{"id" => "abc-123", "status_code" => 20100, "status_message" => "Task Created.", "cost" => 0.004, "result" => nil}]})
      queued = JSON.generate({"status_code" => 20000, "cost" => 0, "tasks" => [{"id" => "abc-123", "status_code" => 40602, "status_message" => "Task In Queue.", "result" => nil}]})
      api = client([200, created], [200, queued], [200, dataforseo([{"rating" => {"value" => 4.5}, "reviews_count" => 3, "items" => [{"type" => "google_reviews_search", "review_text" => "Fine", "rating" => {"value" => 4}, "owner_answer" => "Thanks"}]}], cost: 0)])
      search = Market::Search::Api.new(client: api)
      id, endpoint = search.post_reviews("111")
      expect([id, endpoint]).to eq(["abc-123", "business_data/google/reviews/task_get"])
      expect(@transport.calls.first[2].first).to include(cid: "111", depth: 50, sort_by: "newest")

      task = Market::QueuedTask.new(kind: "reviews", task_id: id, endpoint: endpoint)
      expect { search.queued_result(task) }.to raise_error(Market::Search::Client::NotReady)
      expect(search.queued_result(task)).to include("rating" => 4.5, "count" => 3, "reviews" => [a_hash_including("text" => "Fine", "stars" => 4, "answered" => true)])
      expect(@transport.calls.last[1].to_s).to end_with("/v3/business_data/google/reviews/task_get/abc-123")
    end

    it "uses DataForSEO's sandbox in test mode" do
      Market::Settings.update("sandbox" => "1")
      client([200, dataforseo([{"items" => []}])]).post("dataforseo_labs/google/domain_rank_overview/live", {target: "acme.example"}, target: "acme.example", ceiling: 0.05)
      expect(@transport.calls.first[1].to_s).to start_with("https://sandbox.dataforseo.com/v3/")
    end

    it "keeps the balance, which costs nothing" do
      balance = Market::Settings.check!(client: client([200, dataforseo([{"money" => {"balance" => 42.5}}], cost: 0)]))

      expect(balance).to eq(42.5.to_d)
      expect(Market::Settings.current).to have_attributes(balance: 42.5.to_d, last_error: nil)
    end
  end

  describe Market::SearchPull do
    let!(:rival) { Market::Competitor.create!(name: "Rival", website: "https://rival.example") }
    let(:pull) { described_class.create! }

    before do
      connect_search
      Market::Settings.update("ai_platforms" => [], "extras" => [])
      Market::Profile.update("search_location" => "Springfield, Illinois, United States")
      Market::Keyword.track("emergency plumber\nwater heater repair")
    end

    def api(**options)
      MarketHelpers::FakeApi.new(keywords: {"rival.example" => [{"keyword" => "drain cleaning", "volume" => 900, "position" => 3}]},
        competitors: [{"domain" => "bigbox.example", "shared_keywords" => 40}],
        rankings: {"emergency plumber" => [{"position" => 1, "domain" => "rival.example", "url" => "https://rival.example/"},
          {"position" => 5, "domain" => "www.acme.example", "url" => "https://www.acme.example/emergency"}]}, **options)
    end

    it "pulls every part for every site, the rankings from where customers search, then works out the findings" do
      fake = api
      pull.run!(api: fake)

      expect(pull.reload.state).to eq("ready")
      expect(fake.calls).to eq(["overview:acme.example", "keywords:acme.example", "ai_overview:acme.example", "overview:rival.example", "keywords:rival.example",
        "ai_overview:rival.example", "competitors:acme.example", "ranking:emergency plumber", "ranking:water heater repair"])
      ranking = Market::Keyword.find_by!(keyword: "emergency plumber").rankings.first
      expect(ranking).to have_attributes(position: 5, url: "https://www.acme.example/emergency", location: "Springfield,Illinois,United States", page_path: "emergency")
      expect(Market::Finding.pluck(:key)).to include("keyword_gap:rival.example", "unwatched_search_competitors", "outranked")
    end

    it "keeps parts pulled in the last day rather than buying them again, unless forced" do
      pull.run!(api: api)
      again = api
      described_class.create!.run!(api: again)
      expect(again.calls).to eq(["ranking:emergency plumber", "ranking:water heater repair"])

      forced = api
      described_class.create!(force: true).run!(api: forced)
      expect(forced.calls.size).to eq(9)
    end

    it "notes a part that fails and carries on" do
      pull.run!(api: api(failures: {"keywords:rival.example" => Market::Search::Client::InvalidError.new("DataForSEO 40501: invalid field")}))

      expect(pull.reload).to have_attributes(state: "partial", notes: ["Couldn't get keywords for rival.example: DataForSEO 40501: invalid field"])
      expect(Market::SearchSnapshot.count).to eq(6)
    end

    it "stops where it is when the budget runs out or the login is wrong, keeping what it got" do
      pull.run!(api: api(failures: {"overview:rival.example" => Market::Search::Client::BudgetError.new("budget has $0.01 left")}))
      expect(pull.reload).to have_attributes(state: "stopped", error: "budget has $0.01 left")
      expect(Market::SearchSnapshot.count).to eq(3)

      other = described_class.create!(force: true)
      other.run!(api: api(failures: {"overview:acme.example" => Market::Search::Client::AuthError.new("DataForSEO 40100: not authorized")}))
      expect(other.reload.state).to eq("stopped")
      expect(Market::Settings.current.last_error).to eq("DataForSEO 40100: not authorized")
    end

    it "says the most it could cost before it runs" do
      expect(described_class.ceiling).to eq((2 * (0.05 + 0.25 + 0.05) + 0.10 + 2 * 0.02).round(2))
      Market::Settings.update("ai_platforms" => %w[google_ai_overview chat_gpt claude], "extras" => %w[keyword_facts])
      expect(described_class.ceiling).to eq((2 * (0.05 + 0.25 + 0.05) + 0.10 + 2 * 0.02 + 2 * (0.005 + 0.01 + 0.08) + 0.15 + 0.05 + 0.05 + 0.1).round(2))
    end

    it "asks each tracked search of each AI, noting who's named and cited, and pulls the extras" do
      Market::Settings.update("ai_platforms" => Market::AiCheck::PLATFORMS.keys, "extras" => Market::Settings::EXTRAS.keys)
      Market::LocalScan.create!(keyword: Market::Keyword.first, zip: "62701", center_lat: 39.8, center_lng: -89.6, radius_miles: 5, grid: 3, average_position: 4,
        top3_share: 0.2, found_points: 9, checked_at: Time.current, points: [{"row" => 0, "col" => 0, "position" => 4, "cid" => "111"}],
        leaders: [{"title" => "Rival", "domain" => "rival.example", "top3_points" => 9, "cid" => "222"}])
      ai = {"emergency plumber" => {
        "google_ai_overview" => {"text" => "Top picks: **Rival** and Acme Plumbing.", "sources" => [{"domain" => "acme.example", "url" => "https://acme.example/emergency"}]},
        "google_ai_mode" => {"text" => "Rival is the best-reviewed.", "sources" => [{"domain" => "yelp.com", "url" => "https://yelp.com/rival"}]},
        "chat_gpt" => {"text" => "Here are options.", "sources" => [{"domain" => "yelp.com", "url" => "https://yelp.com/best"}], "businesses" => [{"title" => "Rival", "domain" => "rival.example"}, {"title" => "Drain Kings"}]},
        "claude" => {"text" => "I'd call Acme Plumbing (acme.example) first.", "sources" => [{"url" => "https://www.acme.example/"}]}
      }}
      fake = api(ai: ai)
      pull.run!(api: fake)

      expect([pull.reload.state, pull.error, pull.notes]).to eq(["ready", nil, []])
      checks = Market::AiCheck.where(keyword: Market::Keyword.find_by!(keyword: "emergency plumber")).index_by(&:platform)
      expect(checks.keys).to match_array(Market::AiCheck::PLATFORMS.keys)
      expect(checks["google_ai_overview"]).to have_attributes(answered: true, mentioned: true, mention_rank: 2, cited: true)
      expect(checks["google_ai_mode"]).to have_attributes(mentioned: false, cited: false, verdict: "missing")
      expect(checks["chat_gpt"].named.map { it["name"] }).to eq(["Rival", "Drain Kings"])
      expect(checks["claude"]).to have_attributes(mentioned: true, mention_rank: 1, cited: true, model: "claude-sonnet-9")
      expect(checks["gemini"].verdict).to eq("no_answer")
      expect(fake.calls).to include("ai_mentions:google", "ai_mentions:chat_gpt", "keyword_facts", "ai_volume", "serp_competitors", "site_health",
        "business_profile:111", "business_profile:222", "web_mentions:Rival")

      facts = Market::SearchSnapshot.find_by!(kind: "keyword_facts").data["keywords"]["emergency plumber"]
      expect(facts).to include("volume" => 880, "ai_volume" => 40, "intent" => "commercial")
      expect(Market::Finding.pluck(:kind)).to include("ai_named_instead", "ai_cited_sites", "ai_share_of_voice", "gbp_unclaimed", "site_slow", "web_mentions_gap", "questions_to_answer")
      overview = Market::Search::Overview.new
      expect(overview.ai_summary["claude"]).to include(answered: 1, named: 1, cited: 1)
      expect(overview.ai_named_others.to_h).to include("Rival" => 3)
    end

    it "queues Google reviews and fetches them when they're done, reads the AI's themes, and pulls links and the city's searches" do
      switch_plugin :ai, on: true
      Ai::Settings.update("provider" => "opencode", "api_key" => "zen-key")
      Market::Settings.update("ai_platforms" => [], "extras" => %w[keyword_facts reviews], "backlinks" => "1")
      Market::LocalScan.create!(keyword: Market::Keyword.first, zip: "62701", center_lat: 39.8, center_lng: -89.6, radius_miles: 5, grid: 3, average_position: 4,
        top3_share: 0.2, found_points: 9, checked_at: Time.current, points: [{"row" => 0, "col" => 0, "position" => 4, "cid" => "111"}],
        leaders: [{"title" => "Rival", "domain" => "rival.example", "top3_points" => 9, "cid" => "222"}])
      fake = api(ai: {reviews_pending: true})

      expect { pull.run!(api: fake) }.to have_enqueued_job(Market::QueuedTasksJob)
      expect(fake.calls).to include("post_reviews:111", "post_reviews:222", "backlink_history:acme.example", "link_gap", "ads_locations:US",
        "local_volume:Springfield,Illinois,United States")
      expect(Market::QueuedTask.queued.pluck(:endpoint)).to contain_exactly("business_data/google/extended_reviews/task_get", "business_data/google/reviews/task_get")
      facts = Market::SearchSnapshot.find_by!(kind: "keyword_facts").data
      expect(facts).to include("area" => "Springfield,Illinois,United States")
      expect(facts["keywords"]["emergency plumber"]).to include("local_volume" => 90, "local_cpc" => 14.0, "volume" => 880)

      expect(Market::QueuedTask.fetch_ready!(api: fake)).to eq(2)
      expect(Market::QueuedTask.queued.first.attempts).to eq(1)

      allow(Ai).to receive(:structured).and_return("sites" => [{"key" => "site", "praise" => ["fair prices"], "complaints" => ["slow callbacks"]},
        {"key" => "competitor:#{rival.id}", "praise" => ["fast"], "complaints" => []}], "advice" => "Call back within the hour.")
      done = api
      expect(Market::QueuedTask.fetch_ready!(api: done)).to eq(0)
      own = Market::SearchSnapshot.find_by!(kind: "reviews", competitor_id: nil).data
      expect(own).to include("rating" => 4.1, "themes" => {"praise" => ["fair prices"], "complaints" => ["slow callbacks"]}, "advice" => "Call back within the hour.")
      expect(Market::Finding.pluck(:kind)).to include("reviews_unanswered", "review_pace", "review_complaints", "links_falling", "link_gap")
      expect(Market::Workup::Brief.new("visibility:own").to_s).to include("praise fair prices", "springfieldchamber.example")
    end

    it "gives up on a queued task DataForSEO never finishes, and keeps one that failed" do
      task = Market::QueuedTask.create!(kind: "reviews", task_id: "t1", endpoint: "business_data/google/reviews/task_get", posted_at: 7.hours.ago)
      Market::QueuedTask.fetch_ready!(api: api(ai: {reviews_pending: true}))
      expect(task.reload).to have_attributes(state: "failed", error: a_string_including("hadn't done it"))
    end
  end
end
