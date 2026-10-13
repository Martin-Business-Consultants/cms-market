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

  # A geocoder answering one place for every ZIP.
  module FakeGeocoder
    def self.locate(zip, country: "us") = {lat: 42.9632, lng: -85.6528, place: "#{zip}, Grand Rapids, Michigan, United States"}
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

    def initialize(traffic: {}, keywords: {}, competitors: [], rankings: {}, failures: {}, maps: ->(_keyword, _lat, _lng) { [] }, ai: {})
      @traffic, @keywords, @competitors, @rankings, @failures, @maps, @ai = traffic, keywords, competitors, rankings, failures, maps, ai
      @calls = []
    end

    def overview(domain) = answer("overview:#{domain}") { {"organic_keywords" => @keywords.fetch(domain, []).size, "organic_traffic" => @traffic.fetch(domain, 100), "top_3" => 1, "top_10" => 4, "paid_keywords" => 0} }
    def keywords(domain) = answer("keywords:#{domain}") { {"total" => @keywords.fetch(domain, []).size, "keywords" => @keywords.fetch(domain, [])} }
    def competitors(domain) = answer("competitors:#{domain}") { {"competitors" => @competitors} }
    def backlinks(domain) = answer("backlinks:#{domain}") { {"referring_domains" => 10} }
    def ranking(keyword, location:, ai_overview: false)
      answer("ranking:#{keyword}") do
        {"results" => @rankings.fetch(keyword, []), "features" => ["local_pack"], "location" => location, "questions" => ["How much does a plumber cost?"],
         "local_pack" => [{"title" => "Rival Plumbing", "domain" => "rival.example", "rating" => 4.8}], "ai_overview" => (ai_overview ? @ai.dig(keyword, "google_ai_overview") : nil)}
      end
    end

    def maps(keyword, lat:, lng:, zoom:) = answer("maps:#{keyword}") { @maps.call(keyword, lat, lng) }
    def ai_overview_keywords(domain) = answer("ai_overview:#{domain}") { {"total" => 3, "keywords" => [{"keyword" => "plumber near me", "volume" => 500}]} }
    def ai_mode(keyword, location:) = answer("ai_mode:#{keyword}") { @ai.dig(keyword, "google_ai_mode") || {"text" => "", "sources" => []} }
    def llm_scraper(platform, keyword) = answer("#{platform}:#{keyword}") { @ai.dig(keyword, platform) || {"text" => "", "sources" => []} }
    def llm_response(platform, prompt, model:, city: nil) = answer("#{platform}:#{prompt.split(" — ").first}") { (@ai.dig(prompt.split(" — ").first, platform) || {"text" => "", "sources" => []}).merge("model" => model) }
    def models(platform) = [{"model_name" => (platform == "claude") ? "claude-sonnet-9" : "sonar", "web_search_supported" => true}]
    def ai_mentions(sites, platform:) = answer("ai_mentions:#{platform}") { sites.keys.each_with_index.to_h { |key, index| [key, {"mentions" => (key == "site") ? 1 : 12 + index, "ai_search_volume" => 900}] } }
    def ai_answers(domain, platform:) = answer("ai_answers:#{platform}") { [{"platform" => platform, "question" => "Best plumber in Springfield?", "answer" => "Rival Plumbing.", "sources" => ["yelp.com"]}] }
    def ai_volume(keywords) = answer("ai_volume") { keywords.to_h { [it, 40] } }
    def keyword_facts(keywords) = answer("keyword_facts") { keywords.to_h { [it, {"volume" => 880, "difficulty" => 22, "intent" => "commercial", "cpc" => 12.5}] } }
    def serp_competitors(keywords) = answer("serp_competitors") { {"sites" => [{"domain" => "rival.example", "visibility" => 0.4, "keywords" => 2, "average_position" => 2.0}]} }
    def business_profile(cid) = answer("business_profile:#{cid}") { {"title" => "Acme", "claimed" => false, "photos" => 2, "rating" => 4.1, "reviews" => 9, "hours" => false, "description" => true, "cid" => cid} }
    def site_health(url) = answer("site_health") { {"url" => url, "onpage_score" => 71, "lighthouse" => {"performance" => 38, "seo" => 92}, "issues" => ["no_image_alt"]} }
    def bing(keyword) = answer("bing:#{keyword}") { @ai.dig(keyword, "bing_copilot") || {"text" => "", "sources" => []} }
    def content_ideas(keywords) = answer("content_ideas") { {"ideas" => [{"keyword" => "how much does a plumber cost", "volume" => 1300, "difficulty" => 18, "question" => true},
        {"keyword" => "burst pipe repair", "volume" => 480, "difficulty" => 25, "peak" => {"month" => (Date.current.month + 1) % 12 + 1, "lift" => 140}}]} }
    def ai_topics(keywords) = answer("ai_topics") { {"domains" => [{"domain" => "yelp.com", "mentions" => 40}], "pages" => [{"page" => "https://yelp.com/best-plumbers", "mentions" => 12}]} }
    def ai_history(domain) = answer("ai_history:#{domain}") { {"months" => [{"month" => "2026-09", "mentions" => 2}, {"month" => "2026-10", "mentions" => 3}]} }
    def rank_history(domain) = answer("rank_history:#{domain}") { {"months" => 12.times.map { |index| {"month" => (11 - index).months.ago.strftime("%Y-%m"), "keywords" => 20 + index, "traffic" => 100 + index * 10, "top_10" => 4} }} }
    def relevant_pages(domain) = answer("relevant_pages:#{domain}") { {"pages" => [{"url" => "https://#{domain}/drains", "traffic" => 300, "keywords" => 25, "top_3" => 4}]} }
    def gbp_qa(cid) = answer("gbp_qa:#{cid}") { {"questions" => [{"question" => "Do you work weekends?", "answers" => 0}], "unanswered" => 1} }

    # Queued checks: each task says what it asks, and its result is what the live call would answer.
    def ranking_task(keyword, location:, ai_overview: false) = {"kind" => "ranking", "keyword" => keyword, "location" => location, "ai_overview" => ai_overview}
    def maps_task(keyword, lat:, lng:, zoom:) = {"kind" => "maps_point", "keyword" => keyword, "lat" => lat, "lng" => lng}
    def ai_mode_task(keyword, location:) = {"kind" => "ai_mode", "keyword" => keyword}
    def llm_scraper_task(platform, keyword) = {"kind" => "llm_scraper", "platform" => platform, "keyword" => keyword}
    def bing_task(keyword) = {"kind" => "bing", "keyword" => keyword}
    def post_reviews_task(cid) = {"kind" => "reviews", "cid" => cid}
    def gbp_posts_task(cid) = {"kind" => "gbp_posts", "cid" => cid}
    def trustpilot_task(domain) = {"kind" => "trustpilot", "domain" => domain}
    def tripadvisor_task(name) = {"kind" => "tripadvisor", "name" => name}

    def queue(kind, base, items, pull:, get: "#{base}/task_get/advanced")
      return [] if items.empty?

      answer("queue:#{kind}:#{items.size}") do
        items.map do |item|
          Market::QueuedTask.create!(kind: kind, task_id: SecureRandom.uuid, endpoint: get, pull: pull, keyword: item[:keyword], competitor: item[:competitor],
            domain: item[:domain], meta: (item[:meta] || {}).merge("task" => item[:task]), posted_at: Time.current)
        end
      end
    end

    def queued_result(task)
      answer("queued_result:#{task.kind}") do
        asked = task.meta["task"].to_h
        case task.kind
        when "reviews"
          raise Market::Search::Client::NotReady.new("DataForSEO 40602: Task In Queue.") if @ai[:reviews_pending]

          own = task.competitor.nil?
          {"rating" => own ? 4.1 : 4.8, "count" => own ? 9 : 400, "reviews" => (own ? 6 : 10).times.map do |index|
            {"text" => own ? "Slow to call back" : "Great", "stars" => own ? 3 : 5, "at" => (own ? index * 40 : index).days.ago.iso8601, "reviewer" => "Pat #{index}", "answered" => own ? index.zero? : true}
          end}
        when "ranking" then quietly { ranking(asked["keyword"], location: asked["location"], ai_overview: asked["ai_overview"]) }
        when "maps_point" then @maps.call(asked["keyword"], asked["lat"], asked["lng"])
        when "ai_mode" then @ai.dig(asked["keyword"], "google_ai_mode") || {"text" => "", "sources" => []}
        when "llm_scraper" then @ai.dig(asked["keyword"], asked["platform"]) || {"text" => "", "sources" => []}
        when "bing" then @ai.dig(asked["keyword"], "bing_copilot") || {"text" => "", "sources" => []}
        when "gbp_posts" then {"posts" => [{"text" => "Spring special", "at" => 3.days.ago.iso8601}], "last_90_days" => task.competitor ? 6 : 0}
        else {"rating" => 4.2, "count" => 12, "reviews" => [{"text" => "Good work", "stars" => 4, "at" => 5.days.ago.iso8601}]}
        end
      end
    end

    def backlink_history(domain)
      answer("backlink_history:#{domain}") { {"months" => 12.times.map { |index| {"date" => (11 - index).months.ago.to_date.iso8601, "referring_domains" => 100 - index * 3, "new_referring_domains" => 1, "lost_referring_domains" => 4, "rank" => 30} }} }
    end

    def link_gap(own, competitors) = answer("link_gap") { {"total" => 2, "sites" => [{"domain" => "springfieldchamber.example", "links_to" => competitors, "rank" => 55}]} }
    def ads_locations(iso) = answer("ads_locations:#{iso}") { [{"location_name" => "Springfield,Illinois,United States", "location_type" => "City"}, {"location_name" => "Springfield,Missouri,United States", "location_type" => "City"}] }
    def local_volume(keywords, area) = answer("local_volume:#{area}") { keywords.to_h { [it, {"volume" => 90, "cpc" => 14.0}] } }
    def web_mentions(name) = answer("web_mentions:#{name}") { {"total" => (name == "Acme Plumbing") ? 4 : 60, "connotations" => {"positive" => 3}, "top_domains" => ["yelp.com"]} }

    private

    # A live answer used for a queued one, not counted as a call.
    def quietly
      calls = @calls.dup
      yield
    ensure
      @calls = calls
    end

    def answer(call)
      @calls << call
      raise @failures[call] if @failures[call]

      yield
    end
  end
end

RSpec.configure { it.include MarketHelpers }
