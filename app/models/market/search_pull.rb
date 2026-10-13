# frozen_string_literal: true

# The site's search data, pulled from DataForSEO in Market::SearchPullJob.
#
# For the site and each competitor: its visibility and keywords, the searches
# Google's AI Overviews cite it for, and, as Settings › Market chooses, its
# links, a year of history and its best pages, its Google Business Profile
# (with its reviews, posts and customers' questions) and the web talking
# about it. For the tracked searches: where everyone ranks on Google, from
# where the business's customers search (with the map pack, the questions
# people ask and the AI Overview); each asked of the AIs chosen
# (Market::AiCheck); each on Google Maps from a grid across the area
# (Market::LocalScan); what each is worth, when it peaks, and what to write
# around it. And for the business in AI: its share of voice, what answers say
# about it, and the sites AI cites for its topic.
#
# Saving money (the default), the checks that can wait are queued with
# DataForSEO (Standard, about a third of Live's price: Market::QueuedTask)
# and arrive within minutes; the rest come at once. Each part stands alone:
# one that fails is noted and the rest carry on. A part pulled lately isn't
# paid for twice unless the pull is forced. A wrong login, an empty account
# or the month's budget stops the pull where it is ("stopped"), keeping what
# it got. The findings are worked out again at the end, and again as queued
# results arrive.
class Market::SearchPull < ApplicationRecord
  STATES = %w[queued running ready partial stopped failed].freeze
  STUCK_AFTER = 30.minutes
  MONTHLY = 25.days
  WEEKLY = 6.days

  belongs_to :user, optional: true
  has_many :requests, class_name: "Market::SearchRequest", foreign_key: :pull_id, dependent: :nullify, inverse_of: :pull
  has_many :queued_tasks, class_name: "Market::QueuedTask", foreign_key: :pull_id, dependent: :nullify, inverse_of: :pull

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
    queued = Market::Search::Api::QUEUED
    sites = 1 + Market::Competitor.watchable.count
    keywords = Market::Keyword.count
    per_site = api[:overview] + api[:keywords] + api[:ai_overview] +
      (settings.backlinks? ? api[:backlinks] + api[:backlink_history] + api[:linked_pages] : 0) +
      (settings.extra?(:profiles) ? api[:business_profile] + api[:reviews] + api[:gbp_qa] + queued["gbp_posts"] : 0) +
      (settings.extra?(:other_reviews) ? queued["trustpilot"] + queued["tripadvisor"] : 0) +
      (settings.extra?(:web_mentions) ? api[:web_mentions] : 0) +
      (settings.extra?(:history) ? api[:rank_history] + api[:relevant_pages] : 0)
    profile = Market::Profile.current
    cheap = settings.queue?
    local = profile.local? ? keywords * profile.local_grid**2 * (cheap ? queued["maps_point"] : api[:maps]) : 0
    ai = keywords * settings.ai_platforms.sum do |platform|
      case platform
      when "google_ai_overview" then cheap ? 0.001 : 0.005
      when "google_ai_mode" then cheap ? queued["ai_mode"] : api[:ai_mode]
      when "chat_gpt", "gemini" then cheap ? queued["llm_scraper"] : api[:llm_scraper]
      when "bing_copilot" then cheap ? queued["bing"] : api[:ranking]
      else api[:llm_response]
      end
    end
    extras = (settings.extra?(:keywords) ? api[:keyword_facts] + api[:ai_volume] + api[:serp_competitors] + api[:local_volume] + api[:content_ideas] : 0) +
      (settings.backlinks? && sites > 1 ? api[:link_gap] : 0) +
      (settings.backlinks? ? api[:referring_domains] + api[:link_changes] + api[:broken_links] + api[:anchors] + api[:link_competitors] : 0) +
      (settings.extra?(:ai_visibility) ? 2 * (api[:ai_mentions] + api[:ai_answers]) + api[:ai_topics] + api[:ai_history] : 0) +
      (settings.extra?(:site_health) ? 2 * api[:site_health] : 0)
    rankings = keywords * (cheap ? queued["ranking"] : api[:ranking])
    (sites * per_site + api[:competitors] + rankings + local + ai + extras).round(2)
  end

  # Keeps one Google check of a tracked search (live or queued): who ranks where, the
  # site's own position and page, and, when asked for, the AI Overview as an AI check.
  def self.keep_ranking(keyword, answer, location:, pull: nil, overview: false, profile: Market::Profile.current, brands: nil)
    ranking = keyword.rankings.new(pull: pull, location: location, results: answer["results"], features: answer["features"],
      local_pack: answer["local_pack"], questions: answer["questions"], checked_at: Time.current)
    ranking.position = ranking.position_of(profile.domain)
    ranking.url = ranking.results.find { it["position"] == ranking.position }&.dig("url")
    ranking.save!
    return ranking unless overview

    found = answer["ai_overview"]
    check = if found
      Market::AiCheck.from_answer(keyword: keyword, platform: "google_ai_overview", text: found["text"], sources: found["sources"], pull: pull,
        brands: brands || Market::AiCheck::Brands.new(profile: profile), prompt: keyword.keyword).tap { it.answered = true }
    else
      Market::AiCheck.unanswered(keyword: keyword, platform: "google_ai_overview", pull: pull)
    end
    check.save!
    ranking
  end

  def working? = state.in?(%w[queued running]) && updated_at > STUCK_AFTER.ago
  def run_later = Market::SearchPullJob.perform_later(self)
  def arriving = queued_tasks.queued.count

  # Called by Market::SearchPullJob. Never raises: what went wrong is in `notes` and `error`.
  def run!(api: nil)
    update!(state: "running", started_at: Time.current, notes: [])
    settings = Market::Settings.current
    @api = api || Market::Search::Api.new(client: Market::Search::Client.new(setting: settings, pull: self), setting: settings)
    @profile = Market::Profile.current
    raise Market::Search::Client::InvalidError.new("the site has no address (Settings › General) to pull for") unless @profile.domain

    gather(settings)
    Market::QueuedTasksJob.set(wait: 1.minute).perform_later if queued_tasks.queued.exists?
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
      links(competitor, domain) if settings.backlinks?
      part(competitor, domain, "web_mentions") { @api.web_mentions(competitor ? competitor.name : @profile.business_name) } if settings.extra?(:web_mentions)
      if settings.extra?(:history)
        part(competitor, domain, "rank_history", fresh_for: MONTHLY) { @api.rank_history(domain) }
        part(competitor, domain, "relevant_pages", fresh_for: MONTHLY) { @api.relevant_pages(domain) }
      end
    end
    part(nil, @profile.domain, "competitors") { @api.competitors(@profile.domain) }
    @location = @profile.local_center || @profile.search_location.presence || settings.country
    settings.queue? ? queue_searches : live_searches
    market_extras(settings, sites)
  end

  # A site's links (DataForSEO Backlinks): its profile and its year, daily; its most-linked pages
  # weekly; and for the site itself, weekly, who links to it, what's been won and lost, links to
  # pages that are gone, the words they link with, and the sites with a link profile like its own.
  def links(competitor, domain)
    part(competitor, domain, "backlinks") { @api.backlinks(domain) }
    part(competitor, domain, "backlink_history") { @api.backlink_history(domain) }
    part(competitor, domain, "linked_pages", fresh_for: WEEKLY) { @api.linked_pages(domain) }
    return if competitor

    part(nil, domain, "referring_domains", fresh_for: WEEKLY) { @api.referring_domains(domain) }
    part(nil, domain, "link_changes", fresh_for: WEEKLY) { @api.link_changes(domain) }
    part(nil, domain, "broken_links", fresh_for: WEEKLY) { @api.broken_links(domain) }
    part(nil, domain, "anchors", fresh_for: WEEKLY) { @api.anchors(domain) }
    part(nil, domain, "link_competitors", fresh_for: WEEKLY) { @api.link_competitors(domain) }
  end

  # The location as a Ranking keeps it.
  def location_label = @location.is_a?(Array) ? "#{@profile.local_zip} (#{@location.join(",")})" : @location

  # The tracked searches checked at once (Live): Google, the AIs, Maps.
  def live_searches
    brands = Market::AiCheck::Brands.new(profile: @profile)
    overview = @settings.ai_platform?("google_ai_overview")
    Market::Keyword.ordered.each do |keyword|
      self.class.keep_ranking(keyword, @api.ranking(keyword.keyword, location: @location, ai_overview: overview), location: location_label, pull: self,
        overview: overview, profile: @profile, brands: brands)
    rescue Market::Search::Client::Error => error
      raise if Market::Search::Client.stopping?(error)

      note "Couldn't check “#{keyword.keyword}” from #{@location.is_a?(Array) ? "the ZIP's centre" : @location}: #{error.message}"
    end
    ai_checks(brands, platforms: @settings.ai_platforms - ["google_ai_overview"])
    live_scans if @profile.local?
  end

  # The tracked searches queued (Standard): Google with its AI Overview, Maps points, AI Mode,
  # ChatGPT, Gemini and Bing Copilot, each in one batch; Perplexity and Claude asked at once.
  def queue_searches
    keywords = Market::Keyword.ordered.to_a
    overview = @settings.ai_platform?("google_ai_overview")
    batch("ranking", "serp/google/organic", keywords.map do |keyword|
      {task: @api.ranking_task(keyword.keyword, location: @location, ai_overview: overview), keyword: keyword, meta: {"location" => location_label, "ai_overview" => overview}}
    end)
    platforms = {"google_ai_mode" => ["ai_mode", "serp/google/ai_mode"], "chat_gpt" => ["llm_scraper", "ai_optimization/chat_gpt/llm_scraper"],
                 "gemini" => ["llm_scraper", "ai_optimization/gemini/llm_scraper"], "bing_copilot" => ["bing", "serp/bing/organic"]}
    platforms.each do |platform, (kind, base)|
      next unless @settings.ai_platform?(platform)

      due = keywords.reject { fresh_check?(it, platform) }
      batch(kind, base, due.map do |keyword|
        task = case kind
        when "ai_mode" then @api.ai_mode_task(keyword.keyword, location: @location)
        when "llm_scraper" then @api.llm_scraper_task(platform, keyword.keyword)
        else @api.bing_task(keyword.keyword)
        end
        {task: task, keyword: keyword, meta: {"platform" => platform}}
      end)
    end
    ai_checks(Market::AiCheck::Brands.new(profile: @profile), platforms: @settings.ai_platforms & %w[perplexity claude])
    queue_scans(keywords) if @profile.local?
  end

  def batch(kind, base, items)
    @api.queue(kind, base, items, pull: self)
  rescue Market::Search::Client::Error => error
    raise if Market::Search::Client.stopping?(error)

    note "Couldn't queue #{items.size} #{kind.tr("_", " ")} checks: #{error.message}"
  end

  def fresh_check?(keyword, platform) = !force && Market::AiCheck.where(keyword: keyword, platform: platform, checked_at: Market::SearchSnapshot::FRESH_FOR.ago..).exists?
  def fresh_scan?(keyword) = !force && Market::LocalScan.where(keyword: keyword, checked_at: Market::SearchSnapshot::FRESH_FOR.ago..).exists?

  def grid = Market::LocalGrid.points(@profile.local_center, radius_miles: @profile.local_radius_miles, size: @profile.local_grid)

  def queue_scans(keywords)
    zoom = Market::LocalGrid.zoom(@profile.local_radius_miles)
    points = grid
    items = keywords.reject { fresh_scan?(it) }.flat_map do |keyword|
      points.map do |point|
        {task: @api.maps_task(keyword.keyword, lat: point.lat, lng: point.lng, zoom: zoom), keyword: keyword,
         meta: {"row" => point.row, "col" => point.col, "lat" => point.lat, "lng" => point.lng}}
      end
    end
    batch("maps_point", "serp/google/maps", items)
  end

  # Each tracked search on Google Maps from every point of the grid, at once; a point that
  # fails is noted and left out, a search scanned in the last day is kept.
  def live_scans
    points = grid
    zoom = Market::LocalGrid.zoom(@profile.local_radius_miles)
    Market::Keyword.ordered.each do |keyword|
      next note("Local grid for “#{keyword.keyword}”: scanned in the last day, kept") if fresh_scan?(keyword)

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

  # Each tracked search asked of each AI given, at once; one asked in the last day is kept unless forced.
  def ai_checks(brands, platforms:)
    return if platforms.empty?

    models = {}
    Market::Keyword.ordered.each do |keyword|
      platforms.each do |platform|
        next if fresh_check?(keyword, platform)

        answer = case platform
        when "google_ai_mode" then @api.ai_mode(keyword.keyword, location: @location)
        when "chat_gpt", "gemini" then @api.llm_scraper(platform, keyword.keyword)
        when "bing_copilot" then @api.bing(keyword.keyword)
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

  # What the tracked searches are worth and what to write around them, AI visibility, site
  # health, links missing, and each Google Business Profile (found by its Maps id).
  def market_extras(settings, sites)
    words = Market::Keyword.ordered.pluck(:keyword)
    if settings.extra?(:keywords) && words.any?
      part(nil, @profile.domain, "keyword_facts") do
        facts = @api.keyword_facts(words)
        volumes = optional("AI search volumes", {}) { @api.ai_volume(words) }
        area, local = local_volumes(words)
        {"area" => area, "keywords" => words.to_h { [it, facts.fetch(it, {}).merge("ai_volume" => volumes[it], "local_volume" => local.dig(it, "volume"), "local_cpc" => local.dig(it, "cpc")).compact] }}
      end
      part(nil, @profile.domain, "serp_competitors") { @api.serp_competitors(words) }
      part(nil, @profile.domain, "content_ideas") { @api.content_ideas(words) }
    end
    if settings.extra?(:ai_visibility)
      keys = sites.to_h { |competitor, domain| [competitor ? "competitor:#{competitor.id}" : "site", domain] }.first(10).to_h
      platforms = (settings.country == "United States" && settings.language_code == "en") ? %w[google chat_gpt] : %w[google]
      if keys.size >= 2
        part(nil, @profile.domain, "ai_mentions") { platforms.to_h { [it, @api.ai_mentions(keys, platform: it)] } }
      else
        note "AI share of voice compares the site with its competitors: add one to see it"
      end
      part(nil, @profile.domain, "ai_answers") { {"answers" => platforms.flat_map { @api.ai_answers(@profile.domain, platform: it) }} }
      part(nil, @profile.domain, "ai_topics") { @api.ai_topics(words) } if words.any?
      part(nil, @profile.domain, "ai_history", fresh_for: MONTHLY) { @api.ai_history(@profile.domain) }
    end
    part(nil, @profile.domain, "site_health") { @api.site_health(@profile.website.presence || "https://#{@profile.domain}") } if settings.extra?(:site_health)
    part(nil, @profile.domain, "link_gap") { @api.link_gap(@profile.domain, sites.filter_map { |competitor, domain| domain if competitor }) } if settings.backlinks? && sites.size > 1
    business_profiles(sites) if settings.extra?(:profiles) || settings.extra?(:other_reviews)
  end

  def optional(what, fallback)
    yield
  rescue Market::Search::Client::Error => error
    raise if Market::Search::Client.stopping?(error)

    note "Couldn't get #{what}: #{error.message}"
    fallback
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

  # Each Business Profile (the site's and each competitor's, by the Maps id its scans saw): what's on
  # it, its customers' questions, and, queued, its reviews and its posts; and other review sites.
  def business_profiles(sites)
    scans = Market::LocalScan.latest_for(Market::Keyword.all).values.filter_map(&:first)
    own = scans.filter_map(&:own_cid).first
    leaders = scans.flat_map(&:leaders)
    sites.each do |competitor, domain|
      name = competitor ? competitor.name : @profile.business_name
      if @settings.extra?(:other_reviews)
        queue_once("trustpilot", competitor, domain, "business_data/trustpilot/reviews", @api.trustpilot_task(domain))
        queue_once("tripadvisor", competitor, domain, "business_data/tripadvisor/reviews", @api.tripadvisor_task(name))
      end
      next unless @settings.extra?(:profiles)

      cid = competitor ? leaders.find { |row| row["cid"] && (row["title"].to_s.casecmp?(name) || (row["domain"] && Market::Probe.normalize(row["domain"]) == domain)) }&.dig("cid") : own
      next note("Business Profile for #{name}: not found on Maps yet") unless cid

      part(competitor, domain, "business_profile") { @api.business_profile(cid) }
      part(competitor, domain, "gbp_qa") { @api.gbp_qa(cid) }
      queue_once("reviews", competitor, domain, competitor ? "business_data/google/reviews" : "business_data/google/extended_reviews", @api.post_reviews_task(cid))
      queue_once("gbp_posts", competitor, domain, "business_data/google/my_business_updates", @api.gbp_posts_task(cid))
    end
  end

  # A queued task for one site, unless one is waiting or its result is fresh.
  def queue_once(kind, competitor, domain, base, task)
    return if !force && Market::SearchSnapshot.fresh?(competitor, Market::QueuedTask::SNAPSHOTS.fetch(kind))
    return if Market::QueuedTask.queued.where(kind: kind, competitor: competitor).exists?

    @api.queue(kind, base, [{task: task, competitor: competitor, domain: domain}], pull: self, get: "#{base}/task_get")
  rescue Market::Search::Client::Error => error
    raise if Market::Search::Client.stopping?(error)

    note "Couldn't ask for #{competitor ? competitor.name : @profile.business_name}'s #{kind.tr("_", " ")}: #{error.message}"
  end

  # One part for one site, kept as a snapshot; skipped when fresh, noted when it fails.
  def part(competitor, domain, kind, fresh_for: Market::SearchSnapshot::FRESH_FOR)
    if !force && Market::SearchSnapshot.where(competitor: competitor, kind: kind, taken_at: fresh_for.ago..).exists?
      note "#{kind.humanize} for #{domain}: pulled lately, kept"
      return
    end

    data = yield
    Market::SearchSnapshot.create!(competitor: competitor, pull: self, domain: domain, kind: kind, location: Market::Settings.current.country,
      data: data, taken_at: Time.current)
  rescue Market::Search::Client::Error => error
    raise if Market::Search::Client.stopping?(error)

    note "Couldn't get #{kind.humanize.downcase} for #{domain}: #{error.message}"
  end

  def note(text) = (self.notes = Array(notes) + [text.truncate(300)])

  def finish(state, error: nil)
    update_columns(state: state, error: error&.truncate(500), notes: Array(notes), cost: requests.sum(:cost), finished_at: Time.current, updated_at: Time.current)
    Market::Finding.refresh
  rescue => failure
    Rails.logger.error("[market] finishing search pull #{id}: #{failure.class}: #{failure.message}")
  end
end
