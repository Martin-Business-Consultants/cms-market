# frozen_string_literal: true

# What DataForSEO said about one website (the site's own when there's no
# competitor) at one time, by kind: overview (visibility), keywords (what it
# ranks for), ai_overview (the searches Google's AI Overviews cite it for),
# backlinks and backlink_history, business_profile (its Google profile),
# reviews (its latest Google reviews, from a queued task) and web_mentions; and for
# the market as a whole (on the site's own row): competitors (who shares its
# keywords), serp_competitors (who wins the tracked searches),
# keyword_facts, ai_mentions (AI share of voice), ai_answers (what AI says
# about it), link_gap (sites linking to competitors, not it) and site_health. Kept, so movement shows between pulls.
class Market::SearchSnapshot < ApplicationRecord
  KINDS = %w[overview keywords competitors backlinks ai_overview business_profile web_mentions
    serp_competitors keyword_facts ai_mentions ai_answers site_health reviews backlink_history link_gap].freeze
  FRESH_FOR = 20.hours

  belongs_to :competitor, optional: true
  belongs_to :pull, class_name: "Market::SearchPull", optional: true

  serialize :data, coder: JSON, type: Hash

  validates :kind, inclusion: {in: KINDS}

  scope :latest_first, -> { order(taken_at: :desc, id: :desc) }

  # The latest two of each kind for the site (nil) and each competitor, in
  # three queries: { competitor_id or nil => { kind => [latest, previous] } }.
  def self.latest_by_site(competitor_ids = Market::Competitor.pluck(:id), kinds: KINDS)
    scope = where(competitor_id: [nil, *competitor_ids], kind: kinds)
    latest = scope.group(:competitor_id, :kind).maximum(:id)
    previous = scope.where.not(id: latest.values).group(:competitor_id, :kind).maximum(:id)
    rows = where(id: latest.values + previous.values).index_by(&:id)
    latest.each_with_object(Hash.new { |hash, key| hash[key] = {} }) do |((competitor_id, kind), id), found|
      found[competitor_id][kind] = [rows[id], rows[previous[[competitor_id, kind]]]]
    end
  end

  def self.fresh?(competitor, kind) = where(competitor: competitor, kind: kind, taken_at: FRESH_FOR.ago..).exists?
end
