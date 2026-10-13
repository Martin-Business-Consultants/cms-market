# frozen_string_literal: true

# Something worth doing to win the site's market, on one channel, sized by
# impact and effort, and when: from a plan Claude drafted, or added by a
# person. Open until it's planned (a draft page started for it, or marked
# planned), done, or dismissed.
class Market::Opportunity < ApplicationRecord
  CHANNELS = {
    "seo" => "Search (SEO)", "local" => "Local and maps", "content" => "Content", "paid_search" => "Paid search",
    "paid_social" => "Paid social", "social" => "Social", "email" => "Email", "reviews" => "Reviews and reputation",
    "website" => "Website and conversion", "brand" => "Brand and positioning", "partnerships" => "Partnerships and referrals"
  }.freeze
  IMPACTS = %w[high medium low].freeze
  EFFORTS = %w[low medium high].freeze
  HORIZONS = {"now" => "This month", "next" => "This quarter", "later" => "Later"}.freeze
  STATES = %w[open planned done dismissed].freeze
  ACTIVE = %w[open planned].freeze

  belongs_to :plan, optional: true
  belongs_to :page, class_name: "::Page", optional: true

  normalizes :title, with: ->(title) { title.strip.squeeze(" ") }

  validates :title, presence: true
  validates :channel, inclusion: {in: CHANNELS.keys}
  validates :impact, inclusion: {in: IMPACTS}
  validates :effort, inclusion: {in: EFFORTS}
  validates :horizon, inclusion: {in: HORIZONS.keys}
  validates :state, inclusion: {in: STATES}

  scope :active, -> { where(state: ACTIVE) }
  scope :open, -> { where(state: "open") }

  # Best first: most impact for least effort, then soonest.
  def self.by_priority(records) = records.sort_by { [-it.priority, HORIZONS.keys.index(it.horizon), it.id] }

  def priority = (3 - IMPACTS.index(impact)) * 2 + (3 - EFFORTS.index(effort))
  def channel_label = CHANNELS.fetch(channel)
  def horizon_label = HORIZONS.fetch(horizon)
  def active? = state.in?(ACTIVE)
  def quick_win? = impact != "low" && effort == "low"

  # A draft page for it, titled for it, with what it's for in the page's
  # description: the work starts in the CMS, and the opportunity is planned.
  def start_page(by:, title: nil)
    title = title.presence || self.title
    page = ::Page.new(title: title.truncate(150), slug: free_slug(title), status: "draft",
      locale: Setting.get("general")["default_locale"].presence || "en", blocks: [], frontmatter: {},
      seo: {"meta_description" => [detail, evidence].compact_blank.join(" ").truncate(155)}.compact_blank)
    transaction do
      page.save!
      update!(page: page, state: "planned", decided_by_name: person(by), decided_at: Time.current)
    end
    page.track_creation if page.respond_to?(:track_creation)
    page
  end

  def complete(by:) = decide("done", by)
  def dismiss(by:) = decide("dismissed", by)
  def plan_it(by:) = decide("planned", by)
  def reopen = update(state: "open", decided_by_name: nil, decided_at: nil)

  private

  def decide(state, by) = update(state: state, decided_by_name: person(by), decided_at: Time.current)
  def person(user) = user.try(:name).presence || user.try(:email)

  def free_slug(title)
    base = title.to_s.parameterize.first(60).delete_suffix("-").presence || "page"
    taken = ::Page.where(parent_id: nil).where("slug = ? OR slug LIKE ?", base, "#{base}-%").pluck(:slug)
    return base unless taken.include?(base)

    (2..).lazy.map { "#{base}-#{it}" }.find { !taken.include?(it) }
  end
end
