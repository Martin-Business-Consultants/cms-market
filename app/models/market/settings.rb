# frozen_string_literal: true

# Settings › Market, kept in the core's Setting "market" (the DataForSEO
# password among its secrets): the DataForSEO account
# search data comes from, what may be spent on it a month, where searches are
# measured, and how often it's pulled on its own. Plans are drafted by the AI
# plugin (cms-ai, Settings › AI).
class Market::Settings
  KEY = "market"
  REFRESH = {"off" => "Only when someone asks", "monthly" => "Every month", "weekly" => "Every week"}.freeze
  REFRESH_EVERY = {"monthly" => 1.month, "weekly" => 1.week}.freeze
  # What a pull gathers beyond each site's visibility and keywords, the tracked searches and the map,
  # in plain bundles; the older names still answer (ALIASES).
  EXTRAS = {
    "keywords" => "What each search is worth: searches a month here, in the country and in AI assistants; difficulty, intent and when it peaks; who wins it; and searches worth writing about around it",
    "ai_visibility" => "AI visibility: how often real ChatGPT and Google AI answers mention each site, what they say about it, and the sites they cite for its searches",
    "profiles" => "Business Profiles: each one as customers see it, its Google reviews (read for praise and complaints), its posts and its customers' questions",
    "history" => "A year of history and best pages: each site's visibility month by month, and the pages that bring it the most visits",
    "site_health" => "Site health: the home page as Google renders it, and Lighthouse on a phone",
    "web_mentions" => "Web mentions: the web talking about each business by name, and how warmly",
    "other_reviews" => "Trustpilot and Tripadvisor reviews too, for businesses customers review there"
  }.freeze
  ALIASES = {"keyword_facts" => "keywords", "ai_mentions" => "ai_visibility", "business_profiles" => "profiles", "reviews" => "profiles"}.freeze
  DEFAULTS = {"monthly_budget_cents" => 2500, "country" => "United States", "language_code" => "en", "refresh" => "off",
              "keyword_limit" => 200, "backlinks" => false, "sandbox" => false,
              "ai_platforms" => %w[google_ai_overview google_ai_mode chat_gpt gemini perplexity claude], "extras" => EXTRAS.keys - %w[other_reviews], "queue" => true}.freeze
  # Backlinks (Settings › Market › Backlinks too) brings each site's links month by month, and the sites linking to competitors but not the site.

  def self.current = new(Setting.get(KEY))

  def initialize(data)
    @data = DEFAULTS.merge(data.to_h.stringify_keys.except("profile"))
  end

  def dataforseo_login = @data["dataforseo_login"].presence
  def dataforseo_password = Setting.secret(KEY, "dataforseo_password")
  def search_connected? = dataforseo_login.present? && dataforseo_password.present?

  def monthly_budget_cents = @data["monthly_budget_cents"].to_i
  def budget = monthly_budget_cents.to_d / 100
  def spent_this_month = Market::SearchRequest.where(created_at: Time.current.beginning_of_month..).sum(:cost).to_d
  def remaining_budget = [budget - spent_this_month, 0.to_d].max

  def country = @data["country"].presence || DEFAULTS["country"]
  def language_code = @data["language_code"].presence || DEFAULTS["language_code"]
  def refresh = REFRESH.key?(@data["refresh"]) ? @data["refresh"] : "off"
  def refresh_every = REFRESH_EVERY[refresh]
  def keyword_limit = @data["keyword_limit"].to_i.clamp(10, 1000)
  def backlinks? = @data["backlinks"] == true
  def sandbox? = @data["sandbox"] == true

  # The AIs each tracked search is asked of, on every pull.
  def ai_platforms = Array(@data["ai_platforms"]) & Market::AiCheck::PLATFORMS.keys
  def ai_platform?(platform) = ai_platforms.include?(platform.to_s)
  def extras = Array(@data["extras"]).map { ALIASES.fetch(it, it) }.uniq & EXTRAS.keys
  def extra?(name) = extras.include?(ALIASES.fetch(name.to_s, name.to_s))

  # Queue the checks that can wait (DataForSEO's Standard queue: about a third of the price; they arrive within minutes).
  def queue? = @data["queue"] != false

  def balance = @data["balance"]&.to_d
  def checked_at = @data["checked_at"].presence&.then { Time.zone.parse(it) }
  def last_error = @data["last_error"].presence

  def ai? = Market::Plan.ai_available?

  def self.note_error(message) = Setting.set(KEY, "last_error" => message.to_s.truncate(500))
  def self.clear_error = Setting.set(KEY, "last_error" => nil)

  # Asks DataForSEO for the account's balance (which costs nothing) and keeps it.
  def self.check!(client: Market::Search::Client.new)
    balance = client.balance
    Setting.set(KEY, "balance" => balance.to_s, "checked_at" => Time.current.iso8601, "last_error" => nil)
    balance
  end

  # From Settings › Market's form or the API's PATCH: only what was sent
  # changes. A secret changes only when one is typed; remove_* clears it.
  def self.update(params)
    params = params.to_h.stringify_keys
    boolean = ActiveModel::Type::Boolean.new
    readers = {
      "dataforseo_login" => ->(value) { value.to_s.strip.presence },
      "monthly_budget_cents" => ->(value) { [value.to_i, 0].max },
      "monthly_budget_dollars" => ->(value) { [(value.to_d * 100).round, 0].max },
      "country" => ->(value) { value.to_s.strip.presence || DEFAULTS["country"] },
      "language_code" => ->(value) { value.to_s.strip.downcase.presence || DEFAULTS["language_code"] },
      "refresh" => ->(value) { REFRESH.key?(value.to_s) ? value.to_s : "off" },
      "keyword_limit" => ->(value) { value.to_i.clamp(10, 1000) },
      "backlinks" => ->(value) { boolean.cast(value) || false },
      "sandbox" => ->(value) { boolean.cast(value) || false },
      "ai_platforms" => ->(value) { Array(value) & Market::AiCheck::PLATFORMS.keys },
      "extras" => ->(value) { Array(value).map { ALIASES.fetch(it, it) }.uniq & EXTRAS.keys },
      "queue" => ->(value) { boolean.cast(value) != false }
    }
    data = readers.filter_map { |name, read| [name, read.call(params[name])] if params.key?(name) }.to_h
    data["monthly_budget_cents"] = data.delete("monthly_budget_dollars") if data.key?("monthly_budget_dollars")
    Setting.set(KEY, data) if data.any?
    {"dataforseo_password" => "remove_dataforseo_password"}.each do |secret, remove|
      if params[secret].present?
        Setting.set_secret(KEY, secret => params[secret].to_s.strip)
      elsif boolean.cast(params[remove])
        Setting.set_secret(KEY, secret => "")
      end
    end
    current
  end

  def to_h
    {dataforseo: {connected: search_connected?, login: dataforseo_login, balance: balance&.to_f, checked_at: checked_at, last_error: last_error},
     budget: {monthly: budget.to_f, spent_this_month: spent_this_month.to_f, remaining: remaining_budget.to_f},
     country: country, language_code: language_code, refresh: refresh, keyword_limit: keyword_limit, backlinks: backlinks?, sandbox: sandbox?,
     ai_platforms: ai_platforms, extras: extras, queue: queue?,
     ai: {available: ai?, unavailable_reason: (Market::Plan.ai_unavailable_reason unless ai?)}}
  end
end
