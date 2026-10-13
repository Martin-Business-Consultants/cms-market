# frozen_string_literal: true

# The site's links, and its competitors', as Search › Links, the findings, the
# AI and the API read them (DataForSEO Backlinks, Settings › Market ›
# Backlinks too): each site's profile and year, who links to the site, what
# it's won and lost lately, links to its pages that no longer answer (and
# whether a redirect wins them back yet), the words it's linked with, the
# pages of each site most linked to, the sites linking to competitors but not
# to it, and those with a link profile like its own.
class Market::Links
  KINDS = %w[backlinks backlink_history linked_pages referring_domains link_changes broken_links anchors link_competitors link_gap].freeze
  # A linking site worth having (rank out of 100), and one that looks like spam.
  VALUABLE = 20
  SPAMMY = Market::Search::Api::Links::SPAMMY
  GENERIC = /\A(click here|here|this|website|web ?site|link|read more|learn more|more|visit|visit (the )?(site|website)|source|homepage|home page|this (site|page|article)|https?:?\/?\/?)\z/i
  ANCHOR_KINDS = {"brand" => "The business's name", "url" => "Its address", "generic" => "“Click here” and the like",
                  "keyword" => "A search it wants to win", "other" => "Other words", "none" => "No words (an image)"}.freeze

  Site = Data.define(:name, :domain, :competitor, :summary, :history, :pages) do
    def own? = competitor.nil?
    def figure(key) = summary&.data&.dig(key)
    def months = Array(history&.data&.dig("months"))
    def recent(key, count = 3) = months.last(count).sum { it[key].to_i }
    # Share of linking sites whose links search engines follow.
    def follow_share
      total = figure("referring_domains").to_i
      total.positive? ? ((total - figure("referring_domains_nofollow").to_i) * 100.0 / total).round : nil
    end
  end

  attr_reader :profile

  def initialize(profile: Market::Profile.current)
    @profile = profile
    @competitors = Market::Competitor.watchable.by_threat.to_a
    @snapshots = Market::SearchSnapshot.latest_by_site(@competitors.map(&:id), kinds: KINDS)
  end

  def pulled? = sites.any?(&:summary) || sites.any?(&:history)
  def taken_at = KINDS.filter_map { own(it)&.taken_at }.max

  def sites
    @sites ||= [(site(nil, profile.business_name, profile.domain) if profile.domain), *@competitors.map { site(it, it.name, it.domain) }].compact
  end

  def own_site = sites.find(&:own?)
  def competitor_sites = sites.reject(&:own?)

  # The sites linking to the site, best first: [{"domain", "rank", "links", "follow", "spam", "first_seen"}].
  def referring = Array(own("referring_domains")&.data&.dig("sites"))
  def referring_total = own("referring_domains")&.data&.dig("total").to_i
  def spammy = referring.select { it["spam"].to_i >= SPAMMY }

  # Won and lost in the last 90 days, one row a linking site.
  def changes = own("link_changes")&.data || {}
  def won = Array(changes["won"])
  def lost = Array(changes["lost"])
  def valuable_lost = lost.select { it["follow"] && it["rank"].to_i >= VALUABLE }

  # Pages other sites link to that answer an error, most linked first, each with what's happened to it since:
  # {"path", "url", "status", "sites", "best_rank", "links", "redirect" (where a rule sends it), "page" (a page there now)}.
  def broken
    @broken ||= Array(own("broken_links")&.data&.dig("pages")).map do |row|
      path = row["path"].to_s
      found = defined?(::Redirect) ? ::Redirect.match(path) : nil
      page = ::Page.find_by(path: path.delete_prefix("/").chomp("/").presence || "home")
      row.merge("redirect" => found&.dig(:destination), "page" => page&.path)
    end
  end

  def unfixed = broken.reject { it["redirect"] || it["page"] }

  # The words the site is linked with, each sorted into ANCHOR_KINDS: [{"anchor", "sites", "links", "kind"}].
  def anchors
    @anchors ||= Array(own("anchors")&.data&.dig("anchors")).map { it.merge("kind" => anchor_kind(it["anchor"])) }
  end

  # Of the linking sites, the share using each kind of words: {kind => percent}.
  def anchor_mix
    total = anchors.sum { it["sites"].to_i }
    return {} if total.zero?

    anchors.group_by { it["kind"] }.transform_values { |rows| (rows.sum { it["sites"].to_i } * 100.0 / total).round }.sort_by { -it[1] }.to_h
  end

  # Each competitor's most-linked pages: what earns them links. [[site, [{"url", "sites", "links"}]]]
  def linkable_pages = competitor_sites.filter_map { |site| [site, Array(site.pages&.data&.dig("pages")).first(6)] if site.pages }
  def own_pages = Array(own_site&.pages&.data&.dig("pages"))

  # The sites linking to competitors but not to the site.
  def gap = own("link_gap")&.data || {}

  # Sites whose links overlap the site's, not watched yet: [{"domain", "rank", "shared"}].
  def link_rivals
    watched = @competitors.map(&:domain)
    Array(own("link_competitors")&.data&.dig("sites")).reject { |row| watched.any? { row["domain"] == it || row["domain"].to_s.end_with?(".#{it}") } }
  end

  # The pages a broken link could go to instead: [[title, path]].
  def redirect_choices = ::Page.where(status: "published").order(:path).limit(300).map { [it.title.presence || it.path, "/#{(it.path == "home") ? "" : it.path}"] }

  # Everything, for GET /api/market/links.
  def as_api
    {summary: facts, checked_at: taken_at,
     sites: sites.map do |site|
       {name: site.name, domain: site.domain, competitor_id: site.competitor&.id, profile: site.summary&.data, months: site.months, linked_pages: Array(site.pages&.data&.dig("pages"))}
     end,
     referring: referring, referring_total: referring_total, won: won, lost: lost, valuable_lost: valuable_lost,
     broken: broken, anchors: anchors, anchor_mix: anchor_mix, gap: gap, link_rivals: link_rivals,
     next: ["Redirect a broken address: cms post /api/redirects '{\"redirect\":{\"source_path\":\"/old\",\"destination_url\":\"/new\",\"status_code\":301}}'",
       "POST /api/market/workups {\"subject\":\"links:own\"} for the AI's outreach plan"]}
  end

  # What the AI and the API are told, in a few lines.
  def facts
    own = own_site
    return "No link data yet (Settings › Market › Backlinks too)." unless own&.summary || own&.history

    rows = sites.select(&:summary).map do |site|
      "#{site.name} (#{site.domain}): #{site.figure("referring_domains")} linking sites (#{site.follow_share}% followed), rank #{site.figure("rank")}/100, " \
        "#{site.recent("new_referring_domains")} new and #{site.recent("lost_referring_domains")} lost in 3 months"
    end
    ["Links, from DataForSEO Backlinks:", *rows,
      ("Linking to the site, best first: #{referring.first(15).map { "#{it["domain"]} (rank #{it["rank"]}#{", nofollow" unless it["follow"]})" }.join(", ")}" if referring.any?),
      ("Won in #{changes["days"]} days: #{won.first(10).map { it["domain"] }.join(", ")}" if won.any?),
      ("Lost in #{changes["days"]} days (worth winning back): #{valuable_lost.first(10).map { "#{it["domain"]} (rank #{it["rank"]}, linked to #{it["url_to"]})" }.join("; ")}" if valuable_lost.any?),
      ("Links to pages that no longer answer: #{unfixed.first(10).map { "#{it["path"]} (#{it["status"]}, #{it["sites"]} sites)" }.join("; ")}" if unfixed.any?),
      ("The words it's linked with: #{anchor_mix.map { |kind, share| "#{ANCHOR_KINDS[kind].downcase} #{share}%" }.join(", ")}" if anchor_mix.any?),
      ("Linking to competitors, not to the site: #{Array(gap["sites"]).first(15).map { "#{it["domain"]} (to #{Array(it["links_to"]).join(", ")})" }.join("; ")}" if Array(gap["sites"]).any?),
      *linkable_pages.map { |site, pages| "#{site.name}'s most-linked pages: #{pages.map { "#{it["url"]} (#{it["sites"]} sites)" }.join("; ")}" if pages.any? }.compact,
      ("Sites with links like the site's, not watched: #{link_rivals.first(8).map { it["domain"] }.join(", ")}" if link_rivals.any?)].compact.join("\n")
  end

  private

  def own(kind) = @snapshots.dig(nil, kind, 0)

  def site(competitor, name, domain)
    kinds = @snapshots.fetch(competitor&.id, {})
    Site.new(name: name, domain: domain, competitor: competitor, summary: kinds["backlinks"]&.first, history: kinds["backlink_history"]&.first, pages: kinds["linked_pages"]&.first)
  end

  def anchor_kind(text)
    words = text.to_s.strip.downcase
    return "none" if words.empty?
    return "url" if words.match?(%r{\A(https?://)?(www\.)?[a-z0-9.-]+\.[a-z]{2,}(/\S*)?\z})
    return "generic" if words.match?(GENERIC)
    return "brand" if brand_terms.any? { words.include?(it) }
    return "keyword" if keyword_terms.any? { words.include?(it) }

    "other"
  end

  def brand_terms
    @brand_terms ||= [profile.business_name, profile.maps_name, profile.domain.to_s.split(".").first].compact_blank.map { it.downcase.strip }.select { it.size > 2 }
  end

  def keyword_terms = @keyword_terms ||= Market::Keyword.pluck(:keyword).map { it.downcase.strip }.select { it.size > 3 }
end
