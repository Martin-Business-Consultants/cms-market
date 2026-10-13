# frozen_string_literal: true

module Market
  # What the data says about the site's market, as findings (Hashes for Finding.refresh):
  # each with a stable key, a kind, how much it matters, the channel it's about, a title and
  # detail in plain words, the figures behind it (evidence) and where they came from (sources).
  # Reads only what's stored: a handful of queries, no outside calls.
  class Finding::Analysis
    GAP_LIMIT = 10

    def initialize
      @profile = Market::Profile.current
      @competitors = Market::Competitor.ordered.to_a
      @readings = Market::Reading.latest_for(@competitors)
      @own_reading = @profile.domain ? Market::Reading.own_latest : nil
      all = Market::SearchSnapshot.latest_by_site(@competitors.map(&:id))
      @own_search = all.fetch(nil, {})
      @search = @competitors.to_h { [it, all.fetch(it.id, {})] }
      @keywords = Market::Keyword.ordered.to_a
      @rankings = Market::Ranking.latest_for(@keywords)
      @setting = Market::Settings.current
      @name = @profile.business_name
    end

    def findings
      [profile_gaps, no_competitors, *keyword_gaps, ground, *competitor_surges, ranking_drops, outranked, not_ranking, map_pack,
        competitor_ads, location_pages, content_freshness, conversion_tools, unwatched_search_competitors, backlinks_gap,
        *site_changes, stale_site, stale_search].compact
    end

    private

    attr_reader :profile, :competitors, :readings, :own_reading, :search, :own_search, :keywords, :rankings, :setting, :name

    def finding(key, kind, severity, title, detail: nil, channel: nil, evidence: {}, sources: [])
      {key: key, kind: kind, severity: severity, channel: channel, title: title, detail: detail, evidence: evidence, sources: sources.compact}
    end

    def source(record, type)
      return unless record

      {"type" => type, "id" => record.id, "kind" => record.try(:kind), "domain" => record.try(:domain), "at" => (record.try(:taken_at) || record.try(:checked_at))&.iso8601}.compact
    end

    def own_latest(kind) = own_search.dig(kind, 0)
    def own_previous(kind) = own_search.dig(kind, 1)
    def latest(kind, competitor) = search.dig(competitor, kind, 0)
    def previous(kind, competitor) = search.dig(competitor, kind, 1)
    def reading(competitor) = readings[competitor.id]&.then { it if it.read? }
    def possessive(name) = name.end_with?("s") ? "#{name}'" : "#{name}'s"

    # The profile and the competitors ------------------------------------------------------
    def profile_gaps
      return if profile.gaps.empty?

      severity = profile.gaps.any? { it == "industry" || it.start_with?("the site's address") } ? "medium" : "low"
      finding("profile_gaps", "profile_gaps", severity, "Missing from the market profile: #{profile.gaps.to_sentence}",
        detail: "Fill these in (Market › Profile): plans and findings are only as good as what's known.", evidence: {"missing" => profile.gaps})
    end

    def no_competitors
      return if competitors.any?

      finding("no_competitors", "no_competitors", "medium", "No competitors listed for #{name}",
        detail: "Add the businesses they lose customers to (and the one they'd most like to be) so their websites and search are compared.")
    end

    # Search -------------------------------------------------------------------------------
    def keyword_gaps
      own = own_latest("keywords")
      return [] unless own

      mine = Array(own.data["keywords"]).to_h { [it["keyword"], it["position"]] }
      competitors.filter_map do |competitor|
        theirs = latest("keywords", competitor) or next
        gap = Array(theirs.data["keywords"]).select { it["position"].to_i.between?(1, 10) && !mine.key?(it["keyword"]) }
        next if gap.empty?

        volume = gap.sum { it["volume"].to_i }
        severity = volume >= 1000 || gap.size >= 20 ? "high" : (volume >= 100 ? "medium" : "low")
        top = gap.sort_by { -it["volume"].to_i }.first(GAP_LIMIT)
        finding("keyword_gap:#{competitor.domain}", "keyword_gap", severity,
          "#{competitor.name} is on page one for #{gap.size} #{"search".pluralize(gap.size)} #{name} isn't (#{volume} a month)",
          channel: "seo", detail: "Searches they rank in Google's top 10 for, where #{name} isn't in the top 20. Biggest first: #{top.first(3).map { it["keyword"] }.join(", ")}.",
          evidence: {"competitor" => competitor.name, "domain" => competitor.domain, "searches" => gap.size, "monthly_searches" => volume,
                      "keywords" => top.map { {"keyword" => it["keyword"], "volume" => it["volume"].to_i, "their_position" => it["position"], "url" => it["url"]}.compact }},
          sources: [source(own, "search"), source(theirs, "search")])
      end
    end

    def ground
      now, before = own_latest("overview"), own_previous("overview")
      return unless now && before

      was, is = before.data["organic_traffic"].to_i, now.data["organic_traffic"].to_i
      return if was < 50

      change = ((is - was) * 100.0 / was).round
      evidence = {"organic_traffic_before" => was, "organic_traffic_now" => is, "change_percent" => change,
                   "keywords_before" => before.data["organic_keywords"].to_i, "keywords_now" => now.data["organic_keywords"].to_i}
      if change <= -20
        finding("losing_ground", "losing_ground", "high", "#{possessive(name)} search traffic fell #{change.abs}% (#{was} → #{is} visits a month, estimated)",
          channel: "seo", detail: "Between pulls on #{before.taken_at.to_date.to_fs(:long)} and #{now.taken_at.to_date.to_fs(:long)}. Check the keywords lost and the pages that held them.",
          evidence: evidence, sources: [source(before, "search"), source(now, "search")])
      elsif change >= 20
        finding("gaining_ground", "gaining_ground", "info", "#{possessive(name)} search traffic rose #{change}% (#{was} → #{is} visits a month, estimated)",
          channel: "seo", evidence: evidence, sources: [source(before, "search"), source(now, "search")])
      end
    end

    def competitor_surges
      competitors.filter_map do |competitor|
        now, before = latest("overview", competitor), previous("overview", competitor)
        next unless now && before

        was, is = before.data["organic_traffic"].to_i, now.data["organic_traffic"].to_i
        next unless was >= 50 && is - was >= 100 && is >= was * 1.25

        finding("competitor_surge:#{competitor.domain}", "competitor_surge", "medium",
          "#{possessive(competitor.name)} search traffic rose #{((is - was) * 100.0 / was).round}% (#{was} → #{is} a month, estimated)",
          channel: "seo", detail: "See what they added: new pages, posts or keywords (their keywords and site changes).",
          evidence: {"competitor" => competitor.name, "domain" => competitor.domain, "organic_traffic_before" => was, "organic_traffic_now" => is,
                      "new_keywords" => now.data["new_keywords"].to_i},
          sources: [source(before, "search"), source(now, "search")])
      end
    end

    # Tracked keywords ---------------------------------------------------------------------
    def tracked
      @tracked ||= keywords.filter_map { |keyword| [keyword, *rankings[keyword.id]] if rankings[keyword.id]&.first }
    end

    def ranking_drops
      drops = tracked.filter_map do |keyword, now, before|
        next unless before&.position

        is = now.position
        was = before.position
        next unless is.nil? || is - was >= 3 || (was <= 10 && is > 10)

        {"keyword" => keyword.keyword, "was" => was, "now" => is, "ranking" => now.id}
      end
      return if drops.empty?

      severity = drops.any? { it["was"] <= 3 } ? "high" : "medium"
      finding("ranking_drops", "ranking_drops", severity, "#{name} dropped on #{drops.size} tracked #{"search".pluralize(drops.size)}",
        channel: "seo", detail: drops.first(5).map { "“#{it["keyword"]}” #{it["was"]} → #{it["now"] || "out of the top #{Market::Search::Api::RANKING_DEPTH}"}" }.join("; "),
        evidence: {"drops" => drops}, sources: drops.map { {"type" => "ranking", "id" => it["ranking"]} })
    end

    def outranked
      rows = tracked.filter_map do |keyword, now, _|
        mine = now.position
        ahead = competitors.filter_map do |competitor|
          position = now.position_of(competitor.domain)
          {"competitor" => competitor.name, "position" => position} if position && position <= 10 && (mine.nil? || position < mine)
        end
        {"keyword" => keyword.keyword, "yours" => mine, "ahead" => ahead.sort_by { it["position"] }} if ahead.any?
      end
      return if rows.empty?

      counts = rows.flat_map { it["ahead"].map { |row| row["competitor"] } }.tally.sort_by { -it.last }
      finding("outranked", "outranked", rows.size >= tracked.size / 2.0 ? "high" : "medium",
        "Competitors outrank #{name} on #{rows.size} of #{tracked.size} tracked #{"search".pluralize(tracked.size)}",
        channel: "seo", detail: "Most often: #{counts.first(3).map { "#{it.first} (#{it.last})" }.join(", ")}.",
        evidence: {"keywords" => rows.first(20), "by_competitor" => counts.to_h}, sources: tracked.map { source(it[1], "ranking") })
    end

    def not_ranking
      missing = tracked.select { |_, now, _| now.position.nil? }.map { it.first.keyword }
      return if missing.empty?

      finding("not_ranking", "not_ranking", missing.size >= 3 ? "medium" : "low",
        "#{name} isn't in Google's top #{Market::Search::Api::RANKING_DEPTH} for #{missing.size} tracked #{"search".pluralize(missing.size)}",
        channel: "seo", detail: "A page made for each, and links to it, is where to start: #{missing.first(5).join(", ")}.",
        evidence: {"keywords" => missing})
    end

    def map_pack
      local = tracked.select { |_, now, _| Array(now.features).include?("local_pack") }.map { it.first.keyword }
      return if local.empty?

      finding("map_pack", "map_pack", "info", "Google shows a map of local businesses for #{local.size} tracked #{"search".pluralize(local.size)}",
        channel: "local", detail: "Their Google Business Profile (reviews, photos, categories, posts) decides who's in it.", evidence: {"keywords" => local})
    end

    # The websites -------------------------------------------------------------------------
    def competitor_ads
      own_ads = own_reading&.runs?(:google_ads) || own_latest("overview")&.data&.dig("paid_keywords").to_i.positive?
      return if own_ads

      running = competitors.filter_map do |competitor|
        paid = latest("overview", competitor)&.data&.dig("paid_keywords").to_i
        tag = reading(competitor)&.runs?(:google_ads)
        {"competitor" => competitor.name, "paid_keywords" => paid, "google_ads_tag" => tag ? true : false} if paid.positive? || tag
      end
      return if running.empty?

      finding("competitor_ads", "competitor_ads", "medium", "#{running.size} #{"competitor".pluralize(running.size)} #{running.size == 1 ? "runs" : "run"} search ads; #{name} doesn't",
        channel: "paid_search", detail: "#{running.map { it["competitor"] }.to_sentence} buy their way onto the searches #{name} wants.",
        evidence: {"competitors" => running})
    end

    def location_pages
      own = own_reading&.read? ? own_reading.sitemap["locations"].to_i : nil
      return if own.nil? || own >= 2

      ahead = competitors.filter_map { |competitor| reading(competitor)&.sitemap&.dig("locations").to_i.then { |count| {"competitor" => competitor.name, "location_pages" => count} if count >= 5 } }
      return if ahead.empty?

      finding("location_pages", "location_pages", "medium", "Competitors have a page for each place they serve; #{name} has #{own}",
        channel: "local", detail: ahead.map { "#{it["competitor"]}: #{it["location_pages"]}" }.join(", "),
        evidence: {"yours" => own, "competitors" => ahead}, sources: [source(own_reading, "site_reading")])
    end

    def content_freshness
      return unless own_reading&.read? && own_reading.sitemap.key?("posts_last_90_days")

      own = own_reading.sitemap["posts_last_90_days"].to_i
      active = competitors.filter_map { |competitor| reading(competitor)&.sitemap&.dig("posts_last_90_days").to_i.then { |count| {"competitor" => competitor.name, "posts_last_90_days" => count} if count >= 3 } }
      return unless own.zero? && active.any?

      finding("content_freshness", "content_freshness", "medium", "#{name} published nothing in 90 days; #{active.size} #{"competitor".pluralize(active.size)} did",
        channel: "content", detail: active.map { "#{it["competitor"]}: #{it["posts_last_90_days"]} posts" }.join(", "),
        evidence: {"yours" => 0, "competitors" => active}, sources: [source(own_reading, "site_reading")])
    end

    def conversion_tools
      return unless own_reading&.read?

      missing = %w[booking chat call_tracking reviews_widget].filter_map do |tool|
        next if own_reading.runs?(tool)

        users = competitors.select { reading(it)&.runs?(tool) }.map(&:name)
        {"tool" => Market::Probe::TOOLS.dig(tool, 0), "competitors" => users} if users.any? && users.size * 2 >= competitors.size
      end
      return if missing.empty?

      finding("conversion_tools", "conversion_tools", "low", "Competitors' sites have #{missing.map { it["tool"].downcase }.to_sentence}; #{possessive(name)} doesn't",
        channel: "website", detail: missing.map { "#{it["tool"]}: #{it["competitors"].to_sentence}" }.join(". "), evidence: {"missing" => missing},
        sources: [source(own_reading, "site_reading")])
    end

    def unwatched_search_competitors
      found = own_latest("competitors") or return
      watched = competitors.map(&:domain).compact
      unwatched = Array(found.data["competitors"]).reject { |row| watched.any? { row["domain"] == it || row["domain"].to_s.end_with?(".#{it}") } }
                                                   .select { it["shared_keywords"].to_i >= 5 }.first(8)
      return if unwatched.empty?

      finding("unwatched_search_competitors", "unwatched_search_competitors", "medium",
        "#{unwatched.size} #{"site".pluralize(unwatched.size)} compete with #{name} in search but aren't watched",
        channel: "seo", detail: "By keywords shared: #{unwatched.first(4).map { "#{it["domain"]} (#{it["shared_keywords"]})" }.join(", ")}. Watch the ones that are businesses.",
        evidence: {"sites" => unwatched}, sources: [source(found, "search")])
    end

    def backlinks_gap
      own = own_latest("backlinks") or return
      mine = own.data["referring_domains"].to_i
      best = competitors.filter_map { |competitor| latest("backlinks", competitor)&.then { {"competitor" => competitor.name, "referring_domains" => it.data["referring_domains"].to_i} } }
                        .max_by { it["referring_domains"] }
      return unless best && best["referring_domains"] >= [mine * 2, mine + 20].max

      finding("backlinks_gap", "backlinks_gap", "medium", "#{best["competitor"]} has #{best["referring_domains"]} sites linking to it; #{name} has #{mine}",
        channel: "seo", detail: "Links from local and trade sites are much of why a competitor outranks: directories, suppliers, sponsorships, press.",
        evidence: {"yours" => mine, "best" => best}, sources: [source(own, "search")])
    end

    def site_changes
      competitors.filter_map do |competitor|
        snapshot = readings[competitor.id]
        next unless snapshot && snapshot.differences.any? && snapshot.taken_at >= 14.days.ago

        finding("site_changes:#{competitor.domain}", "site_changes", "info", "#{competitor.name} changed their website: #{snapshot.differences.first.downcase_first}",
          detail: snapshot.differences.join("; "), evidence: {"competitor" => competitor.name, "changes" => snapshot.differences},
          sources: [source(snapshot, "site_reading")])
      end
    end

    # How old the data is ------------------------------------------------------------------
    def stale_site
      return unless profile.domain
      return if own_reading && own_reading.taken_at >= 14.days.ago

      finding("stale_site", "stale_data", "low", own_reading ? "The site hasn't been read from outside in #{(Date.current - own_reading.taken_at.to_date).to_i} days" : "The site hasn't been read from outside yet",
        detail: "It's read weekly; Read the site on Market › Competitors reads it now.")
    end

    def stale_search
      return unless setting.search_connected? && profile.domain

      own = own_latest("overview")
      return if own && own.taken_at >= 45.days.ago

      finding("stale_search", "stale_data", "low", own ? "#{possessive(name)} search data is #{(Date.current - own.taken_at.to_date).to_i} days old" : "No search data for #{name} yet",
        channel: "seo", detail: "Pull search data on Market › Search (it costs a little, within the month's budget).")
    end
  end
end
