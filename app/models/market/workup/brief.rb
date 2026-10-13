# frozen_string_literal: true

# What the AI is told for a work-up (Market::Workup): the business, the one
# thing worked on and the facts about it, the site's pages (path, title, meta
# data), and the wording of the pages that matter most, each text field by
# an id (Market::Workup::Sending changes them by it).
class Market::Workup::Brief
  PAGES = 80
  FIELDS = 60

  attr_reader :subject, :kind, :record

  def initialize(subject)
    raise ActiveRecord::RecordNotFound, "No such subject: #{subject}" unless Market::Workup.subject?(subject)

    @subject = subject
    @kind, id = subject.split(":", 2)
    @record =
      case @kind
      when "keyword", "map" then Market::Keyword.find(id)
      when "opportunity" then Market::Opportunity.find(id)
      when "finding" then Market::Finding.find(id)
      when "page" then ::Page.find(id)
      when "visibility" then (id == "own") ? nil : Market::Competitor.find(id)
      end
  end

  def label
    case kind
    when "keyword" then "the search “#{record.keyword}”"
    when "map" then "showing on Google Maps for “#{record.keyword}”"
    when "opportunity" then "the opportunity “#{record.title}”"
    when "finding" then "the finding “#{record.title}”"
    when "page" then "the page “#{record.title}” (/#{(record.path == "home") ? "" : record.path})"
    else record ? "beating #{record.name} in search" : "the site's visibility in search"
    end
  end

  def to_s
    [business, facts, ai_search, google, pages, *focus_pages.map { page_text(it) }].compact_blank.join("\n\n")
  end

  # A page's text fields, {id => text}; nil for a path that isn't a page.
  def fields_of(path)
    page = ::Page.find_by(path: path.to_s.delete_prefix("/").presence || "home") or return
    self.class.text_fields(page)
  end

  # {"blocks.2.data.heading" => "…"} for each piece of wording in a page's blocks.
  def self.text_fields(page)
    fields = {}
    walk = lambda do |value, path|
      case value
      when Hash then value.each { |key, item| walk.call(item, [*path, key]) unless key.to_s.match?(/(_id|_href|href|url|type|id|icon|image|color|style|variant)\z/) }
      when Array then value.each_with_index { |item, index| walk.call(item, [*path, index]) }
      when String then fields[path.join(".")] = value if value.match?(/[[:alpha:]]{3}/) && !value.match?(%r{\A(https?:|/|#)})
      end
    end
    walk.call(Array(page.blocks), ["blocks"])
    fields.first(FIELDS).to_h
  end

  private

  def profile = @profile ||= Market::Profile.current

  # The business, and the plan for it: the market's big picture and the angle to win on, which every change should serve.
  def business
    plan = Market::Plan.where(state: "ready").latest_first.first
    ["The business: #{profile.business_name} (#{profile.website})",
      *Market::Profile::FIELDS.filter_map { |field| "#{Market::Profile::LABELS[field]}: #{profile.public_send(field)}" if profile.public_send(field) },
      ("The plan's big picture: #{plan.summary}" if plan&.summary.present?),
      ("The angle to win on: #{plan.positioning}" if plan&.positioning.present?)].compact.join("\n")
  end

  def facts
    case kind
    when "keyword" then keyword_facts
    when "map" then map_facts
    when "opportunity" then "The opportunity: #{record.title} (#{record.channel_label}, #{record.impact} impact, #{record.effort} effort)\n#{record.detail}\nEvidence: #{record.evidence}"
    when "finding" then "The finding (#{record.severity}): #{record.title}\n#{record.detail}\nThe figures: #{JSON.generate(record.evidence).truncate(4000)}"
    when "page" then "The page to improve: /#{(record.path == "home") ? "" : record.path} (“#{record.title}”), #{record.status}; SEO: #{JSON.generate(record.seo.to_h).truncate(1500)}"
    else visibility_facts
    end
  end

  def keyword_facts
    now, before = Market::Ranking.latest_for([record])[record.id]
    return "The search: “#{record.keyword}”. Not checked yet: where anyone ranks isn't known." unless now

    results = Array(now.results).first(10).map { "#{it["position"]}. #{it["domain"]} #{it["url"]}#{" — #{it["title"]}" if it["title"]}" }
    ["The search: “#{record.keyword}”, checked #{now.checked_at.to_date.to_fs(:long)}.",
      "The site ranks #{now.position || "outside the top #{Market::Search::Api::RANKING_DEPTH}"}#{" (was #{before.position || "not ranked"})" if before}#{", with #{now.url}" if now.url}.",
      ("On the results page too: #{Array(now.features).join(", ")}" if Array(now.features).any?),
      "The top results:\n#{results.join("\n")}"].compact.join("\n")
  end

  def map_facts
    scan, before = Market::LocalScan.latest_for([record])[record.id]
    return "The search on Google Maps: “#{record.keyword}”. Not scanned yet." unless scan

    missed = scan.points.reject { it["position"].to_i.between?(1, 3) }.map { "#{it["lat"]},#{it["lng"]}: #{it["position"] || "not in the top 20"}; top 3 #{Array(it["top"]).join(", ")}" }
    ["The search on Google Maps: “#{record.keyword}”, from a #{scan.grid}×#{scan.grid} grid of points within #{scan.radius_miles.to_i} miles of #{scan.zip}, #{scan.checked_at.to_date.to_fs(:long)}.",
      "Found at #{scan.found_points} of #{scan.points.size} points; average position #{scan.average_position}#{" (was #{before.average_position})" if before}; in the top 3 at #{(scan.top3_share * scan.points.size).round}.",
      "Its name on Maps: #{profile.maps_name.presence || profile.business_name}.",
      "Who leads the most points: #{scan.leaders.map { "#{it["title"]} (#{it["domain"].presence || "no website"}, top 3 at #{it["top3_points"]})" }.join("; ")}",
      ("Where it isn't in the top 3:\n#{missed.first(25).join("\n")}" if missed.any?)].compact.join("\n")
  end

  def visibility_facts
    data = Market::Search::Overview.new
    rows = data.sites.select(&:pulled?).map do |site|
      "#{site.name} (#{site.domain}): #{site.figure("organic_keywords")} keywords, ~#{site.figure("organic_traffic")} visits a month (est.), #{site.figure("top_3")} in the top 3, #{site.figure("top_10")} in the top 10, #{site.figure("paid_keywords")} paid"
    end
    own = data.sites.find(&:own?)
    theirs = record && data.sites.find { it.competitor == record }
    wins = Array(theirs&.keywords&.data&.dig("keywords")).select { it["position"].to_i.between?(1, 10) }.sort_by { -it["volume"].to_i }.first(25)
    mine = Array(own&.keywords&.data&.dig("keywords")).sort_by { -it["volume"].to_i }.first(25)
    ["Search visibility from DataForSEO (traffic is its estimate):", *rows,
      ("The site's best keywords: #{mine.map { "#{it["keyword"]} (##{it["position"]}, #{it["volume"]}/mo, #{it["url"]})" }.join("; ")}" if mine.any?),
      ("Where #{record.name} is on page one: #{wins.map { "#{it["keyword"]} (##{it["position"]}, #{it["volume"]}/mo)" }.join("; ")}" if wins.any?),
      "Searches tracked: #{data.keywords.map(&:keyword).join(", ").presence || "none"}"].compact.join("\n")
  end

  def pages
    rows = ::Page.where(status: "published").order(:path).limit(PAGES).map do |page|
      seo = page.seo.to_h
      "/#{(page.path == "home") ? "" : page.path} — #{page.title}#{" | meta title: #{seo["meta_title"]}" if seo["meta_title"].present?}#{" | meta description: #{seo["meta_description"]}" if seo["meta_description"].present?}" \
        "#{" | JSON-LD: #{Array.wrap(seo["json_ld"]).filter_map { it["@type"] if it.is_a?(Hash) }.join(", ").presence || "set"}" if seo["json_ld"].present?}#{" | schema type: #{seo["schema_type"]}" if seo["schema_type"].present?}"
    end
    "The site's pages (path — title | meta data):\n#{rows.join("\n")}"
  end

  # The pages whose wording is given: the one ranking for the search, else the home page.
  def focus_pages = @focus_pages ||= find_focus_pages

  def find_focus_pages
    paths = []
    if kind.in?(%w[keyword map])
      now = Market::Ranking.latest_for([record])[record.id]&.first
      paths << now.page_path if now&.page_path
    end
    paths << record.page.path if kind == "opportunity" && record.page
    paths << record.path if kind == "page"
    paths << record.evidence["page_path"] if kind == "finding" && record.evidence["page_path"]
    paths << "home"
    ::Page.where(path: paths.uniq).to_a.sort_by { paths.index(it.path) }.first(2)
  end

  # How the AIs answer: for a search, each one's answer (named the business or not, who instead,
  # what it cited); for the site, how often each named it across the searches, and its share of
  # voice in DataForSEO's database of real AI answers.
  def ai_search
    if kind.in?(%w[keyword map])
      checks = Market::AiCheck.latest_for([record])[record.id].to_h.values.select(&:answered)
      return if checks.empty?

      ["Asked of AI assistants (checked live through DataForSEO):",
        *checks.map do |check|
          "#{check.platform_name}: #{check.mentioned ? "named the business #{check.mention_rank.to_i.ordinalize}" : "did not name the business"}#{", cited its site" if check.cited}; " \
            "named #{check.named.reject { it["own"] }.map { it["name"] }.first(6).join(", ").presence || "no one else known"}; cited #{check.source_domains.first(6).join(", ").presence || "nothing"}. " \
            "Answer: #{check.answer.to_s.squish.truncate(500)}"
        end].join("\n")
    elsif kind.in?(%w[visibility finding opportunity page])
      overview = Market::Search::Overview.new
      return unless overview.ai_checked?

      lines = overview.ai_summary.map { |platform, counts| "#{Market::AiCheck.platform_name(platform)}: named the business in #{counts[:named]} of #{counts[:answered]} answers, cited its site in #{counts[:cited]}" }
      ["AI search across the tracked searches (checked live):", *lines,
        "Named instead: #{overview.ai_named_others.map { "#{it[0]} (#{it[1]})" }.join(", ").presence || "no one"}",
        "Sites the AIs cite most: #{overview.ai_cited_domains.map { "#{it[0]} (#{it[1]})" }.join(", ").presence || "none"}"].join("\n")
    end
  end

  # What Google says, from the Google plugin when it's on: the real searches and clicks, the visits and enquiries, the profile's calls and reviews.
  def google
    return unless defined?(::Google) && ::Google.respond_to?(:search_console)

    paths = focus_pages.map(&:path)
    [search_console_facts(::Google.search_console, paths), analytics_facts(::Google.analytics, paths), profile_facts(::Google.business_profile)].compact.join("\n\n").presence
  end

  def search_console_facts(console, paths)
    return unless console&.totals

    now = console.totals
    rows = (kind.in?(%w[keyword map]) ? console.queries.select { it["keys"][0].include?(record.keyword) || record.keyword.include?(it["keys"][0]) }.first(10) : [])
    ["Google Search Console, last 28 days (real figures): #{now[:clicks]} clicks, #{now[:impressions]} impressions, CTR #{(now[:ctr] * 100).round(1)}%, average position #{now[:position]}#{" (the 28 before: #{console.totals_before[:clicks]} clicks)" if console.totals_before}.",
      ("This search in Search Console: #{rows.map { "#{it["keys"][0]} (#{it["impressions"]} impressions, #{it["clicks"]} clicks, position #{it["position"].to_f.round(1)})" }.join("; ")}" if rows.any?),
      *paths.filter_map { |path| (found = console.queries_for(path, limit: 12)).any? ? "Searches /#{(path == "home") ? "" : path} is found for: #{found.map { "#{it["keys"][0]} (#{it["impressions"]} impr., #{it["clicks"]} clicks, pos. #{it["position"].to_f.round(1)})" }.join("; ")}" : nil },
      "Searches close to the top (position 4–20): #{console.striking_distance(limit: 12).map { "#{it["keys"][0]} (#{it["impressions"]} impr., pos. #{it["position"].to_f.round(1)})" }.join("; ").presence || "none"}",
      ("Pages shown a lot but clicked little: #{console.low_click_pages(limit: 6).map { "/#{console.page_path(it["keys"][0])} (#{it["impressions"]} impr., CTR #{(it["ctr"].to_f * 100).round(1)}%, pos. #{it["position"].to_f.round(1)})" }.join("; ")}" if console.low_click_pages.any?)].compact.join("\n")
  end

  def analytics_facts(analytics, paths)
    return unless analytics&.totals

    now = analytics.totals
    pages = analytics.landing_pages.select { |row| paths.any? { "/#{(it == "home") ? "" : it}" == row["key"] } }
    ["Google Analytics, last 28 days: #{now[:sessions]} sessions, #{now[:key_events]} key events (enquiries, bookings).",
      "By channel: #{analytics.channels.first(6).map { "#{it["key"]} #{it["now"]["sessions"].to_i}" }.join(", ")}",
      *pages.map { "Landing page #{it["key"]}: #{it["now"]["sessions"].to_i} sessions, #{it["now"]["keyEvents"].to_i} key events, #{(it["now"]["engagementRate"] * 100).round}% engaged" }].join("\n")
  end

  def profile_facts(profile)
    return unless profile&.totals && kind.in?(%w[map finding visibility])

    now = profile.totals
    ["Google Business Profile, last 28 days: #{now[:maps] + now[:search]} views, #{now[:calls]} calls, #{now[:website]} website clicks, #{now[:directions]} direction requests; " \
      "#{profile.reviews["total"]} reviews at #{profile.reviews["average"]}, #{profile.unanswered_reviews.size} unanswered.",
      "Searches it was found for on Google: #{profile.keywords.first(15).map { "#{it["keyword"]} (#{it["impressions"]})" }.join(", ")}"].join("\n")
  end

  def page_text(page)
    fields = self.class.text_fields(page).map { |id, text| "#{id}: #{text.truncate(400)}" }
    "The wording of /#{(page.path == "home") ? "" : page.path} (“#{page.title}”), field id: text\n#{fields.join("\n")}"
  end
end
