# frozen_string_literal: true

# A task DataForSEO does in its queue (Standard method) rather than at once:
# Google reviews, which only come that way. Set at a pull (it's paid for then),
# fetched for free when it's done (Market::QueuedTasksJob, every few minutes
# until each is ready or gives up), and kept as a snapshot like the rest. When
# reviews arrive, the AI reads them for what customers praise and complain about.
class Market::QueuedTask < ApplicationRecord
  KINDS = %w[reviews].freeze
  STATES = %w[queued ready failed].freeze
  GIVE_UP_AFTER = 6.hours

  belongs_to :competitor, optional: true
  belongs_to :pull, class_name: "Market::SearchPull", optional: true

  validates :kind, inclusion: {in: KINDS}
  validates :state, inclusion: {in: STATES}

  scope :queued, -> { where(state: "queued") }

  # Fetches every queued task that's done; answers how many are still waiting.
  def self.fetch_ready!(api: Market::Search::Api.new(client: Market::Search::Client.new))
    arrived = queued.order(:id).to_a.count { it.fetch!(api) }
    Market::ReviewThemes.new.run! if arrived.positive? && Market::Plan.ai_available?
    Market::Finding.refresh if arrived.positive?
    queued.count
  end

  # True when it arrived.
  def fetch!(api)
    data = api.queued_result(self)
    Market::SearchSnapshot.create!(competitor: competitor, pull: pull, domain: domain, kind: kind, location: Market::Settings.current.country, data: data, taken_at: Time.current)
    update!(state: "ready", finished_at: Time.current, error: nil, attempts: attempts + 1)
    true
  rescue Market::Search::Client::NotReady
    if posted_at < GIVE_UP_AFTER.ago
      update!(state: "failed", error: "DataForSEO hadn't done it after #{GIVE_UP_AFTER.inspect}", attempts: attempts + 1, finished_at: Time.current)
    else
      update!(attempts: attempts + 1)
    end
    false
  rescue Market::Search::Client::Error => error
    update!(state: "failed", error: error.message.truncate(500), attempts: attempts + 1, finished_at: Time.current)
    false
  end
end
