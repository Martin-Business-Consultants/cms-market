# frozen_string_literal: true

# A business competing for the site's customers: how (direct, indirect, or the
# one the business would most like to be), how much of a threat, what it does
# well and badly, and its website, read from outside every week (Readings).
class Market::Competitor < ApplicationRecord
  KINDS = {"direct" => "Direct", "indirect" => "Indirect", "aspirational" => "Aspirational"}.freeze
  THREATS = %w[high medium low].freeze

  has_many :readings, -> { latest_first }, dependent: :delete_all, inverse_of: :competitor
  has_many :search_snapshots, dependent: :delete_all

  normalizes :name, with: ->(name) { name.strip.squeeze(" ") }
  normalizes :website, with: ->(url) { url.strip.chomp("/").then { it.match?(%r{\Ahttps?://}i) || it.empty? ? it : "https://#{it}" }.presence }

  validates :name, presence: true
  validates :website, format: {with: %r{\Ahttps?://\S+\.\S+\z}i, message: "should be an address like https://example.com"}, allow_nil: true
  validates :kind, inclusion: {in: KINDS.keys}
  validates :threat, inclusion: {in: THREATS}
  validate :one_per_domain

  before_save { self.domain = Market::Probe.normalize(website) }

  scope :ordered, -> { order(:name) }
  scope :by_threat, -> { in_order_of(:threat, THREATS).order(:name) }
  scope :watchable, -> { where.not(domain: [nil, ""]) }

  CHECK_EVERY = 7.days

  # The competitor with this website's domain, or by this name when there's no website.
  def self.matching(name:, website: nil)
    domain = Market::Probe.normalize(website)
    (domain && find_by(domain: domain)) || where("LOWER(name) = ?", name.to_s.strip.downcase).first
  end

  def kind_label = KINDS.fetch(kind)
  def host = domain || website
  def latest_reading = readings.first
  def check_due? = domain.present? && (latest_reading.nil? || latest_reading.taken_at < CHECK_EVERY.ago)
  def check_now = Market::Reading.take(self)
  def check_later = Market::CheckJob.perform_later(self)

  private

  def one_per_domain
    domain = Market::Probe.normalize(website)
    return if domain.blank?

    other = self.class.where(domain: domain).where.not(id: id).first
    errors.add(:website, "is already #{other.name}'s") if other
  end
end
