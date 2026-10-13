# frozen_string_literal: true

# A marketing goal, measured: one of METRICS (each read from what Market
# already knows: Search Console, Analytics, the Business Profile, the tracked
# searches, AI answers, DataForSEO), where it stood when set (baseline), the
# target and the date. Its progress is how far from the baseline to the target
# it's come; it's on pace when that's at least as far as the time gone by.
class Market::Goal < ApplicationRecord
  STATES = %w[active met dropped].freeze
  # metric => label, unit, whether lower is better, whether it's for one search, and where it's read from.
  METRICS = {
    "calls" => {label: "Calls from Google a month", unit: "calls", source: "Business Profile (Google plugin)"},
    "enquiries" => {label: "Enquiries from the site a month", unit: "key events", source: "Google Analytics (Google plugin)"},
    "google_clicks" => {label: "Clicks from Google a month", unit: "clicks", source: "Search Console (Google plugin)"},
    "visibility" => {label: "Visits from search a month (estimated)", unit: "visits", source: "DataForSEO"},
    "search_position" => {label: "Place on Google for a search", unit: "position", lower: true, search: true, source: "Google, checked live"},
    "maps_top3" => {label: "Share of the area in the Maps top 3 for a search", unit: "%", search: true, source: "Google Maps, checked live"},
    "ai_named" => {label: "Share of AI answers that name the business", unit: "%", source: "AI answers, checked live"},
    "linking_sites" => {label: "Sites linking to the site", unit: "sites", source: "DataForSEO Backlinks"},
    "reviews" => {label: "Google reviews", unit: "reviews", source: "Business Profile"},
    "rating" => {label: "Google rating", unit: "★", source: "Business Profile"}
  }.freeze

  belongs_to :keyword, optional: true
  has_many :opportunities, dependent: :nullify

  validates :metric, inclusion: {in: METRICS.keys}
  validates :state, inclusion: {in: STATES}
  validates :target, numericality: true
  validates :keyword, presence: {message: "is needed for this goal"}, if: -> { METRICS.dig(metric, :search) }

  scope :active, -> { where(state: "active") }
  scope :ordered, -> { order(:position, :id) }

  before_create { self.baseline ||= current }

  def info = METRICS.fetch(metric)
  def lower? = info[:lower] == true
  def unit = info[:unit]
  def title = info[:search] && keyword ? "#{info[:label]}: “#{keyword.keyword}”" : info[:label]

  # Where it stands now, from the latest data; nil until there's some.
  def current = @current ||= Metrics.read(metric, keyword)

  # How far from the baseline to the target, 0–100; nil without both ends.
  def progress
    return unless current && baseline
    return 100 if lower? ? current <= target : current >= target

    span = (target - baseline).to_f
    return 0 if span.zero?

    ((current - baseline) / span * 100).clamp(0, 100).round
  end

  def reached? = current.present? && (lower? ? current <= target : current >= target)

  # Whether it's come as far as the time gone by says it should; nil without a date or data.
  def on_pace?
    return unless progress && due_on

    days = (due_on - created_at.to_date).to_f
    return true if days <= 0

    progress >= ((Date.current - created_at.to_date) / days * 100).clamp(0, 100) - 10
  end

  def describe(value)
    return "—" if value.nil?

    number = (value.to_f == value.to_i) ? value.to_i : value.to_f.round(1)
    case unit
    when "%" then "#{number}%"
    when "★" then "#{number}★"
    when "position" then "##{number}"
    else "#{ActiveSupport::NumberHelper.number_to_delimited(number)} #{unit}"
    end
  end

  # The goal as the API gives it.
  def self.as_api(goal)
    {id: goal.id, title: goal.title, metric: goal.metric, keyword_id: goal.keyword_id, unit: goal.unit, source: goal.info[:source], state: goal.state,
     baseline: goal.baseline&.to_f, current: goal.current&.to_f, target: goal.target.to_f, due_on: goal.due_on, why: goal.why, progress: goal.progress, on_pace: goal.on_pace?}
  end
end
