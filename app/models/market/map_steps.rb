# frozen_string_literal: true

# What to do next about one tracked search on Google Maps, worked out from
# its latest scan (Market::LocalScan): set the area up, scan it, tell Market
# the business's name on Maps, watch who leads, close the review gap, win the
# parts of the area it's weak in. Each step the one action that takes it.
class Market::MapSteps
  Step = Market::Competitor::NextSteps::Step
  DIRECTIONS = [%w[north-west north north-east], %w[west centre east], %w[south-west south south-east]].freeze

  include Rails.application.routes.url_helpers

  def initialize(keyword, scan, profile: Market::Profile.current, settings: Market::Settings.current)
    @keyword = keyword
    @scan = scan
    @profile = profile
    @settings = settings
  end

  def all
    @all ||= if !@profile.local?
      [step(:setup, "Set the area up", "A ZIP and radius in the profile: Maps is checked from a grid of points across it.", "Set it up", edit_market_profile_path, method: :get, tone: :urgent)]
    elsif @scan.nil?
      [(step(:pull, "Scan it", "The next pull checks this search on Google Maps from every point of the grid.", "Pull search data", market_search_pulls_path, tone: :urgent) if @settings.search_connected?)].compact
    else
      [name, answer_reviews, *watch, reviews, weak_area].compact
    end
  end

  def first = all.first
  def size = all.size

  # Where it's weak: the part of the grid (north-east, centre…) with the most points outside the top 3.
  def weak_area
    misses = @scan.points.reject { it["position"].to_i.between?(1, 3) }
    return if misses.empty?

    third = ->(index) { (index * 3 / @scan.grid).clamp(0, 2) }
    area, count = misses.group_by { DIRECTIONS[third.call(it["row"])][third.call(it["col"])] }.transform_values(&:size).max_by(&:last)
    task(:weak_area, "Win the #{area} of the area", "Outside the top 3 at #{misses.size} of #{@scan.points.size} points, #{count} of them to the #{area}. " \
      "A page for the towns there, posts that name them, and Google Business Profile posts about them help.",
      channel: "local", named: "Win “#{@keyword.keyword}” on Maps to the #{area}")
  end

  private

  def step(key, title, detail, label, path, method: :post, params: {}, tone: :normal)
    params = params.merge(return_to: market_maps_path(keyword: @keyword.id)) unless method == :get
    Step.new(key:, title:, detail:, label:, path:, method:, params:, tone:)
  end

  # A step that's made an opportunity on the plan; gone once it's there.
  def task(key, title, detail, channel:, named:, tone: :normal)
    return if Market::Opportunity.active.exists?(title: named)

    step(key, title, detail, "Make it an opportunity", market_opportunities_path, tone: tone,
      params: {opportunity: {title: named, detail: detail, evidence: "Google Maps, “#{@keyword.keyword}”, #{@scan.checked_at.to_date.to_fs(:long)}",
                             channel: channel, impact: "high", effort: "medium", horizon: "now"}})
  end

  def name
    return unless @scan.missed?

    step(:name, "It wasn't found anywhere", "Not in the top 20 at any point. If its name on Google Maps differs from #{@profile.business_name}, tell Market what it is; if it has no Google Business Profile, that's the first job.",
      "Set its name on Maps", edit_market_profile_path, method: :get, tone: :urgent)
  end

  # Reviews on the Business Profile nobody has answered (the Google plugin, when it's connected).
  def answer_reviews
    profile = defined?(::Google) && ::Google.respond_to?(:business_profile) && ::Google.business_profile
    waiting = profile ? profile.unanswered_reviews : []
    return if waiting.empty?

    low = waiting.count { it["stars"].to_i <= 3 }
    step(:answer_reviews, "Answer #{waiting.size} Google #{(waiting.size == 1) ? "review" : "reviews"}",
      "#{"#{low} of them 3 stars or fewer. " if low.positive?}Answered reviews tell the next customer, and Google, that the business listens.",
      "Open the reviews", "https://business.google.com/reviews", method: :get, tone: low.positive? ? :urgent : :normal)
  end

  # The leaders that aren't watched yet.
  def watch
    known = Market::Competitor.pluck(:name, :domain)
    @scan.leaders.first(3).filter_map do |leader|
      next if known.any? { |name, domain| name.casecmp?(leader["title"].to_s) || (domain && domain == Market::Probe.normalize(leader["domain"])) }

      step(:"watch_#{leader["title"].parameterize}", "Watch #{leader["title"]}", "In the top 3 at #{leader["top3_points"]} of #{@scan.points.size} points.",
        "Watch them", new_market_competitor_path(name: leader["title"], website: (leader["domain"] && "https://#{leader["domain"]}")), method: :get)
    end
  end

  def reviews
    own = @scan.own_rating
    leader = @scan.leaders.max_by { it["reviews"].to_i }
    return unless leader && leader["reviews"].to_i > own.to_h["reviews"].to_i * 1.5 && leader["reviews"].to_i >= 10

    count = ->(number) { ActiveSupport::NumberHelper.number_to_delimited(number.to_i) }
    have = own ? "#{count.call(own["reviews"])} at #{own["rating"]}" : "none showing"
    task(:reviews, "Close the review gap", "#{leader["title"]} shows #{count.call(leader["reviews"])} reviews at #{leader["rating"]}; the business has #{have}. " \
      "Reviews weigh heavily on who Maps shows: ask every happy customer, and answer every review.",
      channel: "reviews", named: "Ask for Google reviews: #{leader["title"]} has #{count.call(leader["reviews"])}", tone: :urgent)
  end
end
