# frozen_string_literal: true

# How the site's market is going, over time, for the Report screen and the
# API: a health score out of 100 made of the parts there's data for (search,
# rankings, maps, content, findings), each with the figure behind it, and the
# series the charts draw: visibility against each competitor, the tracked
# searches, Google Maps, the site's content beside theirs, findings opened and
# resolved, the plan's progress and what DataForSEO cost. Read-only.
class Market::Report
  Part = Data.define(:key, :label, :score, :detail, :path)
  Series = Data.define(:name, :points, :own) # points: [[Time, Float]]

  WEEKS = 12

  def initialize(since: 6.months.ago)
    @since = since
    @profile = Market::Profile.current
    @competitors = Market::Competitor.watchable.by_threat.to_a
  end

  attr_reader :since

  # The parts there's data for, each 0–100.
  def parts
    @parts ||= [search_part, rankings_part, ai_part, maps_part, reviews_part, content_part, findings_part, *google_parts].compact
  end

  def score = parts.any? ? (parts.sum(&:score).to_f / parts.size).round : nil

  def grade
    return unless score

    if score >= 75 then "Strong"
    elsif score >= 50 then "Fair"
    elsif score >= 25 then "Weak"
    else "Poor"
    end
  end

  # Estimated monthly search traffic, the site and each competitor.
  def visibility = @visibility ||= site_series("organic_traffic")

  # The site's own keywords: all it ranks for, and in the top 10.
  def own_keywords
    rows = overview_snapshots.select { it.competitor_id.nil? }
    [Series.new(name: "Keywords", points: rows.map { [it.taken_at, it.data["organic_keywords"].to_f] }, own: true),
      Series.new(name: "In the top 10", points: rows.map { [it.taken_at, it.data["top_10"].to_f] }, own: false)]
  end

  # The tracked searches at each check: their average position (a miss counts as just past the depth) and how many are in the top 10.
  def rankings
    @rankings ||= begin
      miss = Market::Search::Api::RANKING_DEPTH + 1
      days = Market::Ranking.where(checked_at: @since..).pluck(:checked_at, :position).group_by { it[0].to_date }.sort
      [Series.new(name: "Average position", points: days.map { |day, rows| [day.to_time, (rows.sum { it[1] || miss }.to_f / rows.size).round(1)] }, own: true),
        Series.new(name: "In the top 10", points: days.map { |day, rows| [day.to_time, rows.count { it[1].to_i.between?(1, 10) }.to_f] }, own: false)]
    end
  end

  # AI search by week: the share of AI answers to the tracked searches that named the business, and that cited its site.
  def ai_search
    @ai_search ||= begin
      weeks = Market::AiCheck.where(checked_at: @since.., answered: true).pluck(:checked_at, :mentioned, :cited).group_by { it[0].to_date.beginning_of_week }.sort
      [Series.new(name: "Named it (%)", points: weeks.map { |week, rows| [week.to_time, (rows.count { it[1] } * 100.0 / rows.size).round] }, own: true),
        Series.new(name: "Cited its site (%)", points: weeks.map { |week, rows| [week.to_time, (rows.count { it[2] } * 100.0 / rows.size).round] }, own: false)]
    end
  end

  # Sites linking in, by month (Backlinks history): the site and each competitor.
  def links
    @links ||= begin
      names = @competitors.to_h { [it.id, it.name] }
      Market::SearchSnapshot.latest_by_site(@competitors.map(&:id), kinds: ["backlink_history"]).filter_map do |id, kinds|
        snapshot = kinds.dig("backlink_history", 0) or next
        Series.new(name: id ? names[id] : @profile.business_name, own: id.nil?,
          points: Array(snapshot.data["months"]).map { [Time.zone.parse(it["date"]), it["referring_domains"].to_f] }.select { it[0] && it[0] >= @since })
      end.sort_by { it.own ? 0 : 1 }
    end
  end

  # Google Maps across the area at each scan: the average position, and the share of points in the top 3.
  def maps
    @maps ||= begin
      days = Market::LocalScan.where(checked_at: @since..).pluck(:checked_at, :average_position, :top3_share).group_by { it[0].to_date }.sort
      [Series.new(name: "Average position", points: days.map { |day, rows| [day.to_time, (rows.sum { it[1] }.to_f / rows.size).round(1)] }, own: true),
        Series.new(name: "Top 3 share (%)", points: days.map { |day, rows| [day.to_time, (rows.sum { it[2] } * 100 / rows.size).round] }, own: false)]
    end
  end

  # Posts in the last 90 days, at each reading: the site and each competitor.
  def posting
    @posting ||= begin
      readings = Market::Reading.where(taken_at: @since..).where(competitor_id: [nil, *@competitors.map(&:id)]).order(:taken_at).to_a
      names = @competitors.to_h { [it.id, it.name] }
      readings.select(&:read?).group_by(&:competitor_id).map do |id, rows|
        Series.new(name: id ? names[id] : @profile.business_name, points: rows.map { [it.taken_at, it.sitemap["posts_last_90_days"].to_f] }, own: id.nil?)
      end.sort_by { it.own ? 0 : 1 }
    end
  end

  # The latest reading's content counts, the site first: [name, pages, posts in 90 days, location pages, service pages, own?].
  def content
    @content ||= begin
      latest = Market::Reading.latest_for(@competitors)
      [[@profile.business_name, Market::Reading.own_latest, true], *@competitors.map { [it.name, latest[it.id], false] }].filter_map do |name, reading, own|
        next unless reading&.read?

        sitemap = reading.sitemap
        [name, sitemap["pages"].to_i, sitemap["posts_last_90_days"].to_i, sitemap["locations"].to_i, sitemap["services"].to_i, own]
      end
    end
  end

  # Findings opened and resolved each week.
  def findings_by_week
    @findings_by_week ||= begin
      start = WEEKS.weeks.ago.beginning_of_week
      rows = Market::Finding.where("first_seen_at >= ? OR resolved_at >= ?", start, start).pluck(:first_seen_at, :resolved_at)
      weeks = (0...WEEKS).map { start + it.weeks }
      [Series.new(name: "Found", points: weeks.map { |week| [week, rows.count { it[0]&.between?(week, week + 1.week) }.to_f] }, own: false),
        Series.new(name: "Resolved", points: weeks.map { |week| [week, rows.count { it[1]&.between?(week, week + 1.week) }.to_f] }, own: true)]
    end
  end

  def open_findings = @open_findings ||= Market::Finding.open.group(:severity).count
  def opportunities = @opportunities ||= Market::Opportunity.group(:state).count

  # DataForSEO spend by month.
  def spend
    Market::SearchPull.where(created_at: @since..).pluck(:created_at, :cost).group_by { it[0].strftime("%Y-%m") }.sort
      .map { |month, rows| [Date.parse("#{month}-01"), rows.sum { it[1].to_d }] }
  end

  def goals = @goals ||= Market::Goal.active.ordered.includes(:keyword).to_a

  def any_data? = parts.any? || visibility.any? || posting.any?

  # Google's own figures, from the Google plugin when it's connected; nil for each service that isn't.
  def search_console = google(:search_console)
  def analytics = google(:analytics)
  def business_profile = google(:business_profile)

  # Clicks and impressions from Google search, by week (Search Console).
  def google_clicks = weekly(search_console&.daily, {"Clicks" => 1}, own: "Clicks")
  def google_impressions = weekly(search_console&.daily, {"Impressions" => 2}, own: "Impressions")

  # Sessions and key events, by week (Analytics).
  def google_sessions = weekly(analytics&.daily, {"Sessions" => 1}, own: "Sessions")
  def google_key_events = weekly(analytics&.daily, {"Key events" => 3}, own: "Key events")

  # Calls, website clicks and directions from the Business Profile, by week.
  def google_actions
    days = business_profile&.daily.to_a.map { [Date.parse(it["date"]), it["calls"].to_i, it["website"].to_i, it["directions"].to_i] }
    weekly(days, {"Calls" => 1, "Website clicks" => 2, "Directions" => 3}, own: "Calls")
  end

  private

  def google(service)
    return unless defined?(::Google) && ::Google.respond_to?(service)

    (@google ||= {})[service] ||= ::Google.public_send(service)
  end

  # Days ([Date, figure…]) added up by week, one series per {name => index}; part-weeks (the first and the last) dropped.
  def weekly(days, columns, own:)
    return [] if days.blank?

    weeks = days.group_by { it[0].beginning_of_week }.sort.reject { |_, rows| rows.size < 7 }
    columns.map do |name, index|
      Series.new(name: name, points: weeks.map { |week, rows| [week.to_time, rows.sum { it[index].to_f }] }, own: name == own)
    end
  end

  # Moved since the 28 days before, as a score: unchanged is 50, doubled or more is 100.
  def trend_score(now, before)
    return 50 if before.to_f.zero?

    (50 + (now.to_f - before) * 50 / before).clamp(0, 100).round
  end

  def google_parts
    [(console = search_console) && console.totals && Part.new(key: :google_search, label: "Clicks from Google",
      score: trend_score(console.totals[:clicks], console.totals_before&.dig(:clicks)),
      detail: "#{console.totals[:clicks]} clicks in 28 days#{" (#{console.totals_before[:clicks]} the 28 before)" if console.totals_before}, Search Console", path: :market_search_path),
      (ga = analytics) && ga.totals && Part.new(key: :google_enquiries, label: "Enquiries",
        score: trend_score(ga.totals[:key_events], ga.totals_before&.dig(:key_events)),
        detail: "#{ga.totals[:key_events]} key events from #{ga.totals[:sessions]} sessions in 28 days#{" (#{ga.totals_before[:key_events]} the 28 before)" if ga.totals_before}, Analytics", path: :market_report_path),
      (profile = business_profile) && profile.totals && Part.new(key: :google_profile, label: "Business Profile",
        score: ((profile.reviews["average"].to_f / 5 * 60) + trend_score(profile.totals[:calls], profile.totals_before&.dig(:calls)) * 0.4).round,
        detail: "#{profile.reviews["average"] || "No"} stars from #{profile.reviews["total"].to_i} reviews; #{profile.totals[:calls]} calls in 28 days#{" (#{profile.totals_before[:calls]} before)" if profile.totals_before}", path: :market_maps_path)].compact
  end

  def overview_snapshots
    @overview_snapshots ||= Market::SearchSnapshot.where(kind: "overview", taken_at: @since..).where(competitor_id: [nil, *@competitors.map(&:id)]).order(:taken_at).to_a
  end

  # Each site's figure at each pull; for visits, a year of DataForSEO's monthly history first (where it was pulled), so the chart starts full.
  def site_series(key)
    names = @competitors.to_h { [it.id, it.name] }
    pulled = overview_snapshots.group_by(&:competitor_id)
    history = (key == "organic_traffic") ? Market::SearchSnapshot.latest_by_site(@competitors.map(&:id), kinds: ["rank_history"]).transform_values { it.dig("rank_history", 0) }.compact : {}
    (pulled.keys | history.keys).map do |id|
      monthly = Array(history[id]&.data&.dig("months")).map { [Date.parse("#{it["month"]}-01").to_time, it["traffic"].to_f] }.select { it[0] >= @since }
      first = Array(pulled[id]).map(&:taken_at).min
      points = monthly.reject { first && it[0] >= first.beginning_of_month } + Array(pulled[id]).map { [it.taken_at, it.data[key].to_f] }
      Series.new(name: id ? names[id] : @profile.business_name, points: points.sort_by(&:first), own: id.nil?)
    end.reject { it.points.empty? }.sort_by { it.own ? 0 : 1 }
  end


  def latest_values(series) = series.to_h { [it.name, it.points.last&.last.to_f] }

  # The site's share of the search traffic among the sites watched, against an even share.
  def search_part
    latest = latest_values(visibility)
    own = visibility.find(&:own)&.points&.last&.last
    return if own.nil? || latest.size < 2

    total = latest.values.sum
    share = total.positive? ? own / total : 0
    fair = 1.0 / latest.size
    Part.new(key: :search, label: "Search visibility", score: (share / fair * 50).clamp(0, 100).round,
      detail: "#{(share * 100).round}% of the search traffic among the #{latest.size} sites watched (DataForSEO's estimate)", path: :market_search_path)
  end

  def rankings_part
    latest = Market::Ranking.latest_for(Market::Keyword.all).values.filter_map(&:first)
    return if latest.empty?

    top10 = latest.count { it.position.to_i.between?(1, 10) }
    top3 = latest.count { it.position.to_i.between?(1, 3) }
    Part.new(key: :rankings, label: "Tracked searches", score: (((top10 + top3).to_f / (latest.size * 2)) * 100).round,
      detail: "#{top10} of #{latest.size} on page one, #{top3} in the top 3", path: :market_search_path)
  end

  def ai_part
    latest = Market::AiCheck.latest_for(Market::Keyword.all).values.flat_map(&:values).select(&:answered)
    return if latest.empty?

    named = latest.count(&:mentioned)
    cited = latest.count(&:cited)
    Part.new(key: :ai, label: "AI search", score: ((named + cited * 0.5) * 100.0 / latest.size).clamp(0, 100).round,
      detail: "Named in #{named} of #{latest.size} AI answers to the tracked searches, its site cited in #{cited}", path: :market_search_path)
  end

  def reviews_part
    reviews = Market::SearchSnapshot.where(competitor_id: nil, kind: "reviews").latest_first.first&.data or return
    list = Array(reviews["reviews"])
    return if list.empty?

    answered = list.count { it["answered"] } * 100 / list.size
    Part.new(key: :reviews, label: "Reviews", score: ((reviews["rating"].to_f / 5 * 70) + answered * 0.3).clamp(0, 100).round,
      detail: "#{reviews["rating"]}★ from #{reviews["count"]}; #{answered}% of the latest #{list.size} answered", path: :market_search_path)
  end

  def maps_part
    latest = Market::LocalScan.latest_for(Market::Keyword.all).values.filter_map(&:first)
    return if latest.empty?

    share = latest.sum(&:top3_share) / latest.size
    Part.new(key: :maps, label: "Google Maps", score: (share * 100).round,
      detail: "In the map's top 3 at #{(share * 100).round}% of the points across the area", path: :market_maps_path)
  end

  # The site's posting and location pages against the busiest competitor's.
  def content_part
    own = content.find(&:last)
    theirs = content.reject(&:last)
    return if own.nil? || theirs.empty?

    posts = [theirs.map { it[2] }.max, 1].max
    places = theirs.map { it[3] }.max
    score = ([own[2].to_f / posts, 1].min * 60) + (places.positive? ? [own[3].to_f / places, 1].min * 40 : 40)
    Part.new(key: :content, label: "Content", score: score.round,
      detail: "#{own[2]} posts in 90 days (the busiest competitor: #{posts}); #{own[3]} location pages (most: #{places})", path: :market_competitors_path)
  end

  def findings_part
    return if Market::Finding.none?

    high = open_findings["high"].to_i
    medium = open_findings["medium"].to_i
    Part.new(key: :findings, label: "Findings", score: (100 - high * 15 - medium * 5).clamp(0, 100),
      detail: "#{high} high and #{medium} medium open", path: :market_findings_path)
  end
end
