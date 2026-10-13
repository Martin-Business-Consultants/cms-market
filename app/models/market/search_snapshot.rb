# frozen_string_literal: true

# What DataForSEO said about one website (the site's own when there's no
# competitor) at one time, by kind: overview (visibility), keywords (what it
# ranks for), competitors (who shares its keywords: the site's only) and
# backlinks. Kept, so movement shows between pulls.
class Market::SearchSnapshot < ApplicationRecord
  KINDS = %w[overview keywords competitors backlinks].freeze
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
