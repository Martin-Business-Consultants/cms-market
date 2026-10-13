# frozen_string_literal: true

# The site's search data, pulled from DataForSEO in Market::SearchPullJob: for
# the site and each competitor, its overview and the keywords it ranks for;
# who else shares the site's keywords; backlinks when Settings › Market has
# them on; where everyone ranks for the tracked searches, from where the
# business's customers search (the profile's ZIP when it has one); and, with
# a ZIP and radius, each tracked search on Google Maps from every point of a
# grid across the area (Market::LocalScan).
#
# Each part stands alone: one that fails is noted and the rest carry on. A
# part pulled in the last FRESH_FOR isn't paid for twice unless the pull is
# forced. A wrong login, an empty account or the month's budget stops the
# pull where it is ("stopped"), keeping what it got. The findings are worked
# out again at the end (Market::Finding.refresh).
class Market::SearchPull < ApplicationRecord
  STATES = %w[queued running ready partial stopped failed].freeze
  STUCK_AFTER = 30.minutes

  belongs_to :user, optional: true
  has_many :requests, class_name: "Market::SearchRequest", foreign_key: :pull_id, dependent: :nullify, inverse_of: :pull

  serialize :notes, coder: JSON, type: Array

  validates :state, inclusion: {in: STATES}

  scope :latest_first, -> { order(id: :desc) }

  def self.running? = where(state: %w[queued running]).any?(&:working?)

  # Why a pull can't start now, or nil.
  def self.refusal(settings: Market::Settings.current)
    return "Connect DataForSEO in Settings › Market first" unless settings.search_connected?
    return "Set the site's address in Settings › General first" unless Market::Profile.current.domain
    return "A pull is already running" if running?

    "This month's search budget is spent: raise it in Settings › Market" unless settings.remaining_budget.positive?
  end

  # The most it could cost, said before it runs: every part for every site.
  def self.ceiling(settings: Market::Settings.current)
    api = Market::Search::Api::CEILINGS
    sites = 1 + Market::Competitor.watchable.count
    per_site = api[:overview] + api[:keywords] + (settings.backlinks? ? api[:backlinks] : 0)
    profile = Market::Profile.current
    local = profile.local? ? Market::Keyword.count * profile.local_grid**2 * api[:maps] : 0
    (sites * per_site + api[:competitors] + Market::Keyword.count * api[:ranking] + local).round(2)
  end

  def working? = state.in?(%w[queued running]) && updated_at > STUCK_AFTER.ago
  def run_later = Market::SearchPullJob.perform_later(self)

  # Called by Market::SearchPullJob. Never raises: what went wrong is in `notes` and `error`.
  def run!(api: nil)
    update!(state: "running", started_at: Time.current, notes: [])
    settings = Market::Settings.current
    @api = api || Market::Search::Api.new(client: Market::Search::Client.new(setting: settings, pull: self), setting: settings)
    @profile = Market::Profile.current
    raise Market::Search::Client::InvalidError.new("the site has no address (Settings › General) to pull for") unless @profile.domain

    gather(settings)
    finish(notes.any? { it.start_with?("Couldn't") } ? "partial" : "ready")
  rescue Market::Search::Client::Error => error
    Market::Settings.note_error(error.message) if error.is_a?(Market::Search::Client::AuthError) || error.is_a?(Market::Search::Client::FundsError)
    finish(Market::Search::Client.stopping?(error) ? "stopped" : "failed", error: error.message)
  rescue => error
    Rails.logger.error("[market] search pull #{id}: #{error.class}: #{error.message}")
    finish("failed", error: "#{error.class.name.demodulize}: #{error.message}")
  end

  private

  def gather(settings)
    sites = [[nil, @profile.domain], *Market::Competitor.watchable.ordered.map { [it, it.domain] }]
    sites.each do |competitor, domain|
      part(competitor, domain, "overview") { @api.overview(domain) }
      part(competitor, domain, "keywords") { @api.keywords(domain) }
      part(competitor, domain, "backlinks") { @api.backlinks(domain) } if settings.backlinks?
    end
    part(nil, @profile.domain, "competitors") { @api.competitors(@profile.domain) }
    rankings(@profile.local_center || @profile.search_location.presence || settings.country)
    local_scans if @profile.local?
  end

  # Each tracked search on Google Maps from every point of the grid; a point
  # that fails is noted and left out, a search scanned in the last day is kept.
  def local_scans
    points = Market::LocalGrid.points(@profile.local_center, radius_miles: @profile.local_radius_miles, size: @profile.local_grid)
    zoom = Market::LocalGrid.zoom(@profile.local_radius_miles)
    Market::Keyword.ordered.each do |keyword|
      if !force && Market::LocalScan.where(keyword: keyword, checked_at: Market::SearchSnapshot::FRESH_FOR.ago..).exists?
        note "Local grid for “#{keyword.keyword}”: scanned in the last day, kept"
        next
      end

      answers = points.filter_map do |point|
        {point: point, results: @api.maps(keyword.keyword, lat: point.lat, lng: point.lng, zoom: zoom)}
      rescue Market::Search::Client::Error => error
        raise if Market::Search::Client.stopping?(error)

        note "Couldn't check “#{keyword.keyword}” on Maps at #{point.lat},#{point.lng}: #{error.message}"
        nil
      end
      Market::LocalScan.from_results(keyword: keyword, profile: @profile, answers: answers, pull: self).save! if answers.any?
    end
  end

  # One part for one site, kept as a snapshot; skipped when fresh, noted when it fails.
  def part(competitor, domain, kind)
    if !force && Market::SearchSnapshot.fresh?(competitor, kind)
      note "#{kind.capitalize} for #{domain}: pulled in the last day, kept"
      return
    end

    data = yield
    Market::SearchSnapshot.create!(competitor: competitor, pull: self, domain: domain, kind: kind, location: Market::Settings.current.country,
      data: data, taken_at: Time.current)
  rescue Market::Search::Client::Error => error
    raise if Market::Search::Client.stopping?(error)

    note "Couldn't get #{kind} for #{domain}: #{error.message}"
  end

  def rankings(location)
    Market::Keyword.ordered.each do |keyword|
      answer = @api.ranking(keyword.keyword, location: location)
      ranking = keyword.rankings.new(pull: self, location: location.is_a?(Array) ? "#{@profile.local_zip} (#{location.join(",")})" : location, results: answer["results"], features: answer["features"], checked_at: Time.current)
      ranking.position = ranking.position_of(@profile.domain)
      ranking.url = ranking.results.find { it["position"] == ranking.position }&.dig("url")
      ranking.save!
    rescue Market::Search::Client::Error => error
      raise if Market::Search::Client.stopping?(error)

      note "Couldn't check “#{keyword.keyword}” from #{location.is_a?(Array) ? "the ZIP's centre" : location}: #{error.message}"
    end
  end

  def note(text) = (self.notes = Array(notes) + [text.truncate(300)])

  def finish(state, error: nil)
    update_columns(state: state, error: error&.truncate(500), notes: Array(notes), cost: requests.sum(:cost), finished_at: Time.current, updated_at: Time.current)
    Market::Finding.refresh
  rescue => failure
    Rails.logger.error("[market] finishing search pull #{id}: #{failure.class}: #{failure.message}")
  end
end
