# frozen_string_literal: true

module Market
  # Findings from the Google plugin (cms-google) when it's on: Search Console's
  # real clicks and searches, Analytics' visits and key events, the Business
  # Profile's calls and reviews. Each reads the latest sync only; none without it.
  module Finding::GoogleFindings
    private

    def google_findings
      return [] unless defined?(::Google) && ::Google.respond_to?(:search_console)

      console = ::Google.search_console
      analytics = ::Google.analytics
      profile = ::Google.business_profile
      [*(console ? [*low_click_pages(console), striking_distance(console), clicks_falling(console)] : []),
        *(analytics ? [leaky_pages(analytics), key_events_falling(analytics)] : []),
        *(profile ? [unanswered_reviews(profile), calls_falling(profile)] : [])].compact
    end

    def google_source(service, at) = {"type" => "google", "kind" => service, "at" => at&.iso8601}.compact

    def low_click_pages(console)
      console.low_click_pages(limit: 5).map do |row|
        path = console.page_path(row["keys"][0])
        expected = (console.expected_ctr(row["position"]) * 100).round
        finding("gsc_low_clicks:#{path}", "gsc_low_clicks", (row["impressions"].to_i >= 1000) ? "high" : "medium",
          "/#{(path == "home") ? "" : path} is shown #{row["impressions"]} times a month but clicked #{row["clicks"]}",
          detail: "At an average position of #{row["position"].to_f.round(1)}, about #{expected}% of searchers would usually click; it gets #{(row["ctr"].to_f * 100).round(1)}%. " \
                  "A title and meta description that answer the search would win clicks without ranking any higher.",
          channel: "seo", evidence: {"page_path" => path, "url" => row["keys"][0], "impressions" => row["impressions"], "clicks" => row["clicks"],
                                     "ctr" => row["ctr"].to_f.round(4), "position" => row["position"].to_f.round(1), "searches" => console.queries_for(path, limit: 8).map { it["keys"][0] }},
          sources: [google_source("search_console", console.synced_at)])
      end
    end

    def striking_distance(console)
      rows = console.striking_distance(limit: 12)
      return if rows.empty?

      finding("gsc_striking_distance", "gsc_striking_distance", "medium", "#{rows.size} searches are close to page one's top",
        detail: "Google already shows the site for these, on average 4th to 20th. A better page for each, or more on the page that ranks, moves them up for the least work.",
        channel: "seo", evidence: {"keywords" => rows.map { {"keyword" => it["keys"][0], "impressions" => it["impressions"], "clicks" => it["clicks"], "position" => it["position"].to_f.round(1)} }},
        sources: [google_source("search_console", console.synced_at)])
    end

    def clicks_falling(console)
      now = console.totals
      before = console.totals_before
      return unless now && before && before[:clicks].to_i >= 50 && now[:clicks] < before[:clicks] * 0.8

      change = ((now[:clicks] - before[:clicks]) * 100.0 / before[:clicks]).round
      finding("gsc_clicks_falling", "gsc_clicks_falling", (change <= -35) ? "high" : "medium", "Clicks from Google fell #{change.abs}% in four weeks",
        detail: "#{before[:clicks]} → #{now[:clicks]} clicks; impressions #{before[:impressions]} → #{now[:impressions]}, average position #{before[:position]} → #{now[:position]}.",
        channel: "seo", evidence: {"now" => now.stringify_keys, "before" => before.stringify_keys}, sources: [google_source("search_console", console.synced_at)])
    end

    def leaky_pages(analytics)
      rows = analytics.leaky_pages(limit: 8)
      return if rows.empty?

      finding("ga_leaky_pages", "ga_leaky_pages", "medium", "#{rows.size} landing pages bring visits but no enquiries",
        detail: "People arrive on these and leave without a key event (an enquiry, a booking, a call). A clearer offer and a form or button where they land would turn some into leads.",
        channel: "website", evidence: {"pages" => rows.map { {"page" => it["key"], "sessions" => it["now"]["sessions"].to_i, "engagement" => "#{(it["now"]["engagementRate"] * 100).round}%"} }},
        sources: [google_source("analytics", analytics.synced_at)])
    end

    def key_events_falling(analytics)
      now = analytics.totals
      before = analytics.totals_before
      return unless now && before && before[:key_events].to_i >= 10 && now[:key_events] < before[:key_events] * 0.75

      finding("ga_key_events_falling", "ga_key_events_falling", "high", "Enquiries from the site fell: #{before[:key_events]} → #{now[:key_events]} key events in four weeks",
        detail: "Sessions went #{before[:sessions]} → #{now[:sessions]}. Check the forms still work, then where the visits come from.",
        channel: "website", evidence: {"now" => now.stringify_keys, "before" => before.stringify_keys}, sources: [google_source("analytics", analytics.synced_at)])
    end

    def unanswered_reviews(profile)
      waiting = profile.unanswered_reviews
      return if waiting.empty?

      finding("gbp_unanswered_reviews", "gbp_unanswered_reviews", waiting.any? { it["stars"].to_i <= 3 } ? "high" : "low",
        "#{waiting.size} Google #{(waiting.size == 1) ? "review hasn't" : "reviews haven't"} been answered",
        detail: "Answering every review, and the critical ones first, shows the next customer the business listens, and Google counts it.",
        channel: "reviews", evidence: {"reviews" => waiting.first(10).map { it.slice("reviewer", "stars", "comment", "at") }},
        sources: [google_source("business_profile", profile.synced_at)])
    end

    def calls_falling(profile)
      now = profile.totals
      before = profile.totals_before
      return unless now && before && before[:calls].to_i >= 10 && now[:calls] < before[:calls] * 0.75

      finding("gbp_calls_falling", "gbp_calls_falling", "medium", "Calls from Google fell: #{before[:calls]} → #{now[:calls]} in four weeks",
        detail: "Views on Maps and Search went #{before[:maps] + before[:search]} → #{now[:maps] + now[:search]}. Post to the profile, add photos, and check its hours and categories.",
        channel: "local", evidence: {"now" => now.stringify_keys, "before" => before.stringify_keys}, sources: [google_source("business_profile", profile.synced_at)])
    end
  end
end
