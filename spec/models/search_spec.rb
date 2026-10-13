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
      expect(fake.calls).to eq(["overview:acme.example", "keywords:acme.example", "overview:rival.example", "keywords:rival.example",
        "competitors:acme.example", "ranking:emergency plumber", "ranking:water heater repair"])
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
      expect(forced.calls.size).to eq(7)
    end

    it "notes a part that fails and carries on" do
      pull.run!(api: api(failures: {"keywords:rival.example" => Market::Search::Client::InvalidError.new("DataForSEO 40501: invalid field")}))

      expect(pull.reload).to have_attributes(state: "partial", notes: ["Couldn't get keywords for rival.example: DataForSEO 40501: invalid field"])
      expect(Market::SearchSnapshot.count).to eq(4)
    end

    it "stops where it is when the budget runs out or the login is wrong, keeping what it got" do
      pull.run!(api: api(failures: {"overview:rival.example" => Market::Search::Client::BudgetError.new("budget has $0.01 left")}))
      expect(pull.reload).to have_attributes(state: "stopped", error: "budget has $0.01 left")
      expect(Market::SearchSnapshot.count).to eq(2)

      other = described_class.create!(force: true)
      other.run!(api: api(failures: {"overview:acme.example" => Market::Search::Client::AuthError.new("DataForSEO 40100: not authorized")}))
      expect(other.reload.state).to eq("stopped")
      expect(Market::Settings.current.last_error).to eq("DataForSEO 40100: not authorized")
    end

    it "says the most it could cost before it runs" do
      expect(described_class.ceiling).to eq((2 * (0.05 + 0.25) + 0.10 + 2 * 0.02).round(2))
    end
  end
end
