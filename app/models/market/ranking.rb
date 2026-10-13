# frozen_string_literal: true

# Where everyone ranked for one tracked search at one check: the organic
# results (position, domain, url), the site's own position and page, and what
# else was on the page (a map pack, ads, questions).
class Market::Ranking < ApplicationRecord
  belongs_to :keyword
  belongs_to :pull, class_name: "Market::SearchPull", optional: true

  serialize :results, coder: JSON, type: Array
  serialize :features, coder: JSON, type: Array

  # The latest two checks of each keyword: { keyword_id => [latest, previous] }.
  def self.latest_for(keywords)
    ids = Array(keywords).map(&:id)
    return {} if ids.empty?

    latest = where(keyword_id: ids).group(:keyword_id).maximum(:id)
    previous = where(keyword_id: ids).where.not(id: latest.values).group(:keyword_id).maximum(:id)
    rows = where(id: latest.values + previous.values).index_by(&:id)
    latest.to_h { |keyword_id, id| [keyword_id, [rows[id], rows[previous[keyword_id]]].compact] }
  end

  # Where a domain (or one of its subdomains) ranked; nil when not in the results.
  def position_of(domain)
    domain = Market::Probe.normalize(domain)
    return if domain.blank?

    results.find { (row = Market::Probe.normalize(it["domain"]).to_s) == domain || row.end_with?(".#{domain}") }&.dig("position")
  end

  # The CMS page path the site ranked with ("home" for the front page), to
  # find its page: Search::Overview looks them all up at once.
  def page_path
    return unless url

    URI.parse(url).path.to_s.delete_prefix("/").chomp("/").presence || "home"
  rescue URI::InvalidURIError
    nil
  end
end
