# frozen_string_literal: true

# What customers say, read by the install's AI (the AI plugin) from the latest
# Google reviews of the site and each competitor: what they praise, what they
# complain about, and, for the business, what to answer and what to fix. Kept
# on each reviews snapshot as "themes"; never raises.
class Market::ReviewThemes
  SCHEMA = {
    type: "object", additionalProperties: false, required: %w[sites],
    properties: {sites: {type: "array", items: {
      type: "object", additionalProperties: false, required: %w[key praise complaints],
      properties: {key: {type: "string"}, praise: {type: "array", items: {type: "string"}, description: "Up to 4 things customers praise, each a short phrase."},
                   complaints: {type: "array", items: {type: "string"}, description: "Up to 4 things customers complain about, each a short phrase; [] when none."}}
    }}, advice: {type: "string", description: "For the business: two or three sentences on what its reviews and its competitors' say it should fix, say, or ask customers for."}}
  }.freeze

  def run!
    snapshots = Market::SearchSnapshot.latest_by_site(Market::Competitor.pluck(:id), kinds: ["reviews"]).transform_values { it.dig("reviews", 0) }.compact
    return if snapshots.empty?

    names = Market::Competitor.where(id: snapshots.keys.compact).to_h { [it.id, it.name] }
    prompt = snapshots.map do |id, snapshot|
      key = id ? "competitor:#{id}" : "site"
      reviews = Array(snapshot.data["reviews"]).first(40).map { "#{it["stars"]}★ #{it["text"].to_s.squish.truncate(300)}" }
      "#{key} (#{id ? names[id] : Market::Profile.current.business_name}), #{snapshot.data["rating"]}★ from #{snapshot.data["count"]}:\n#{reviews.join("\n")}"
    end.join("\n\n")
    answer = ::Ai.structured(purpose: "market_review_themes", fast: true, schema: SCHEMA, prompt: prompt,
      system: "You read local businesses' recent Google reviews and say plainly what customers praise and complain about, from the reviews only. The one keyed \"site\" is the business you advise.")
    themes = Array(answer["sites"]).index_by { it["key"] }
    snapshots.each do |id, snapshot|
      found = themes[id ? "competitor:#{id}" : "site"] or next
      snapshot.update!(data: snapshot.data.merge("themes" => found.slice("praise", "complaints"), "advice" => (id ? nil : answer["advice"])).compact)
    end
  rescue => error
    Rails.logger.error("[market] review themes: #{error.class}: #{error.message}")
    nil
  end
end
