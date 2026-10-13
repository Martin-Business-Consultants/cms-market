# frozen_string_literal: true

module Market
  module Search
    class Api
      # DataForSEO's Backlinks API (docs.dataforseo.com/v3/backlinks, a subscription of its own;
      # Live only, about $0.02 a request plus a little a row): each site's link profile, and for the
      # site itself who links to it, what's been won and lost, links to pages that no longer exist,
      # the words they link with, its most-linked pages, and the sites with a profile like its own.
      # Ranks are out of 100, the same scale as the history.
      module Links
        CHANGES_DAYS = 90
        SPAMMY = 60

        # A site's link profile (Backlinks summary): linking sites and pages, how many follow, rank,
        # spam score, links to missing pages, and where the links come from.
        def backlinks(domain)
          task = {target: domain, include_subdomains: true, rank_scale: "one_hundred", internal_list_limit: 8}
          result = @client.post("backlinks/summary/live", task, target: domain, ceiling: CEILINGS[:backlinks]).first || {}
          figures = result.slice("rank", "backlinks", "referring_domains", "referring_domains_nofollow", "referring_main_domains", "referring_pages",
            "referring_ips", "referring_subnets", "broken_backlinks", "broken_pages", "backlinks_spam_score", "crawled_pages").transform_values(&:to_i)
          figures.merge("first_seen" => result["first_seen"].to_s.first(10).presence, "spam_score" => result.dig("info", "target_spam_score"),
            "tlds" => top(result["referring_links_tld"]), "types" => top(result["referring_links_types"]), "attributes" => top(result["referring_links_attributes"]),
            "countries" => top(result["referring_links_countries"].to_h.reject { |country, _| country.blank? }),
            "platforms" => top(result["referring_links_platform_types"])).compact
        end

        # The sites linking to `domain`, highest ranked first (Backlinks referring domains).
        def referring_domains(domain)
          task = {target: domain, limit: 100, order_by: ["rank,desc"], rank_scale: "one_hundred", include_subdomains: true, exclude_internal_backlinks: true}
          result = @client.post("backlinks/referring_domains/live", task, target: domain, ceiling: CEILINGS[:referring_domains]).first || {}
          {"total" => result["total_count"].to_i,
           "sites" => Array(result["items"]).filter_map do |item|
             next if item["domain"].blank?

             links = item["backlinks"].to_i
             nofollow = item.dig("referring_links_attributes", "nofollow").to_i
             {"domain" => item["domain"], "rank" => item["rank"].to_i, "links" => links, "follow" => links > nofollow,
              "spam" => item["backlinks_spam_score"].to_i, "first_seen" => item["first_seen"].to_s.first(10).presence}.compact
           end}
        end

        # The words other sites link to `domain` with (Backlinks anchors), most used first.
        def anchors(domain)
          task = {target: domain, limit: 50, order_by: ["referring_domains,desc"], include_subdomains: true}
          result = @client.post("backlinks/anchors/live", task, target: domain, ceiling: CEILINGS[:anchors]).first || {}
          {"total" => result["total_count"].to_i,
           "anchors" => Array(result["items"]).map { {"anchor" => it["anchor"].to_s.strip.truncate(120), "sites" => it["referring_domains"].to_i, "links" => it["backlinks"].to_i} }}
        end

        # Links won and lost in the last 90 days (Backlinks backlinks, live and lost, one a linking site), best first.
        def link_changes(domain)
          since = CHANGES_DAYS.days.ago.utc.strftime("%Y-%m-%d %H:%M:%S +00:00")
          task = {target: domain, mode: "one_per_domain", backlinks_status_type: "all", limit: 200, rank_scale: "one_hundred",
                  filters: [["first_seen", ">", since], "or", ["is_lost", "=", true]], order_by: ["domain_from_rank,desc"]}
          result = @client.post("backlinks/backlinks/live", task, target: domain, ceiling: CEILINGS[:link_changes]).first || {}
          rows = Array(result["items"]).map { link_row(it) }
          won = rows.reject { it["lost"] }
          lost = rows.select { it["lost"] && (it["last_seen"].blank? || it["last_seen"] >= CHANGES_DAYS.days.ago.to_date.iso8601) }
          {"days" => CHANGES_DAYS, "won" => won.first(50), "lost" => lost.first(50), "won_count" => won.size, "lost_count" => lost.size}
        end

        # Live links to pages on `domain` that answer an error (Backlinks backlinks, is_broken): links to win back with a redirect.
        def broken_links(domain)
          task = {target: domain, backlinks_status_type: "live", limit: 300, rank_scale: "one_hundred", filters: [["is_broken", "=", true]], order_by: ["domain_from_rank,desc"]}
          result = @client.post("backlinks/backlinks/live", task, target: domain, ceiling: CEILINGS[:broken_links]).first || {}
          pages = Array(result["items"]).map { link_row(it) }.group_by { it["url_to"] }.map do |url, links|
            {"url" => url, "path" => path_of(url), "status" => links.first["status"], "sites" => links.map { it["domain"] }.uniq.size,
             "best_rank" => links.map { it["rank"].to_i }.max, "links" => links.first(8).map { it.slice("domain", "url_from", "anchor", "rank", "follow") }}
          end
          {"total" => result["total_count"].to_i, "pages" => pages.sort_by { [-it["sites"], -it["best_rank"]] }.first(40)}
        end

        # A site's pages with the most sites linking to them (Backlinks domain pages summary): what's worth linking to.
        def linked_pages(domain)
          task = {target: domain, limit: 15, order_by: ["referring_domains,desc"], rank_scale: "one_hundred", include_subdomains: true}
          result = @client.post("backlinks/domain_pages_summary/live", task, target: domain, ceiling: CEILINGS[:linked_pages]).first || {}
          {"pages" => Array(result["items"]).filter_map do |item|
            {"url" => item["url"], "sites" => item["referring_domains"].to_i, "links" => item["backlinks"].to_i, "rank" => item["rank"].to_i} if item["url"].present?
          end}
        end

        # Sites whose links overlap the site's most (Backlinks competitors; huge sites left out): who competes for the same links.
        def link_competitors(domain)
          task = {target: domain, limit: 25, rank_scale: "one_hundred", exclude_large_domains: true, main_domain: true, order_by: ["intersections,desc"]}
          result = @client.post("backlinks/competitors/live", task, target: domain, ceiling: CEILINGS[:link_competitors]).first || {}
          {"sites" => Array(result["items"]).filter_map do |item|
            found = Market::Probe.normalize(item["target"].to_s)
            {"domain" => found, "rank" => item["rank"].to_i, "shared" => item["intersections"].to_i} if found.present? && found != Market::Probe.normalize(domain)
          end}
        end

        private

        def link_row(item)
          {"domain" => item["domain_from"], "url_from" => item["url_from"], "url_to" => item["url_to"], "anchor" => item["anchor"].to_s.strip.truncate(120).presence,
           "rank" => item["domain_from_rank"].to_i, "follow" => item["dofollow"] == true, "lost" => item["is_lost"] == true, "status" => item["url_to_status_code"],
           "first_seen" => item["first_seen"].to_s.first(10).presence, "last_seen" => item["last_seen"].to_s.first(10).presence,
           "spam" => item["backlink_spam_score"].to_i}.compact
        end

        def path_of(url)
          URI.parse(url.to_s).path.presence || "/"
        rescue URI::InvalidURIError
          url.to_s
        end

        def top(counts, size = 6) = counts.to_h.transform_values(&:to_i).reject { |_, count| count.zero? }.sort_by { -it[1] }.first(size).to_h.presence
      end
    end
  end
end
