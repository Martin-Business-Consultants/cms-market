# frozen_string_literal: true

# The site's search data as the screens and the API read it: the latest
# DataForSEO snapshots of every site (and the one before, to compare), the
# sites sharing the site's keywords, and the tracked searches with everyone's
# positions and the CMS page the site ranks with. A few queries in all.
class Market::Search::Overview
  Site = Data.define(:name, :domain, :competitor, :overview, :previous, :keywords, :backlinks) do
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
    @snapshots = Market::SearchSnapshot.latest_by_site(@competitors.map(&:id))
    @last_pull = Market::SearchPull.latest_first.first
  end

  def sites
    @sites ||= [(site(nil, @profile.business_name, @profile.domain) if @profile.domain), *competitors.map { site(it, it.name, it.domain) }].compact
  end

  def pulled? = sites.any?(&:pulled?)
  def competitor_sites = sites.reject(&:own?)

  # Each tracked search: the site's position now and before, its page, and each competitor's position now.
  def tracked
    pages = Page.where(path: rankings.values.filter_map { it.first&.page_path }.uniq).index_by(&:path)
    keywords.map do |keyword|
      now, before = rankings[keyword.id]
      {keyword: keyword, ranking: now, position: now&.position, before: before&.position, page: now&.page_path && pages[now.page_path],
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
      keywords: kinds["keywords"]&.first, backlinks: kinds["backlinks"]&.first)
  end
end
