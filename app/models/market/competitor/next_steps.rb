# frozen_string_literal: true

# What to do about one competitor next, worked out from what's known: each
# step a title, why, and the one action that takes it (a path, and the HTTP
# method and params a button sends). First what's needed to know them (their
# website read, their search data, sizing them up), then what the findings
# about them say to do, then the moves to beat them and the searches they win.
class Market::Competitor::NextSteps
  Step = Data.define(:key, :title, :detail, :label, :path, :method, :params, :tone) do
    def button? = method != :get
  end

  include Rails.application.routes.url_helpers

  def initialize(competitor, settings: Market::Settings.current, findings: Market::Finding.open.to_a, tracked: Market::Keyword.pluck(:keyword))
    @competitor = competitor
    @settings = settings
    @findings = findings
    @tracked = tracked
  end

  def all
    @all ||= [website, reading, search, assessment, *finding_steps, *move_steps, keywords].compact
  end

  def first = all.first
  def size = all.size

  # The open findings about this competitor.
  def findings
    @findings.select { it.key.end_with?(":#{@competitor.domain}") || Array(it.evidence["leaders"]).any? { |leader| leader["title"].to_s.casecmp?(@competitor.name) } ||
      Array(it.evidence["competitors"]).any? { |row| row.is_a?(Hash) && row["competitor"] == @competitor.name } }
  end

  private

  # Every button brings the person back to the competitor.
  def step(key, title, detail, label, path, method: :post, params: {}, tone: :normal)
    params = params.merge(return_to: market_competitor_path(@competitor)) unless method == :get
    Step.new(key:, title:, detail:, label:, path:, method:, params:, tone:)
  end

  def website
    return if @competitor.domain

    step(:website, "Add their website", "Nothing about them can be read or compared without it.", "Add it", edit_market_competitor_path(@competitor), method: :get, tone: :urgent)
  end

  def reading
    return unless @competitor.domain

    latest = @competitor.latest_reading
    if latest.nil?
      step(:read, "Read their website", "To see their pages, posts, locations and the tools they run, beside the site's.", "Read it", market_competitor_check_path(@competitor), tone: :urgent)
    elsif !latest.read?
      step(:read, "Their website couldn't be read", latest.error.to_s.truncate(160), "Try again", market_competitor_check_path(@competitor))
    elsif latest.taken_at < Market::Competitor::CHECK_EVERY.ago
      step(:read, "Read their website again", "Last read #{latest.taken_at.to_date.to_fs(:long)}; it's read weekly.", "Read it", market_competitor_check_path(@competitor))
    end
  end

  def search
    return unless @settings.search_connected? && @competitor.domain
    return if Market::SearchSnapshot.where(competitor: @competitor, kind: "keywords").exists?

    step(:search, "Pull their search data", "To see the keywords they win and how visible they are, beside the site.", "Pull search data", market_search_pulls_path)
  end

  def assessment
    return if @competitor.assessing?
    return unless Market::Plan.ai_available?

    if !@competitor.assessed?
      step(:assess, "Size them up", "The AI reads what's known about them and says what they do well, where they're weak, and the moves that would beat them.",
        "Size them up with AI", market_competitor_assessment_path(@competitor), tone: :urgent)
    elsif @competitor.analysed_at < 30.days.ago
      step(:assess, "Size them up again", "Last done #{@competitor.analysed_at.to_date.to_fs(:long)}.", "Size them up", market_competitor_assessment_path(@competitor))
    end
  end

  def finding_steps
    findings.filter_map do |finding|
      next if finding.opportunity

      step(:"finding_#{finding.id}", finding.title, finding.detail.to_s.truncate(200), "Make it an opportunity", market_finding_opportunity_path(finding),
        tone: (finding.severity == "high") ? :urgent : :normal)
    end
  end

  def move_steps
    @competitor.moves.each_with_index.filter_map do |move, index|
      next if @competitor.move_opportunity(index)

      step(:"move_#{index}", move["title"], move["detail"].to_s.truncate(200), "Make it an opportunity", market_competitor_move_path(@competitor, index))
    end
  end

  # The searches they're on page one for that aren't tracked.
  def keywords
    snapshot = Market::SearchSnapshot.where(competitor: @competitor, kind: "keywords").latest_first.first or return
    best = Array(snapshot.data["keywords"]).select { it["position"].to_i.between?(1, 10) }.sort_by { -it["volume"].to_i }.map { it["keyword"] } - @tracked
    return if best.empty?

    step(:keywords, "Track the searches they win", "They're on Google's first page for #{best.first(3).join(", ")}#{" and more" if best.size > 3}.",
      "Track #{[best.size, 5].min}", market_keywords_path, params: {keyword: {keywords: best.first(5).join("\n"), source: "gap"}})
  end
end
