# frozen_string_literal: true

module Market
  # Findings from AI search and the pull's extras: searches the AIs answer
  # without naming the business, competitors they name instead, the sites
  # they cite, AI share of voice, the Business Profile's gaps beside the
  # competitors', the home page's health, and the web talking about others more.
  module Finding::SearchFindings
    private

    def search_findings
      [*ai_not_named, ai_named_instead, ai_cited_sites, ai_share_of_voice, *profile_findings, *health_findings, web_mentions_gap, questions_to_answer,
        *review_findings, *link_findings].compact
    end

    def ai_checks = @ai_checks ||= Market::AiCheck.latest_for(keywords)

    def ai_source(check) = {"type" => "ai_check", "id" => check.id, "kind" => check.platform, "at" => check.checked_at.iso8601}

    # A search two or more AIs answer, none of them naming the business.
    def ai_not_named
      keywords.filter_map do |keyword|
        answered = ai_checks.fetch(keyword.id, {}).values.select(&:answered)
        next if answered.size < 2 || answered.any?(&:mentioned)

        others = answered.flat_map(&:competitors_named).map { it["name"] }.tally.sort_by { -it[1] }.first(5).map(&:first)
        finding("ai_not_named:#{keyword.keyword}", "ai_not_named", others.any? ? "high" : "medium",
          "AI assistants answer “#{keyword.keyword}” without naming #{name}",
          detail: "#{answered.map(&:platform_name).to_sentence} answered; none named the business#{others.any? ? ", and they named #{others.to_sentence}" : ""}. " \
                  "A page that plainly answers the search, with the facts the answers use and structured data, and being on the sites they cite, gets it named.",
          channel: "seo", evidence: {"search" => keyword.keyword, "keyword_id" => keyword.id, "asked" => answered.map(&:platform_name), "named_instead" => others,
                                     "cited" => answered.flat_map(&:source_domains).tally.sort_by { -it[1] }.first(8).map(&:first)},
          sources: answered.map { ai_source(it) })
      end
    end

    # A competitor the AIs name more often than the business, across the searches.
    def ai_named_instead
      checks = ai_checks.values.flat_map(&:values).select(&:answered)
      return if checks.size < 3

      own = checks.count(&:mentioned)
      leader, count = checks.flat_map(&:competitors_named).map { it["name"] }.tally.max_by(&:last)
      return unless leader && count > own && count >= 2

      finding("ai_named_instead:#{leader}", "ai_named_instead", (own.zero? ? "high" : "medium"), "AI assistants name #{leader} in #{count} answers, #{name} in #{own}",
        detail: "Across #{checks.size} answers to the tracked searches. Find what they're cited for (Search › AI search) and give the AIs the same reasons to name #{name}.",
        channel: "seo", evidence: {"competitor" => leader, "competitor_answers" => count, "own_answers" => own, "answers" => checks.size},
        sources: checks.first(10).map { ai_source(it) })
    end

    # The sites the AIs cite most, where the business isn't.
    def ai_cited_sites
      checks = ai_checks.values.flat_map(&:values).select(&:answered)
      cited = checks.flat_map(&:source_domains).reject { it == profile.domain }.tally.sort_by { -it[1] }.select { it[1] >= 2 }.first(10)
      return if cited.empty?

      finding("ai_cited_sites", "ai_cited_sites", "medium", "AI answers lean on #{cited.first(3).map(&:first).to_sentence}",
        detail: "The sites the AIs cite most in answering the tracked searches. A listing, reviews or a mention on each is how a business gets into those answers.",
        channel: "local", evidence: {"sites" => cited.map { {"site" => it[0], "answers" => it[1]} }}, sources: checks.first(10).map { ai_source(it) })
    end

    # AI share of voice from DataForSEO's database of real answers: the business far behind a competitor.
    def ai_share_of_voice
      snapshot = own_latest("ai_mentions") or return
      snapshot.data.filter_map do |platform, rows|
        own = rows.dig("site", "mentions").to_i
        key, best = rows.reject { |k, _| k == "site" }.max_by { |_, row| row["mentions"].to_i }
        next unless best && best["mentions"].to_i >= 5 && best["mentions"].to_i > own * 3

        competitor = competitors.find { "competitor:#{it.id}" == key }
        finding("ai_share_of_voice:#{platform}", "ai_share_of_voice", "medium",
          "#{(platform == "chat_gpt") ? "ChatGPT" : "Google's AI"} answers mention #{competitor&.name || "a competitor"} #{best["mentions"]} times, #{name} #{own}",
          detail: "From DataForSEO's database of real AI answers. Being cited is earned like links are: pages that answer questions fully, and mentions on the sites AI trusts.",
          channel: "seo", evidence: {"platform" => platform, "own" => own, "competitor" => competitor&.name, "competitor_mentions" => best["mentions"].to_i,
                                     "sources" => Array(best["sources"]).first(6)},
          sources: [source(snapshot, "search_snapshot")])
      end.first
    end

    def profile_findings
      own = own_latest("business_profile")&.data or return []
      theirs = competitors.filter_map { latest("business_profile", it)&.data }
      found = []
      unless own["claimed"]
        found << finding("gbp_unclaimed", "gbp_unclaimed", "high", "#{name}'s Google Business Profile isn't claimed",
          detail: "Claim it (business.google.com) to answer reviews, post, and keep its hours, categories and photos right.", channel: "local", evidence: own.slice("title", "category", "rating", "reviews"))
      end
      missing = {"hours" => "opening hours", "description" => "a description"}.reject { |key, _| own[key] }.values
      if missing.any?
        found << finding("gbp_missing", "gbp_missing", "medium", "The Google Business Profile has no #{missing.to_sentence}",
          detail: "A complete profile ranks better on Maps and gives AI answers the facts to name it.", channel: "local", evidence: {"missing" => missing})
      end
      if theirs.any?
        photos = theirs.map { it["photos"].to_i }.sort[theirs.size / 2]
        if photos >= 10 && own["photos"].to_i < photos / 2
          found << finding("gbp_photos", "gbp_photos", "low", "The profile has #{own["photos"].to_i} photos; competitors typically #{photos}",
            detail: "Photos of the work, the team and the place, added every month.", channel: "local", evidence: {"own" => own["photos"].to_i, "competitors_median" => photos})
        end
      end
      found
    end

    def health_findings
      health = own_latest("site_health")&.data or return []
      found = []
      performance = health.dig("lighthouse", "performance")
      if performance && performance < 50
        found << finding("site_slow", "site_slow", "medium", "The home page scores #{performance}/100 for speed on a phone",
          detail: "Lighthouse, on a phone. Slow pages lose visitors and rankings: compress images, defer scripts, cache.",
          channel: "website", evidence: health.slice("lighthouse", "lcp_ms", "url"))
      end
      if Array(health["issues"]).any?
        found << finding("site_issues", "site_issues", "low", "The home page has #{health["issues"].size} things to fix",
          detail: health["issues"].map(&:humanize).first(8).join(", "), channel: "website", evidence: health.slice("issues", "url", "onpage_score"))
      end
      found
    end

    def web_mentions_gap
      own = own_latest("web_mentions")&.data or return
      leader = competitors.filter_map { |competitor| latest("web_mentions", competitor)&.data&.then { [competitor, it] } }.max_by { it[1]["total"].to_i }
      return unless leader && leader[1]["total"].to_i >= 20 && leader[1]["total"].to_i > own["total"].to_i * 3

      finding("web_mentions_gap", "web_mentions_gap", "low", "The web names #{leader[0].name} #{leader[1]["total"]} times, #{name} #{own["total"].to_i}",
        detail: "Pages naming a business are what AI assistants learn it from. Local press, directories, partners and sponsorships add them.",
        channel: "brand", evidence: {"own" => own["total"].to_i, "competitor" => leader[0].name, "competitor_total" => leader[1]["total"].to_i, "where" => Array(leader[1]["top_domains"]).first(6)})
    end

    # Reviews (DataForSEO's queue): unanswered, coming slower than a competitor's, and what customers complain about.
    def review_findings
      own = own_latest("reviews")&.data or return []
      list = Array(own["reviews"])
      found = []
      waiting = list.reject { it["answered"] }
      google = defined?(::Google) && ::Google.respond_to?(:ready?) && ::Google.ready?(:business_profile)
      if !google && list.size >= 5 && waiting.size > list.size / 2
        found << finding("reviews_unanswered", "reviews_unanswered", waiting.any? { it["stars"].to_i <= 3 } ? "high" : "medium",
          "#{waiting.size} of the latest #{list.size} reviews haven't been answered",
          detail: "Answer every review, the critical ones first: the next customer reads the answers, and Google counts them.", channel: "reviews",
          evidence: {"waiting" => waiting.first(8).map { it.slice("stars", "reviewer", "text", "at", "source") }})
      end
      recent = ->(data) { Array(data["reviews"]).count { it["at"].present? && Time.zone.parse(it["at"]) > 90.days.ago } }
      mine = recent.call(own)
      leader = competitors.filter_map { |competitor| latest("reviews", competitor)&.data&.then { [competitor, recent.call(it)] } }.max_by(&:last)
      if leader && leader[1] >= 5 && leader[1] > mine * 2
        found << finding("review_pace", "review_pace", "medium", "#{leader[0].name} got #{leader[1]} Google reviews in 90 days, #{name} #{mine}",
          detail: "Reviews coming in steadily are what Maps and AI answers reward. Ask every happy customer, with a direct link to leave one.", channel: "reviews",
          evidence: {"competitor" => leader[0].name, "competitor_90_days" => leader[1], "own_90_days" => mine})
      end
      complaints = Array(own.dig("themes", "complaints"))
      if complaints.any?
        found << finding("review_complaints", "review_complaints", "medium", "Customers' reviews complain about #{complaints.first(2).to_sentence}",
          detail: own["advice"].presence || "Fix what's behind them, say so in the answers, and ask the customers it's fixed for to review again.", channel: "reviews",
          evidence: {"complaints" => complaints, "praise" => Array(own.dig("themes", "praise"))})
      end
      found
    end

    # Links: the site's linking sites falling over the year, and the sites linking to competitors but not to it.
    def link_findings
      found = []
      months = Array(own_latest("backlink_history")&.data&.dig("months"))
      if months.size >= 6
        before = months.first["referring_domains"].to_i
        now = months.last["referring_domains"].to_i
        if before >= 20 && now < before * 0.9
          found << finding("links_falling", "links_falling", "medium", "Sites linking to #{name} fell from #{before} to #{now} in a year",
            detail: "Lost links lose rankings. Find the ones lost (moved pages, closed directories) and win them back.", channel: "seo",
            evidence: {"a_year_ago" => before, "now" => now, "lost_last_3_months" => months.last(3).sum { it["lost_referring_domains"].to_i }})
        end
      end
      gap = own_latest("link_gap")&.data
      if gap && Array(gap["sites"]).any?
        found << finding("link_gap", "link_gap", "medium", "#{gap["total"]} sites link to competitors but not to #{name}",
          detail: "The sites already linking to the competitors (directories, associations, suppliers, local press) are the likeliest to link to the business too.",
          channel: "seo", evidence: {"sites" => gap["sites"].first(12).map { it.slice("domain", "links_to", "rank") }})
      end
      found
    end

    # The questions people also ask for the tracked searches the site ranks with a page for.
    def questions_to_answer
      rows = keywords.filter_map do |keyword|
        now = rankings[keyword.id]&.first or next
        questions = Array(now.questions)
        {"search" => keyword.keyword, "questions" => questions.first(5)} if questions.any?
      end
      return if rows.empty?

      finding("questions_to_answer", "questions_to_answer", "low", "People ask #{rows.sum { it["questions"].size }} questions around the tracked searches",
        detail: "Google shows them under the results; answering them on the site (an FAQ with FAQPage JSON-LD) wins that space and gives AI answers something to cite.",
        channel: "content", evidence: {"searches" => rows})
    end
  end
end
