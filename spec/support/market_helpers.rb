# frozen_string_literal: true

# What Market's specs share: readings and DataForSEO answers without the network.
module MarketHelpers
  FakeProbe = Struct.new(:domain, :facts)

  def market_facts(domain: "rival.example", pages: 40, posts: 10, tools: %w[google_analytics], title: "Rival Plumbing", locations: 2, recent: 3)
    {"domain" => domain,
     "home_page" => {"title" => title, "headings" => ["Plumbers you can trust"], "platform" => "WordPress", "tools" => tools,
                     "socials" => {"facebook" => "https://facebook.com/rival"}, "schema_types" => ["Plumber"], "words" => 900},
     "sitemap" => {"pages" => pages, "posts" => posts, "locations" => locations, "services" => 6, "posts_last_90_days" => recent, "last_changed" => "2026-10-01"}}
  end

  # A reading of a competitor's website, or the site's own for nil.
  def read_site(competitor = nil, **options)
    domain = competitor ? competitor.domain : Market::Profile.current.domain
    Market::Reading.take(competitor, probe: FakeProbe.new(domain, market_facts(domain: domain, **options)))
  end

  def site_address(url = "https://acme.example") = Setting.set("general", "site_base_url" => url, "title" => "Acme Plumbing")

  def connect_search(budget_cents: 2500, **settings)
    Market::Settings.update({"dataforseo_login" => "api@example.com", "dataforseo_password" => "secret", "monthly_budget_cents" => budget_cents}.merge(settings.stringify_keys))
  end

  def dataforseo(result, code: 20000, message: "Ok.", cost: 0.01, top_code: 20000)
    JSON.generate({"status_code" => top_code, "status_message" => "Ok.", "cost" => cost,
                   "tasks" => [{"status_code" => code, "status_message" => message, "cost" => cost, "result" => result}]})
  end

  # Answers each call in turn ([status, body] or an exception), recording them.
  class FakeTransport
    attr_reader :calls

    def initialize(*answers)
      @answers = answers
      @calls = []
    end

    def call(*arguments)
      @calls << arguments
      answer = @answers.shift or raise "no more answers"
      raise answer if answer.is_a?(Exception)

      answer
    end
  end

  # A Market::Search::Api from per-domain figures, raising what `failures` says for a call.
  class FakeApi
    attr_reader :calls

    def initialize(traffic: {}, keywords: {}, competitors: [], rankings: {}, failures: {})
      @traffic, @keywords, @competitors, @rankings, @failures = traffic, keywords, competitors, rankings, failures
      @calls = []
    end

    def overview(domain) = answer("overview:#{domain}") { {"organic_keywords" => @keywords.fetch(domain, []).size, "organic_traffic" => @traffic.fetch(domain, 100), "top_3" => 1, "top_10" => 4, "paid_keywords" => 0} }
    def keywords(domain) = answer("keywords:#{domain}") { {"total" => @keywords.fetch(domain, []).size, "keywords" => @keywords.fetch(domain, [])} }
    def competitors(domain) = answer("competitors:#{domain}") { {"competitors" => @competitors} }
    def backlinks(domain) = answer("backlinks:#{domain}") { {"referring_domains" => 10} }
    def ranking(keyword, location:) = answer("ranking:#{keyword}") { {"results" => @rankings.fetch(keyword, []), "features" => ["local_pack"]} }

    private

    def answer(call)
      @calls << call
      raise @failures[call] if @failures[call]

      yield
    end
  end
end

RSpec.configure { it.include MarketHelpers }
