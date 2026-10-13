# frozen_string_literal: true

# A check DataForSEO does in its queue (Standard: about a third of Live's
# price) rather than at once: most of a pull when Settings › Market saves
# money that way (Google's results for each tracked search, every Maps point,
# AI Mode's, ChatGPT's, Gemini's and Bing Copilot's answers), and what only
# comes that way (Google reviews, Business Profile posts, Trustpilot and
# Tripadvisor reviews). Set at the pull, which pays for it; fetched for free
# when it's done (Market::QueuedTasksJob, every couple of minutes until each
# is in or gives up) and put to use like a live answer (#apply).
class Market::QueuedTask < ApplicationRecord
  KINDS = %w[reviews ranking maps_point ai_mode llm_scraper bing gbp_posts trustpilot tripadvisor].freeze
  STATES = %w[queued ready failed].freeze
  GIVE_UP_AFTER = 6.hours
  SNAPSHOTS = {"reviews" => "reviews", "gbp_posts" => "gbp_posts", "trustpilot" => "trustpilot", "tripadvisor" => "tripadvisor"}.freeze

  belongs_to :competitor, optional: true
  belongs_to :keyword, optional: true
  belongs_to :pull, class_name: "Market::SearchPull", optional: true

  serialize :meta, coder: JSON, type: Hash

  validates :kind, inclusion: {in: KINDS}
  validates :state, inclusion: {in: STATES}

  scope :queued, -> { where(state: "queued") }

  # Fetches every queued task that's done; answers how many are still waiting.
  def self.fetch_ready!(api: Market::Search::Api.new(client: Market::Search::Client.new))
    arrived = queued.order(:id).to_a.select { it.fetch!(api) }
    if arrived.any?
      Market::ReviewThemes.new.run! if arrived.any? { it.kind == "reviews" } && Market::Plan.ai_available?
      Market::Finding.refresh
    end
    queued.count
  end

  # True when it arrived.
  def fetch!(api)
    data = api.queued_result(self)
    transaction do
      update!(state: "ready", finished_at: Time.current, error: nil, attempts: attempts + 1, meta: meta.merge("result" => (kind == "maps_point") ? data : nil).compact)
      apply(data)
    end
    true
  rescue Market::Search::Client::NotReady
    posted_at < GIVE_UP_AFTER.ago ? give_up("DataForSEO hadn't done it after #{GIVE_UP_AFTER.inspect}") : update!(attempts: attempts + 1)
    false
  rescue Market::Search::Client::Error => error
    give_up(error.message)
    false
  end

  private

  def give_up(message)
    update!(state: "failed", error: message.truncate(500), attempts: attempts + 1, finished_at: Time.current)
    complete_scan if kind == "maps_point"
    Market::AiCheck.unanswered(keyword: keyword, platform: meta["platform"], pull: pull, error: message.truncate(300)).save! if keyword && meta["platform"].present?
  end

  # Puts an answer to use as a live one would be.
  def apply(data)
    if (snapshot = SNAPSHOTS[kind])
      Market::SearchSnapshot.create!(competitor: competitor, pull: pull, domain: domain, kind: snapshot, location: Market::Settings.current.country, data: data, taken_at: Time.current)
    elsif kind == "ranking"
      Market::SearchPull.keep_ranking(keyword, data, location: meta["location"], pull: pull, overview: meta["ai_overview"])
    elsif kind == "maps_point"
      complete_scan
    else
      Market::AiCheck.from_answer(keyword: keyword, platform: meta["platform"], text: data["text"], sources: data["sources"], businesses: data["businesses"],
        model: data["model"], prompt: keyword.keyword, pull: pull).save!
    end
  end

  # Once every point of a search's grid is in (or gave up), its scan is made from them.
  def complete_scan
    points = self.class.where(pull: pull, keyword: keyword, kind: "maps_point")
    return if points.queued.exists?

    answers = points.where(state: "ready").map do |task|
      {point: Market::LocalGrid::Point.new(row: task.meta["row"], col: task.meta["col"], lat: task.meta["lat"], lng: task.meta["lng"]), results: Array(task.meta["result"])}
    end
    Market::LocalScan.from_results(keyword: keyword, profile: Market::Profile.current, answers: answers, pull: pull).save! if answers.any?
  end
end
