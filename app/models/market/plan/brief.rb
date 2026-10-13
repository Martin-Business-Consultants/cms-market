# frozen_string_literal: true

# Everything a plan is drafted from, written out for the AI: the profile, the
# site's content in the CMS and its live reading, each competitor with how it
# competes and its latest reading, the search data, the tracked rankings, the
# open findings, and the opportunities already there.
class Market::Plan::Brief
  def initialize
    @profile = Market::Profile.current
    @competitors = Market::Competitor.by_threat.to_a
    @readings = Market::Reading.latest_for(@competitors)
    @search = Market::Search::Overview.new
  end

  def to_s
    [business_part, goals_part, content_part, own_site_part, competitors_part, search_part, rankings_part, local_part, links_part, ai_part, findings_part, work_part].compact.join("\n\n")
  end

  private

  attr_reader :profile, :competitors, :readings, :search

  # The links (DataForSEO Backlinks), when they've been pulled.
  def links_part
    links = Market::Links.new(profile: profile)
    links.facts if links.pulled?
  end

  # The goals, with where each stands: every opportunity should serve one.
  def goals_part
    goals = Market::Goal.active.ordered.to_a
    return "Goals: none set. Aim at more customers from search, maps and AI generally." if goals.empty?

    "Goals (give each opportunity the id of the goal it serves):\n" + goals.map do |goal|
      "goal #{goal.id}: #{goal.title}: now #{goal.describe(goal.current)}, target #{goal.describe(goal.target)}#{" by #{goal.due_on.to_fs(:long)}" if goal.due_on}" \
        "#{" (behind pace)" if goal.on_pace? == false}#{" — #{goal.why}" if goal.why.present?}"
    end.join("\n")
  end

  # How the AIs answer the tracked searches: named or not, and who instead.
  def ai_part
    overview = Market::Search::Overview.new
    return unless overview.ai_checked?

    lines = overview.ai_summary.map { |platform, counts| "#{Market::AiCheck.platform_name(platform)}: named the business in #{counts[:named]} of #{counts[:answered]} answers, cited its site in #{counts[:cited]}" }
    ["AI search (each tracked search asked of each AI):", *lines,
      "Named instead: #{overview.ai_named_others.map { "#{it[0]} (#{it[1]})" }.join(", ").presence || "no one"}",
      "Sites the AIs cite: #{overview.ai_cited_domains.first(8).map(&:first).join(", ").presence || "none"}"].join("\n")
  end

  def business_part
    lines = ["Business: #{profile.business_name}", "Website: #{profile.website || "not set"}"]
    lines << "Local area: within #{profile.local_radius_miles.to_i} miles of #{profile.local_zip} (#{profile.local_place})" if profile.local?
    Market::Profile::FIELDS.each { |field| lines << "#{Market::Profile::LABELS[field]}: #{profile.public_send(field)}" if profile.public_send(field) }
    lines.join("\n")
  end

  # What the CMS holds: pages, and each collection's entries and how recently they were published.
  def content_part
    pages = ::Page.where(status: "published")
    lines = ["Published pages: #{pages.count} (#{pages.order(updated_at: :desc).limit(40).pluck(:path).join(", ")})"]
    if defined?(::Collection) && defined?(::CollectionEntry)
      published = ::CollectionEntry.where(status: "published")
      counts = published.group(:collection_id).count
      recent = published.where(published_at: 90.days.ago..).group(:collection_id).count
      ::Collection.where(id: counts.keys).find_each do |collection|
        lines << "#{collection.name}: #{counts[collection.id]} published, #{recent[collection.id].to_i} in the last 90 days"
      end
    end
    "What's on the site, in the CMS:\n#{lines.join("\n")}"
  end

  def own_site_part
    reading = Market::Reading.own_latest
    return "The live site hasn't been read from outside yet." unless reading

    "The live site (read #{reading.taken_at.to_date.to_fs(:long)}):\n#{JSON.pretty_generate(reading.facts)}"
  end

  def competitors_part
    return "No competitors listed yet." if competitors.empty?

    "Competitors:\n" + competitors.map do |competitor|
      reading = readings[competitor.id]
      ["## #{competitor.name} (#{competitor.kind_label.downcase}, #{competitor.threat} threat)#{" — #{competitor.host}" if competitor.host}",
        ("Notes: #{competitor.notes}" if competitor.notes.present?),
        ("Strengths: #{competitor.strengths}" if competitor.strengths.present?),
        ("Weaknesses: #{competitor.weaknesses}" if competitor.weaknesses.present?),
        reading ? "Website (read #{reading.taken_at.to_date.to_fs(:long)}): #{JSON.generate(reading.facts.except("domain"))}" : "Website not read yet.",
        ("Recent changes: #{reading.differences.join("; ")}" if reading&.differences.present?)].compact.join("\n")
    end.join("\n\n")
  end

  def search_part
    pulled = search.sites.select(&:pulled?)
    return if pulled.empty?

    lines = pulled.map { "- #{it.name}#{" (this business)" if it.own?}, #{it.domain} (#{it.overview.taken_at.to_date.to_fs(:long)}): #{JSON.generate(it.overview.data)}" }
    own = search.sites.find(&:own?)
    top = Array(own&.keywords&.data&.dig("keywords")).first(15).map { "#{it["keyword"]} (##{it["position"]}, #{it["volume"]}/mo)" }
    "Search visibility (DataForSEO, #{Market::Settings.current.country}; traffic is estimated monthly visits):\n#{lines.join("\n")}" +
      (top.any? ? "\nIts biggest keywords: #{top.join("; ")}" : "")
  end

  def rankings_part
    rows = search.tracked.filter_map do |row|
      ranking = row[:ranking] or next
      others = row[:competitors].filter_map { |domain, position| "#{domain} ##{position}" if position }
      "- “#{row[:keyword].keyword}”: this site #{row[:position] ? "##{row[:position]}#{" with /#{row[:page].path}" if row[:page]}" : "not in the top #{Market::Search::Api::RANKING_DEPTH}"}" \
        "#{"; #{others.join(", ")}" if others.any?}#{"; also on the page: #{ranking.features.join(", ")}" if ranking.features.any?}"
    end
    "Tracked searches:\n#{rows.join("\n")}" if rows.any?
  end

  # Each tracked search on Google Maps across the ZIP's grid.
  def local_part
    rows = search.tracked.filter_map do |row|
      scan = row[:local] or next
      leaders = scan.leaders.first(3).map { "#{it["title"]} (top 3 at #{it["top3_points"]})" }
      "- “#{row[:keyword].keyword}”: average position #{scan.average_position}, top 3 at #{(scan.top3_share * scan.points.size).round} of #{scan.points.size} points" \
        "#{", not found at #{scan.points.size - scan.found_points}" if scan.found_points < scan.points.size}#{"; leaders: #{leaders.join(", ")}" if leaders.any?}"
    end
    return if rows.empty?

    profile = Market::Profile.current
    "Local search on Google Maps, a #{profile.local_grid}x#{profile.local_grid} grid within #{profile.local_radius_miles.to_i} miles of #{profile.local_zip}:\n#{rows.join("\n")}"
  end

  def findings_part
    findings = Market::Finding.open.by_severity.limit(25).to_a
    return if findings.empty?

    "Findings from the data (act on these; the evidence is exact):\n" +
      findings.map { "- [#{it.severity}] #{it.title}#{" — #{it.detail}" if it.detail.present?} #{JSON.generate(it.evidence)}".truncate(900) }.join("\n")
  end

  def work_part
    opportunities = Market::Opportunity.order(:id).last(40)
    return "No opportunities yet." if opportunities.empty?

    "Already listed (don't repeat):\n" + opportunities.map { "- [#{it.state}] #{it.channel_label}: #{it.title}" }.join("\n")
  end
end
