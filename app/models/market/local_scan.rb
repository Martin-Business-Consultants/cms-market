# frozen_string_literal: true

# One tracked search checked on Google Maps from every point of a grid across
# the profile's ZIP and radius (Market::LocalGrid): at each point, where the
# business showed (nil when it didn't, in the top 20) and the first three
# names; across the area, its average position (counting a miss as 21), the
# share of points it's in the top 3 at, and who leads the most points.
class Market::LocalScan < ApplicationRecord
  MISS = 21
  DEPTH = 20

  belongs_to :keyword
  belongs_to :pull, class_name: "Market::SearchPull", optional: true

  serialize :points, coder: JSON, type: Array
  serialize :leaders, coder: JSON, type: Array

  # The latest two scans of each keyword: { keyword_id => [latest, previous] }.
  def self.latest_for(keywords)
    ids = Array(keywords).map(&:id)
    return {} if ids.empty?

    latest = where(keyword_id: ids).group(:keyword_id).maximum(:id)
    previous = where(keyword_id: ids).where.not(id: latest.values).group(:keyword_id).maximum(:id)
    rows = where(id: latest.values + previous.values).index_by(&:id)
    latest.to_h { |keyword_id, id| [keyword_id, [rows[id], rows[previous[keyword_id]]].compact] }
  end

  # Builds a scan from each point's Maps results ({point:, results:}), finding the business by its website or its name.
  def self.from_results(keyword:, profile:, answers:, pull: nil)
    points = answers.map do |answer|
      results = Array(answer[:results])
      mine = results.find { ours?(it, profile) }
      {"row" => answer[:point].row, "col" => answer[:point].col, "lat" => answer[:point].lat, "lng" => answer[:point].lng,
       "position" => mine&.dig("position"), "top" => results.first(3).map { it["title"] }}
    end
    positions = points.map { it["position"] || MISS }
    leaders = answers.flat_map { Array(it[:results]).first(3).reject { |row| ours?(row, profile) } }
      .group_by { it["title"] }.map { |title, rows| {"title" => title, "domain" => rows.first["domain"], "top3_points" => rows.size} }
      .sort_by { -it["top3_points"] }.first(5)
    new(keyword: keyword, pull: pull, zip: profile.local_zip, center_lat: profile.local_center[0], center_lng: profile.local_center[1],
      radius_miles: profile.local_radius_miles, grid: profile.local_grid, points: points, leaders: leaders,
      average_position: (positions.sum.to_f / positions.size).round(1), top3_share: (points.count { it["position"].to_i.between?(1, 3) }.to_f / points.size).round(2),
      found_points: points.count { it["position"] }, checked_at: Time.current)
  end

  def self.ours?(row, profile)
    domain = Market::Probe.normalize(row["domain"]).to_s
    own = profile.domain.to_s
    (own.present? && (domain == own || domain.end_with?(".#{own}"))) || row["title"].to_s.casecmp?(profile.maps_name.to_s)
  end

  def rows = points.group_by { it["row"] }.sort.map { |_, row| row.sort_by { it["col"] } }
  def missed? = found_points.zero?
end
