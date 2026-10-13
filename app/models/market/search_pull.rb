# frozen_string_literal: true

# The site's search data, pulled from DataForSEO in Market::SearchPullJob: for
# the site and each competitor, its overview and the keywords it ranks for;
# who else shares the site's keywords; backlinks when Settings › Market has
# them on; where everyone ranks for the tracked searches, from where the
# business's customers search (the profile's ZIP when it has one); and, with
# a ZIP and radius, each tracked search on Google Maps from every point of a
# grid across the area (Market::LocalScan). AI search: each tracked search
# asked of the AIs chosen in Settings › Market (Market::AiCheck: Google's AI
# Overview with the results page, AI Mode, ChatGPT, Gemini, Perplexity,
# Claude), and the AI share of voice from DataForSEO's database of real AI
# answers. And the extras chosen there: keyword facts, who wins the tracked
# searches, Business Profiles, site health, web mentions.
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
    keywords = Market::Keyword.count
    per_site = api[:overview] + api[:keywords] + api[:ai_overview] + (settings.backlinks? ? api[:backlinks] + api[:backlink_history] : 0) +
      (settings.extra?(:business_profiles) ? api[:business_profile] : 0) + (settings.extra?(:web_mentions) ? api[:web_mentions] : 0) +
      (settings.extra?(:reviews) ? api[:reviews] : 0)
    profile = Market::Profile.current
    local = profile.local? ? keywords * profile.local_grid**2 * api[:maps] : 0
    ai = keywords * settings.ai_platforms.sum do |platform|
      {"google_ai_overview" => 0.005, "google_ai_mode" => api[:ai_mode], "chat_gpt" => api[:llm_scraper], "gemini" => api[:llm_scraper]}.fetch(platform, api[:llm_response])
    end
    extras = (settings.extra?(:keyword_facts) ? api[:keyword_facts] + api[:ai_volume] + api[:serp_competitors] + api[:local_volume] : 0) +
      (settings.backlinks? && sites > 1 ? api[:link_gap] : 0) +
      (settings.extra?(:ai_mentions) ? 2 * (api[:ai_mentions] + api[:ai_answers]) : 0) + (settings.extra?(:site_health) ? 2 * api[:site_health] : 0)
    (sites * per_site + api[:competitors] + keywords * api[:ranking] + local + ai + extras).round(2)
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
    Market::QueuedTasksJob.set(wait: 2.minutes).perform_later if @queued
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
    @settings = settings
    sites = [[nil, @profile.domain], *Market::Competitor.watchable.ordered.map { [it, it.domain] }]
    sites.each do |competitor, domain|
      part(competitor, domain, "overview") { @api.overview(domain) }
      part(competitor, domain, "keywords") { @api.keywords(domain) }
      part(competitor, domain, "ai_overview") { @api.ai_overview_keywords(domain) }
      if settings.backlinks?
        part(competitor, domain, "backlinks") { @api.backlinks(domain) }
        part(competitor, domain, "backlink_history") { @api.backlink_history(domain) }
      end
      part(competitor, domain, "web_mentions") { @api.web_mentions(competitor ? competitor.name : @profile.business_name) } if settings.extra?(:web_mentions)
    end
    part(nil, @profile.domain, "competitors") { @api.competitors(@profile.domain) }
    location = @profile.local_center || @profile.search_location.presence || settings.country
    rankings(location)
    ai_checks(location)
    local_scans if @profile.local?
    market_extras(settings, sites)
  end

  # Keyword facts, who wins the tracked searches, AI share of voice and what AI says, site
  # health, and each Business Profile (found by the Maps id the local scans saw).
  def market_extras(settings, sites)
    words = Market::Keyword.ordered.pluck(:keyword)
    if settings.extra?(:keyword_facts) && words.any?
      part(nil, @profile.domain, "keyword_facts") do
        facts = @api.keyword_facts(words)
        volumes = begin
          @api.ai_volume(words)
        rescue Market::Search::Client::Error => error
          raise if Market::Search::Client.stopping?(error)

          note "Couldn't get AI search volumes: #{error.message}"
          {}
        end
        area, local = local_volumes(words)
        {"area" => area, "keywords" => words.to_h { [it, facts.fetch(it, {}).merge("ai_volume" => volumes[it], "local_volume" => local.dig(it, "volume"), "local_cpc" => local.dig(it, "cpc")).compact] }}
      end
      part(nil, @profile.domain, "serp_competitors") { @api.serp_competitors(words) }
    end
    if settings.extra?(:ai_mentions)
      keys = sites.to_h { |competitor, domain| [competitor ? "competitor:#{competitor.id}" : "site", domain] }.first(10).to_h
      platforms = (settings.country == "United States" && settings.language_code == "en") ? %w[google chat_gpt] : %w[google]
      if keys.size >= 2
        part(nil, @profile.domain, "ai_mentions") { platforms.to_h { [it, @api.ai_mentions(keys, platform: it)] } }
      else
        note "AI share of voice compares the site with its competitors: add one to see it"
      end
      part(nil, @profile.domain, "ai_answers") { {"answers" => platforms.flat_map { @api.ai_answers(@profile.domain, platform: it) }} }
    end
    part(nil, @profile.domain, "site_health") { @api.site_health(@profile.website.presence || "https://#{@profile.domain}") } if settings.extra?(:site_health)
    part(nil, @profile.domain, "link_gap") { @api.link_gap(@profile.domain, sites.filter_map { |competitor, domain| domain if competitor }) } if settings.backlinks? && sites.size > 1
    business_profiles(sites) if settings.extra?(:business_profiles) || settings.extra?(:reviews)
  end

  # Searches a month in the business's city (Google Ads), when Google Ads knows the city: [area, {keyword => {"volume", "cpc"}}].
  def local_volumes(words)
    area = Market::AdsLocation.new(profile: @profile, settings: @settings).name(@api)
    return [nil, {}] unless area

    [area, @api.local_volume(words, area)]
  rescue Market::Search::Client::Error => error
    raise if Market::Search::Client.stopping?(error)

    note "Couldn't get searches a month in the business's city: #{error.message}"
    [nil, {}]
  end

  # Sets a queued task for each site's latest Google reviews; they're fetched when DataForSEO has done them.
  def queue_reviews(competitor, domain, cid)
    return if !force && Market::SearchSnapshot.fresh?(competitor, "reviews")
    return if Market::QueuedTask.queued.where(kind: "reviews", competitor: competitor).exists?

    task_id, endpoint = @api.post_reviews(cid, extended: competitor.nil?)
    Market::QueuedTask.create!(kind: "reviews", competitor: competitor, pull: self, domain: domain, task_id: task_id, endpoint: endpoint, posted_at: Time.current)
    @queued = true
  rescue Market::Search::Client::Error => error
    raise if Market::Search::Client.stopping?(error)

    note "Couldn't ask for #{competitor ? competitor.name : @profile.business_name}'s reviews: #{error.message}"
  end

  def business_profiles(sites)
    scans = Market::LocalScan.latest_for(Market::Keyword.all).values.filter_map(&:first)
    own = scans.filter_map(&:own_cid).first
    leaders = scans.flat_map(&:leaders)
    sites.each do |competitor, domain|
      cid = competitor ? leaders.find { |row| row["cid"] && (row["title"].to_s.casecmp?(competitor.name) || (row["domain"] && Market::Probe.normalize(row["domain"]) == domain)) }&.dig("cid") : own
      next note("Business Profile for #{competitor ? competitor.name : @profile.business_name}: not found on Maps yet") unless cid

      part(competitor, domain, "business_profile") { @api.business_profile(cid) } if @settings.extra?(:business_profiles)
      queue_reviews(competitor, domain, cid) if @settings.extra?(:reviews)
    end
  end

  # Each tracked search asked of each AI chosen (Google's AI Overview comes with the results
  # page, in #rankings); one asked in the last day is kept unless the pull is forced.
  def ai_checks(location)
    platforms = @settings.ai_platforms - ["google_ai_overview"]
    return if platforms.empty?

    brands = Market::AiCheck::Brands.new(profile: @profile)
    models = {}
    Market::Keyword.ordered.each do |keyword|
      platforms.each do |platform|
        if !force && Market::AiCheck.where(keyword: keyword, platform: platform, checked_at: Market::SearchSnapshot::FRESH_FOR.ago..).exists?
          next
        end

        answer = case platform
        when "google_ai_mode" then @api.ai_mode(keyword.keyword, location: location)
        when "chat_gpt", "gemini" then @api.llm_scraper(platform, keyword.keyword)
        else
          models[platform] ||= model_for(platform)
          @api.llm_response(platform, ai_prompt(keyword), model: models[platform], city: @profile.search_location.to_s.split(",").first.presence)
        end
        Market::AiCheck.from_answer(keyword: keyword, platform: platform, text: answer["text"], sources: answer["sources"], businesses: answer["businesses"],
          model: answer["model"], prompt: platform.in?(%w[perplexity claude]) ? ai_prompt(keyword) : keyword.keyword, pull: self, brands: brands).save!
      rescue Market::Search::Client::Error => error
        raise if Market::Search::Client.stopping?(error)

        Market::AiCheck.unanswered(keyword: keyword, platform: platform, pull: self, error: error.message.truncate(300)).save!
        note "Couldn't ask #{Market::AiCheck.platform_name(platform)} “#{keyword.keyword}”: #{error.message}"
      end
    end
  end

  # How a customer would ask an assistant: the search, as a request for businesses.
  def ai_prompt(keyword) = "#{keyword.keyword} — which businesses would you recommend, and why?"

  # The platform's model to ask: one that searches the web, Claude's Sonnet or Perplexity's Sonar first.
  def model_for(platform)
    wanted = (platform == "claude") ? /sonnet/ : /\Asonar\z|\Asonar-pro/
    models = @api.models(platform)
    choice = models.find { it["model_name"].to_s.match?(wanted) && (platform == "perplexity" || it["web_search_supported"]) } ||
      models.find { platform == "perplexity" || it["web_search_supported"] }
    choice&.dig("model_name") || ((platform == "claude") ? "claude-sonnet-4-5" : "sonar")
  rescue Market::Search::Client::Error
    (platform == "claude") ? "claude-sonnet-4-5" : "sonar"
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
    overview = @settings&.ai_platform?("google_ai_overview")
    brands = Market::AiCheck::Brands.new(profile: @profile) if overview
    Market::Keyword.ordered.each do |keyword|
      answer = @api.ranking(keyword.keyword, location: location, ai_overview: overview)
      ranking = keyword.rankings.new(pull: self, location: location.is_a?(Array) ? "#{@profile.local_zip} (#{location.join(",")})" : location, results: answer["results"],
        features: answer["features"], local_pack: answer["local_pack"], questions: answer["questions"], checked_at: Time.current)
      ranking.position = ranking.position_of(@profile.domain)
      ranking.url = ranking.results.find { it["position"] == ranking.position }&.dig("url")
      ranking.save!
      if overview
        found = answer["ai_overview"]
        check = found ? Market::AiCheck.from_answer(keyword: keyword, platform: "google_ai_overview", text: found["text"], sources: found["sources"], pull: self, brands: brands,
          prompt: keyword.keyword) : Market::AiCheck.unanswered(keyword: keyword, platform: "google_ai_overview", pull: self)
        check.answered = true if found
        check.save!
      end
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
