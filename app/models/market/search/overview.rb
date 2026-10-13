# frozen_string_literal: true

# The site's search data as the screens and the API read it: the latest
# DataForSEO snapshots of every site (and the one before, to compare), the
# sites sharing the site's keywords, the tracked searches with everyone's
# positions and the CMS page the site ranks with, AI search (each tracked
# search asked of each AI, and AI share of voice), and the extras: keyword
# facts, who wins the tracked searches, Business Profiles, site health, web
# mentions. A few queries in all.
class Market::Search::Overview
  Site = Data.define(:name, :domain, :competitor, :overview, :previous, :keywords, :backlinks, :ai_overview, :business_profile, :web_mentions,
    :reviews, :backlink_history) do
    def own? = competitor.nil?
    def pulled? = overview.present?
    def figure(key) = overview&.data&.dig(key)
    def before(key) = previous&.data&.dig(key)
  end

  attr_reader :profile, :competitors, :keywords, :rankings, :last_pull

  def initialize
    @profile = Market::Profile.current
    @competitors = Market::Competitor.watchable.by_threat.to_a
    @keywords = Market::Keyword.ordered.to_a
    @rankings = Market::Ranking.latest_for(@keywords)
    @local = Market::LocalScan.latest_for(@keywords)
    @snapshots = Market::SearchSnapshot.latest_by_site(@competitors.map(&:id))
    @last_pull = Market::SearchPull.latest_first.first
    @ai = Market::AiCheck.latest_for(@keywords)
  end

  def settings = @settings ||= Market::Settings.current

  # The latest of a market-wide kind (kept on the site's own row): keyword_facts, serp_competitors, ai_mentions, ai_answers, site_health.
  def market(kind) = @snapshots.dig(nil, kind, 0)

  # The AIs asked, in order, that have answered or been asked at least once.
  def ai_platforms = Market::AiCheck::PLATFORMS.keys.select { |platform| settings.ai_platform?(platform) || @ai.values.any? { it.key?(platform) } }
  def ai_checked? = @ai.any?

  # Across the tracked searches, for each AI: how many it answered, named the business in, cited its site in.
  def ai_summary
    ai_platforms.to_h do |platform|
      checks = @ai.values.filter_map { it[platform] }
      answered = checks.select(&:answered)
      [platform, {asked: checks.size, answered: answered.size, named: answered.count(&:mentioned), cited: answered.count(&:cited),
                  checked_at: checks.map(&:checked_at).max}]
    end
  end

  # Who the AIs name instead, and the sites they cite most, across every answer: [[name, count]].
  def ai_named_others = all_checks.flat_map(&:competitors_named).map { it["name"] }.tally.sort_by { -it[1] }.first(10)
  def ai_cited_domains = all_checks.flat_map(&:source_domains).tally.sort_by { -it[1] }.first(12)
  def all_checks = @ai.values.flat_map(&:values).select(&:answered)

  # Reviews still being fetched from DataForSEO's queue.
  def reviews_waiting? = Market::QueuedTask.queued.where(kind: "reviews").exists?

  # The area the local searches a month are for ("Grand Rapids,Michigan,United States").
  def volume_area = market("keyword_facts")&.data&.dig("area")

  # One search's facts: Google's volume, AI's, difficulty, intent.
  def keyword_fact(keyword) = market("keyword_facts")&.data&.dig("keywords", keyword.keyword) || {}

  def sites
    @sites ||= [(site(nil, @profile.business_name, @profile.domain) if @profile.domain), *competitors.map { site(it, it.name, it.domain) }].compact
  end

  def pulled? = sites.any?(&:pulled?)
  def local_scanned? = @local.any?
  def competitor_sites = sites.reject(&:own?)

  # Each tracked search: the site's position now and before, its page, and each competitor's position now.
  def tracked
    pages = Page.where(path: rankings.values.filter_map { it.first&.page_path }.uniq).index_by(&:path)
    keywords.map do |keyword|
      now, before = rankings[keyword.id]
      local, local_before = @local[keyword.id]
      {keyword: keyword, ranking: now, position: now&.position, before: before&.position, page: now&.page_path && pages[now.page_path],
       local: local, local_before: local_before, ai: @ai.fetch(keyword.id, {}), facts: keyword_fact(keyword),
       competitors: competitor_sites.to_h { [it.domain, now&.position_of(it.domain)] }}
    end
  end

  # The sites sharing the site's keywords that aren't watched yet.
  def unwatched
    watched = competitor_sites.map(&:domain)
    found = @snapshots.dig(nil, "competitors", 0)
    Array(found&.data&.dig("competitors")).reject { |row| watched.any? { row["domain"] == it || row["domain"].to_s.end_with?(".#{it}") } }
  end

  private

  def site(competitor, name, domain)
    kinds = @snapshots.fetch(competitor&.id, {})
    overview, previous = kinds["overview"]
    Site.new(name: name, domain: domain, competitor: competitor, overview: overview, previous: previous,
      keywords: kinds["keywords"]&.first, backlinks: kinds["backlinks"]&.first, ai_overview: kinds["ai_overview"]&.first,
      business_profile: kinds["business_profile"]&.first, web_mentions: kinds["web_mentions"]&.first, reviews: kinds["reviews"]&.first,
      backlink_history: kinds["backlink_history"]&.first)
  end
end
