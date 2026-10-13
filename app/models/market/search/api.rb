# frozen_string_literal: true

module Market
  module Search
    # The DataForSEO calls Market makes, each answering a compact Hash of what's worth keeping
    # (never the raw response). Labs data is country-wide (Market::Settings#country); a ranking check is
    # for the place a client's customers search from. `CEILINGS` are the most each call is
    # allowed to cost, for the budget check: generous on purpose, the ledger keeps what it did.
    # AI search (docs.dataforseo.com/v3/ai_optimization, /serp/google/ai_mode): Google's AI
    # Overview comes with the results page, AI Mode on its own, ChatGPT and Gemini from their real
    # search answers (LLM Scraper), Perplexity and Claude asked with web search (LLM Responses),
    # and what DataForSEO's database of real AI answers says about each site (LLM Mentions).
    class Api
      CEILINGS = {overview: 0.05, keywords: 0.25, competitors: 0.10, backlinks: 0.10, ranking: 0.02, maps: 0.02,
                  ai_overview: 0.05, ai_mode: 0.01, llm_scraper: 0.01, llm_response: 0.08, ai_mentions: 0.25, ai_answers: 0.15,
                  keyword_facts: 0.15, ai_volume: 0.05, serp_competitors: 0.05, business_profile: 0.01, site_health: 0.02, web_mentions: 0.05,
                  reviews: 0.01, backlink_history: 0.05, link_gap: 0.07, local_volume: 0.1}.freeze
      REVIEWS = 50
      COUNTRY_CODES = {"United States" => "US", "United Kingdom" => "GB", "Canada" => "CA", "Australia" => "AU", "Ireland" => "IE", "New Zealand" => "NZ",
                       "Germany" => "DE", "France" => "FR", "Spain" => "ES", "Italy" => "IT", "Netherlands" => "NL", "Mexico" => "MX", "Brazil" => "BR",
                       "India" => "IN", "South Africa" => "ZA"}.freeze
      RANKING_DEPTH = 30

      def initialize(client:, setting: Market::Settings.current)
        @client = client
        @setting = setting
      end

      # How visible a domain is in search: keywords by position, estimated monthly visits, and
      # the same for paid search.
      def overview(domain)
        result = @client.post("dataforseo_labs/google/domain_rank_overview/live", labs_task(target: domain), target: domain, ceiling: CEILINGS[:overview])
        metrics = Array(result.first&.dig("items")).first&.dig("metrics") || {}
        organic = metrics["organic"] || {}
        paid = metrics["paid"] || {}
        {"organic_keywords" => organic["count"].to_i, "organic_traffic" => organic["etv"].to_f.round,
          "top_3" => organic["pos_1"].to_i + organic["pos_2_3"].to_i, "top_10" => organic["pos_1"].to_i + organic["pos_2_3"].to_i + organic["pos_4_10"].to_i,
          "top_20" => organic.values_at("pos_1", "pos_2_3", "pos_4_10", "pos_11_20").sum(&:to_i),
          "new_keywords" => organic["is_new"].to_i, "lost_keywords" => organic["is_lost"].to_i,
          "paid_keywords" => paid["count"].to_i, "paid_traffic" => paid["etv"].to_f.round, "paid_traffic_value" => paid["estimated_paid_traffic_cost"].to_f.round}
      end

      # The keywords a domain ranks in the top 20 for, by search volume.
      def keywords(domain)
        task = labs_task(target: domain, limit: @setting.keyword_limit, item_types: ["organic"],
          filters: ["ranked_serp_element.serp_item.rank_group", "<=", 20], order_by: ["keyword_data.keyword_info.search_volume,desc"])
        result = @client.post("dataforseo_labs/google/ranked_keywords/live", task, target: domain, ceiling: CEILINGS[:keywords]).first || {}
        {"total" => result["total_count"].to_i,
          "keywords" => Array(result["items"]).filter_map do |item|
            data = item["keyword_data"] || {}
            serp = item.dig("ranked_serp_element", "serp_item") || {}
            next if data["keyword"].blank?

            {"keyword" => data["keyword"], "volume" => data.dig("keyword_info", "search_volume").to_i, "cpc" => data.dig("keyword_info", "cpc")&.to_f&.round(2),
              "difficulty" => data.dig("keyword_properties", "keyword_difficulty"), "intent" => data.dig("search_intent_info", "main_intent"),
              "position" => serp["rank_group"], "url" => serp["url"], "traffic" => serp["etv"].to_f.round(1)}.compact
          end}
      end

      # The domains that rank for the most of the same keywords.
      def competitors(domain)
        task = labs_task(target: domain, limit: 20, exclude_top_domains: true, item_types: ["organic"])
        result = @client.post("dataforseo_labs/google/competitors_domain/live", task, target: domain, ceiling: CEILINGS[:competitors]).first || {}
        {"competitors" => Array(result["items"]).filter_map do |item|
            next if item["domain"].blank? || Market::Probe.normalize(item["domain"]) == Market::Probe.normalize(domain)

            {"domain" => Market::Probe.normalize(item["domain"]), "shared_keywords" => item["intersections"].to_i, "average_position" => item["avg_position"]&.to_f&.round(1),
              "organic_traffic" => item.dig("full_domain_metrics", "organic", "etv").to_f.round, "organic_keywords" => item.dig("full_domain_metrics", "organic", "count").to_i}
          end}
      end

      # Links from elsewhere (Backlinks API, a separate DataForSEO subscription).
      def backlinks(domain)
        result = @client.post("backlinks/summary/live", {target: domain, include_subdomains: true}, target: domain, ceiling: CEILINGS[:backlinks]).first || {}
        result.slice("rank", "backlinks", "referring_domains", "referring_main_domains", "broken_backlinks", "backlinks_spam_score").transform_values { it.is_a?(Numeric) ? it : it.to_i }
      end

      # Google's results for one keyword, searched from `location` (a DataForSEO location name,
      # "Grand Rapids,Michigan,United States", or [lat, lng] to search from that point): who's where
      # in the organic results, what else is on the page, the map pack, the questions people also
      # ask, and the AI Overview with the sources it cites (loaded when Google loads it later).
      def ranking(keyword, location:, ai_overview: false)
        task = {keyword: keyword, **where(location, radius: true), language_code: @setting.language_code, depth: RANKING_DEPTH}
        task[:load_async_ai_overview] = true if ai_overview
        result = @client.post("serp/google/organic/live/advanced", task, target: keyword, ceiling: CEILINGS[:ranking] + (ai_overview ? 0.005 : 0)).first || {}
        items = Array(result["items"])
        overview = items.find { it["type"] == "ai_overview" }
        {"results" => items.select { it["type"] == "organic" }.map do |item|
            {"position" => item["rank_group"], "domain" => Market::Probe.normalize(item["domain"]), "url" => item["url"], "title" => item["title"].to_s.truncate(120)}
          end,
          "features" => Array(result["item_types"]) - ["organic"],
          "local_pack" => items.select { it["type"] == "local_pack" }.map do |item|
            {"title" => item["title"].to_s.truncate(120), "domain" => Market::Probe.normalize(item["domain"]), "rating" => item.dig("rating", "value"),
             "reviews" => item.dig("rating", "votes_count"), "cid" => item["cid"]}.compact
          end,
          "questions" => items.select { it["type"] == "people_also_ask" }.flat_map { Array(it["items"]).map { |question| question["title"] } }.compact_blank.first(8),
          "ai_overview" => overview && {"text" => overview["markdown"].presence || Array(overview["items"]).map { it["markdown"] || it["text"] }.compact.join("\n\n"),
                                        "sources" => Array(overview["references"]).map { {"domain" => it["domain"], "url" => it["url"], "title" => it["title"]} }}}
      end

      # Google Maps' results for one search from one point: who's where, with their rating and Google's ids.
      def maps(keyword, lat:, lng:, zoom:)
        task = {keyword: keyword, location_coordinate: "#{lat},#{lng},#{zoom}z", language_code: @setting.language_code, depth: Market::LocalScan::DEPTH}
        result = @client.post("serp/google/maps/live/advanced", task, target: keyword, ceiling: CEILINGS[:maps]).first || {}
        Array(result["items"]).select { it["type"] == "maps_search" }.map do |item|
          {"position" => item["rank_group"], "title" => item["title"].to_s.truncate(120), "domain" => Market::Probe.normalize(item["domain"]),
           "rating" => item.dig("rating", "value"), "reviews" => item.dig("rating", "votes_count"), "category" => item["category"], "cid" => item["cid"]}.compact
        end
      end

      # AI search ----------------------------------------------------------------------------

      # Google's AI Mode answer to a search, with the sources it cites.
      def ai_mode(keyword, location:)
        where = location.is_a?(Array) ? {location_coordinate: "#{location[0]},#{location[1]},11z"} : {location_name: location}
        task = {keyword: keyword, **where, language_code: @setting.language_code}
        result = @client.post("serp/google/ai_mode/live/advanced", task, target: keyword, ceiling: CEILINGS[:ai_mode]).first || {}
        element = Array(result["items"]).find { it["type"].to_s.start_with?("ai_overview") } || {}
        {"text" => element["markdown"].presence || Array(element["items"]).map { it["markdown"] || it["text"] }.compact.join("\n\n"),
         "sources" => Array(element["references"] || result["references"]).map { {"domain" => it["domain"], "url" => it["url"], "title" => it["title"]} }}
      end

      # ChatGPT's or Gemini's real search answer (the LLM Scraper): its text, the sources it cites,
      # and the businesses it shows as cards (ChatGPT's local businesses and brands).
      def llm_scraper(platform, keyword)
        task = {keyword: keyword, location_name: @setting.country, language_code: @setting.language_code}
        task[:force_web_search] = true if platform == "chat_gpt"
        result = @client.post("ai_optimization/#{platform}/llm_scraper/live/advanced", task, target: keyword, ceiling: CEILINGS[:llm_scraper]).first || {}
        items = Array(result["items"])
        businesses = items.select { it["type"] == "chat_gpt_local_businesses" }.flat_map { Array(it["items"]) }
          .map { {"title" => it["title"], "domain" => it["domain"], "url" => it["url"], "rating" => it.dig("rating", "value"), "reviews" => it.dig("rating", "votes_count")} } +
          Array(result["brand_entities"]).map { {"title" => it["title"], "domain" => Array(it["urls"]).first&.dig("domain")} }
        {"text" => result["markdown"].presence || items.filter_map { it["markdown"] || it["text"] }.join("\n\n"), "model" => result["model"],
         "sources" => Array(result["sources"]).map { {"domain" => it["domain"], "url" => it["url"], "title" => it["title"]} }, "businesses" => businesses}
      end

      # An answer from Perplexity or Claude, asked with web search on, from where customers are:
      # its text and the sources it cites. `model` from #models.
      def llm_response(platform, prompt, model:, city: nil)
        task = {user_prompt: prompt.truncate(500), model_name: model, max_output_tokens: 1200}
        country = COUNTRY_CODES[@setting.country]
        if platform == "perplexity"
          task[:web_search_country_iso_code] = country if country
        else
          task.merge!(web_search: true, web_search_country_iso_code: country, web_search_city: city).compact!
        end
        result = @client.post("ai_optimization/#{platform}/llm_responses/live", task, target: prompt.truncate(80), ceiling: CEILINGS[:llm_response]).first || {}
        sections = Array(result["items"]).select { it["type"] == "message" }.flat_map { Array(it["sections"]) }
        {"text" => sections.map { it["text"] }.join("\n\n"), "model" => result["model_name"],
         "sources" => sections.flat_map { Array(it["annotations"]) }.map { {"url" => it["url"], "title" => it["title"]} }}
      end

      # The models a platform answers with (free): [{"model_name", "web_search_supported", "reasoning"}].
      def models(platform) = Array(@client.get("ai_optimization/#{platform}/llm_responses/models"))

      # How often AI answers mention each site, from DataForSEO's database of real ChatGPT and
      # Google AI Overview answers (LLM Mentions): {site key => {"mentions", "ai_search_volume"}}.
      # `sites` is {key => domain}; ChatGPT's answers are only for the United States in English.
      def ai_mentions(sites, platform:)
        targets = sites.map { |key, domain| {key: key, target: [{domain: domain, search_filter: "include"}]} }
        task = {targets: targets, platform: platform, location_code: (platform == "chat_gpt") ? 2840 : nil, location_name: (platform == "chat_gpt") ? nil : @setting.country,
                language_code: @setting.language_code, internal_list_limit: 10}.compact
        result = @client.post("ai_optimization/llm_mentions/multi_target_metrics/live", task, target: sites.values.first, ceiling: CEILINGS[:ai_mentions]).first || {}
        Array(result["items"]).to_h do |item|
          aggregated = item["aggregated_metrics"] || item
          [item["key"], {"mentions" => item.dig("total", "mentions").to_i, "ai_search_volume" => item.dig("total", "ai_search_volume").to_i,
                         "sources" => Array(aggregated["sources_domain"]).first(10).map { {"domain" => it["key"], "mentions" => it["mentions"].to_i} }}]
        end
      end

      # The questions AI answered that mention a site, with the answer and what it cited (LLM Mentions).
      def ai_answers(domain, platform:)
        task = {target: [{domain: domain, search_filter: "include"}], platform: platform, language_code: @setting.language_code, limit: 10,
                location_code: (platform == "chat_gpt") ? 2840 : nil, location_name: (platform == "chat_gpt") ? nil : @setting.country}.compact
        result = @client.post("ai_optimization/llm_mentions/search_mentions/live", task, target: domain, ceiling: CEILINGS[:ai_answers]).first || {}
        Array(result["items"]).map do |item|
          {"platform" => platform, "question" => item["question"].to_s.truncate(300), "answer" => item["answer"].to_s.truncate(800),
           "ai_search_volume" => item["ai_search_volume"].to_i, "sources" => Array(item["sources"]).first(6).map { it["domain"] }.compact.uniq,
           "at" => item["last_response_at"]}
        end
      end

      # Searches people make in AI assistants, by keyword (AI Keyword Data): {keyword => monthly AI searches}.
      def ai_volume(keywords)
        task = {keywords: keywords.first(1000), location_name: @setting.country, language_code: @setting.language_code}
        result = @client.post("ai_optimization/ai_keyword_data/keywords_search_volume/live", task, target: "#{keywords.size} keywords", ceiling: CEILINGS[:ai_volume]).first || {}
        Array(result["items"]).to_h { [it["keyword"], it["ai_search_volume"].to_i] }
      end

      # Keywords ----------------------------------------------------------------------------

      # What each tracked search is worth: Google's monthly searches, cost per click, how hard it
      # is to rank for, what the searcher wants, and the year's trend (Labs keyword overview).
      def keyword_facts(keywords)
        result = @client.post("dataforseo_labs/google/keyword_overview/live", labs_task(keywords: keywords.first(700)), target: "#{keywords.size} keywords",
          ceiling: CEILINGS[:keyword_facts]).first || {}
        Array(result["items"]).to_h do |item|
          info = item["keyword_info"] || {}
          [item["keyword"], {"volume" => info["search_volume"].to_i, "cpc" => info["cpc"]&.to_f&.round(2), "competition" => info["competition_level"],
                             "difficulty" => item.dig("keyword_properties", "keyword_difficulty"), "intent" => item.dig("search_intent_info", "main_intent"),
                             "trend" => info.dig("search_volume_trend", "yearly")}.compact]
        end
      end

      # The sites that win the tracked searches, by how visible they are across them (Labs SERP competitors).
      def serp_competitors(keywords)
        task = labs_task(keywords: keywords.first(200), limit: 20, item_types: ["organic", "local_pack"])
        result = @client.post("dataforseo_labs/google/serp_competitors/live", task, target: "#{keywords.size} keywords", ceiling: CEILINGS[:serp_competitors]).first || {}
        {"sites" => Array(result["items"]).filter_map do |item|
          domain = Market::Probe.normalize(item["domain"])
          {"domain" => domain, "visibility" => item["visibility"].to_f.round(3), "average_position" => item["avg_position"]&.to_f&.round(1),
           "keywords" => item["keywords_count"].to_i, "traffic" => item["etv"].to_f.round} if domain
        end}
      end

      # The searches a domain is cited for in Google's AI Overviews, from Labs' database.
      def ai_overview_keywords(domain)
        task = labs_task(target: domain, limit: 100, item_types: ["ai_overview_reference"], order_by: ["keyword_data.keyword_info.search_volume,desc"])
        result = @client.post("dataforseo_labs/google/ranked_keywords/live", task, target: domain, ceiling: CEILINGS[:ai_overview]).first || {}
        {"total" => result["total_count"].to_i,
         "keywords" => Array(result["items"]).filter_map do |item|
           keyword = item.dig("keyword_data", "keyword") or next
           {"keyword" => keyword, "volume" => item.dig("keyword_data", "keyword_info", "search_volume").to_i, "url" => item.dig("ranked_serp_element", "serp_item", "url")}.compact
         end}
      end

      # The business ---------------------------------------------------------------------------

      # A Google Business Profile, by its Maps id: what's on it, as a customer sees it.
      def business_profile(cid)
        task = {keyword: "cid:#{cid}", location_name: @setting.country, language_code: @setting.language_code}
        result = @client.post("business_data/google/my_business_info/live", task, target: "cid:#{cid}", ceiling: CEILINGS[:business_profile]).first || {}
        item = Array(result["items"]).first || {}
        {"title" => item["title"], "category" => item["category"], "additional_categories" => Array(item["additional_categories"]),
         "rating" => item.dig("rating", "value"), "reviews" => item.dig("rating", "votes_count").to_i, "rating_distribution" => item["rating_distribution"],
         "claimed" => item["is_claimed"], "photos" => item["total_photos"].to_i, "phone" => item["phone"], "website" => item["url"],
         "hours" => item.dig("work_time", "work_hours", "timetable").present?, "description" => item["description"].present?,
         "attributes" => Array(item.dig("attributes", "available_attributes")&.values).flatten.size,
         "topics" => item["place_topics"].to_h.sort_by { -it[1].to_i }.first(8).map(&:first),
         "also_searched" => Array(item["people_also_search"]).first(6).map { it["title"] }.compact, "cid" => cid.to_s}.compact
      end

      # The site's home page, checked as Google renders it (On-Page instant pages, structured data
      # validated) and by Lighthouse on a phone: speed, SEO, accessibility, best practice.
      def site_health(url)
        page = @client.post("on_page/instant_pages", {url: url, enable_browser_rendering: true, validate_micromarkup: true}, target: url, ceiling: CEILINGS[:site_health]).first || {}
        item = Array(page["items"]).first || {}
        meta = item["meta"] || {}
        checks = item["checks"].to_h.select { |_, failed| failed == true }.keys
        lighthouse = begin
          Array(@client.post("on_page/lighthouse/live/json", {url: url, for_mobile: true}, target: url, ceiling: CEILINGS[:site_health])).first || {}
        rescue Client::InvalidError, Client::UnavailableError
          {}
        end
        scores = lighthouse["categories"].to_h.to_h { |key, category| [key, (category["score"].to_f * 100).round] }
        {"url" => url, "onpage_score" => item["onpage_score"]&.round, "title" => meta["title"], "title_length" => meta["title_length"],
         "description_length" => meta["description_length"], "h1" => Array(meta.dig("htags", "h1")).first, "words" => meta.dig("content", "plain_text_word_count"),
         "issues" => checks.first(20), "lcp_ms" => item.dig("page_timing", "largest_contentful_paint")&.round, "lighthouse" => scores}.compact
      end

      # Google reviews (only queued, Standard method): sets the task for a business by its Maps id,
      # the newest first; its result comes with #queued_result. The site's own as Extended Reviews,
      # which also carries the other sites' reviews Google shows (Yelp, Facebook…).
      def post_reviews(cid, extended: false)
        endpoint = extended ? "business_data/google/extended_reviews" : "business_data/google/reviews"
        task = {cid: cid.to_s, location_name: @setting.country, language_code: @setting.language_code, depth: REVIEWS, sort_by: "newest"}
        [@client.post_task("#{endpoint}/task_post", task, target: "cid:#{cid}", ceiling: CEILINGS[:reviews]), "#{endpoint}/task_get"]
      end

      # A queued task's result, by its kind; NotReady until DataForSEO has done it.
      def queued_result(task)
        result = @client.task_result("#{task.endpoint}/#{task.task_id}").first || {}
        case task.kind
        when "reviews" then reviews_from(result)
        end
      end

      # A site's links month by month for the last year (Backlinks history): rank, linking sites, new and lost.
      def backlink_history(domain)
        task = {target: domain, date_from: 12.months.ago.to_date.beginning_of_month.iso8601, rank_scale: "one_hundred"}
        result = @client.post("backlinks/history/live", task, target: domain, ceiling: CEILINGS[:backlink_history]).first || {}
        {"months" => Array(result["items"]).map do |item|
          {"date" => item["date"].to_s.first(10), "rank" => item["rank"].to_i, "backlinks" => item["backlinks"].to_i, "referring_domains" => item["referring_domains"].to_i,
           "new_referring_domains" => item["new_referring_domains"].to_i, "lost_referring_domains" => item["lost_referring_domains"].to_i}
        end.sort_by { it["date"] }}
      end

      # The sites linking to competitors but not to the site (Backlinks domain intersection): where to get links.
      def link_gap(own, competitors)
        targets = competitors.first(20).each_with_index.to_h { |domain, index| [(index + 1).to_s, domain] }
        task = {targets: targets, exclude_targets: [own], intersection_mode: "partial", limit: 40, order_by: ["1.rank,desc"], rank_scale: "one_hundred"}
        result = @client.post("backlinks/domain_intersection/live", task, target: own, ceiling: CEILINGS[:link_gap]).first || {}
        {"total" => result["total_count"].to_i,
         "sites" => Array(result["items"]).filter_map do |item|
           linked = item["domain_intersection"].to_h.compact
           first = linked.values.first or next
           {"domain" => Market::Probe.normalize(first["target"]), "rank" => linked.values.map { it["rank"].to_i }.max,
            "links_to" => linked.keys.map { targets[it] }.compact, "spam" => first["backlinks_spam_score"].to_i}
         end.sort_by { [-it["links_to"].size, -it["rank"]] }}
      end

      # Google Ads' monthly searches and cost per click for the tracked searches in one area (a city,
      # by its Google Ads location name): what they're worth where the business is.
      def local_volume(keywords, location_name)
        task = {keywords: keywords.first(1000), location_name: location_name, language_code: @setting.language_code}
        result = @client.post("keywords_data/google_ads/search_volume/live", task, target: location_name, ceiling: CEILINGS[:local_volume])
        Array(result).to_h { [it["keyword"], {"volume" => it["search_volume"], "cpc" => it["cpc"]&.to_f&.round(2), "competition" => it["competition"]}.compact] }
      end

      # Google Ads' locations in a country (free): [{"location_name", "location_type", "location_code"}].
      def ads_locations(country_iso) = Array(@client.get("keywords_data/google_ads/locations/#{country_iso.downcase}"))

      # The web talking about a business by name (Content Analysis): how often, how warmly, and where.
      def web_mentions(name)
        result = @client.post("content_analysis/summary/live", {keyword: name, internal_list_limit: 8}, target: name, ceiling: CEILINGS[:web_mentions]).first || {}
        {"total" => result["total_count"].to_i, "sentiment" => result["sentiment_connotations"].to_h, "connotations" => result["connotation_types"].to_h,
         "top_domains" => result["top_domains"].to_a.first(8).map { it.is_a?(Hash) ? (it["domain"] || it["key"]) : it }.compact}
      end

      private

      def labs_task(**fields) = {location_name: @setting.country, language_code: @setting.language_code, **fields}

      def reviews_from(result)
        reviews = Array(result["items"]).filter_map do |item|
          next unless item["type"].to_s.include?("review") || item["review_text"] || item["rating"]

          {"text" => item["review_text"].to_s.truncate(1000), "stars" => item.dig("rating", "value")&.to_i, "at" => item["timestamp"], "reviewer" => item["profile_name"],
           "answered" => item["owner_answer"].present?, "source" => item.dig("source", "title") || item["source"]&.then { it.is_a?(String) ? it : nil } || "Google",
           "url" => item["review_url"]}.compact
        end
        {"title" => result["title"], "rating" => result.dig("rating", "value"), "count" => (result["reviews_count"] || result.dig("rating", "votes_count")).to_i,
         "cid" => result["cid"], "reviews" => reviews}
      end

      def where(location, radius: false)
        return {location_name: location} unless location.is_a?(Array)

        {location_coordinate: radius ? "#{location[0]},#{location[1]},200" : "#{location[0]},#{location[1]}"}
      end
    end
  end
end
