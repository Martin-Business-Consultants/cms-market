# frozen_string_literal: true

module Market
  module Search
    # The DataForSEO calls Market makes, each answering a compact Hash of what's worth keeping
    # (never the raw response). Labs data is country-wide (Market::Settings#country); a ranking check is
    # for the place a client's customers search from. `CEILINGS` are the most each call is
    # allowed to cost, for the budget check: generous on purpose, the ledger keeps what it did.
    class Api
      CEILINGS = {overview: 0.05, keywords: 0.25, competitors: 0.10, backlinks: 0.10, ranking: 0.02, maps: 0.02}.freeze
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
      # "Grand Rapids,Michigan,United States"): who's where in the organic results, and what
      # else is on the page (a map pack, ads, questions).
      # `location` is a DataForSEO location name, or [lat, lng] to search from that point.
      def ranking(keyword, location:)
        where = location.is_a?(Array) ? {location_coordinate: "#{location[0]},#{location[1]},200"} : {location_name: location}
        task = {keyword: keyword, **where, language_code: @setting.language_code, depth: RANKING_DEPTH}
        result = @client.post("serp/google/organic/live/regular", task, target: keyword, ceiling: CEILINGS[:ranking]).first || {}
        {"results" => Array(result["items"]).select { it["type"] == "organic" }.map do |item|
            {"position" => item["rank_group"], "domain" => Market::Probe.normalize(item["domain"]), "url" => item["url"], "title" => item["title"].to_s.truncate(120)}
          end,
          "features" => Array(result["item_types"]) - ["organic"]}
      end

      # Google Maps' results for one search from one point: who's where, with their rating.
      def maps(keyword, lat:, lng:, zoom:)
        task = {keyword: keyword, location_coordinate: "#{lat},#{lng},#{zoom}z", language_code: @setting.language_code, depth: Market::LocalScan::DEPTH}
        result = @client.post("serp/google/maps/live/advanced", task, target: keyword, ceiling: CEILINGS[:maps]).first || {}
        Array(result["items"]).select { it["type"] == "maps_search" }.map do |item|
          {"position" => item["rank_group"], "title" => item["title"].to_s.truncate(120), "domain" => Market::Probe.normalize(item["domain"]),
           "rating" => item.dig("rating", "value"), "reviews" => item.dig("rating", "votes_count"), "category" => item["category"]}.compact
        end
      end

      private

      def labs_task(**fields) = {location_name: @setting.country, language_code: @setting.language_code, **fields}
    end
  end
end
