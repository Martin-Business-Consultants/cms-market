# frozen_string_literal: true

# Reads a goal's metric from what Market already has: the Google plugin's
# Search Console, Analytics and Business Profile (the last 28 days), the
# tracked searches' latest Google check and Maps scan, the latest AI answers,
# the latest Google reviews, and DataForSEO's visibility estimate.
module Market::Goal::Metrics
  module_function

  def read(metric, keyword = nil)
    case metric
    when "calls" then google(:business_profile)&.totals&.dig(:calls)
    when "enquiries" then google(:analytics)&.totals&.dig(:key_events)
    when "google_clicks" then google(:search_console)&.totals&.dig(:clicks)
    when "visibility" then Market::SearchSnapshot.where(competitor_id: nil, kind: "overview").latest_first.first&.data&.dig("organic_traffic")
    when "search_position" then keyword && Market::Ranking.latest_for([keyword])[keyword.id]&.first&.then { it.position || Market::Search::Api::RANKING_DEPTH + 1 }
    when "maps_top3" then keyword && Market::LocalScan.latest_for([keyword])[keyword.id]&.first&.then { (it.top3_share * 100).round }
    when "ai_named" then ai_named
    when "reviews" then reviews&.dig("count") || google(:business_profile)&.reviews&.dig("total")
    when "rating" then reviews&.dig("rating") || google(:business_profile)&.reviews&.dig("average")
    end&.then { it.to_d }
  end

  def google(service)
    return unless defined?(::Google) && ::Google.respond_to?(service)

    ::Google.public_send(service)
  end

  def ai_named
    checks = Market::AiCheck.latest_for(Market::Keyword.all).values.flat_map(&:values).select(&:answered)
    (checks.count(&:mentioned) * 100.0 / checks.size).round if checks.any?
  end

  def reviews = Market::SearchSnapshot.where(competitor_id: nil, kind: "reviews").latest_first.first&.data
end
