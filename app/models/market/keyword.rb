# frozen_string_literal: true

# A search the business wants to win ("emergency dentist grand rapids"),
# checked on every pull from where its customers search: where the site ranks,
# with which of its pages, and where each competitor does.
class Market::Keyword < ApplicationRecord
  SOURCES = %w[manual gap plan ranked].freeze
  MAX = 100

  has_many :rankings, -> { order(checked_at: :desc, id: :desc) }, dependent: :delete_all
  has_many :local_scans, -> { order(checked_at: :desc, id: :desc) }, dependent: :delete_all

  normalizes :keyword, with: ->(keyword) { keyword.strip.squeeze(" ").downcase }

  validates :keyword, presence: true, length: {maximum: 200}, uniqueness: {message: "is already tracked"}
  validates :source, inclusion: {in: SOURCES}

  scope :ordered, -> { order(:keyword) }

  # Several at once, one a line or comma-separated: answers [added, skipped].
  def self.track(text, source: "manual")
    words = text.to_s.split(/[\n,]+/).map { it.strip.squeeze(" ").downcase }.compact_blank.uniq
    tracked = pluck(:keyword)
    fresh = (words - tracked).first([MAX - tracked.size, 0].max)
    added = fresh.filter_map { |word| create(keyword: word, source: source.presence_in(SOURCES) || "manual").then { it if it.persisted? } }
    [added, words.size - added.size]
  end
end
