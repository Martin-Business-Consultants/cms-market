# frozen_string_literal: true

# Settings › Market, kept in the core's Setting "market" (the DataForSEO
# password and the Anthropic key among its secrets): the DataForSEO account
# search data comes from, what may be spent on it a month, where searches are
# measured, how often it's pulled on its own, and the model plans are drafted
# with.
class Market::Settings
  KEY = "market"
  REFRESH = {"off" => "Only when someone asks", "monthly" => "Every month", "weekly" => "Every week"}.freeze
  REFRESH_EVERY = {"monthly" => 1.month, "weekly" => 1.week}.freeze
  DEFAULT_MODEL = "claude-opus-5-5"
  DEFAULTS = {"monthly_budget_cents" => 2500, "country" => "United States", "language_code" => "en", "refresh" => "off",
              "keyword_limit" => 200, "backlinks" => false, "ai_model" => DEFAULT_MODEL}.freeze

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

  def balance = @data["balance"]&.to_d
  def checked_at = @data["checked_at"].presence&.then { Time.zone.parse(it) }
  def last_error = @data["last_error"].presence

  def ai_key = Setting.secret(KEY, "anthropic_api_key")
  def ai_model = @data["ai_model"].presence || DEFAULT_MODEL
  def ai? = ai_key.present?

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
      "ai_model" => ->(value) { value.to_s.strip.presence || DEFAULT_MODEL }
    }
    data = readers.filter_map { |name, read| [name, read.call(params[name])] if params.key?(name) }.to_h
    data["monthly_budget_cents"] = data.delete("monthly_budget_dollars") if data.key?("monthly_budget_dollars")
    Setting.set(KEY, data) if data.any?
    {"dataforseo_password" => "remove_dataforseo_password", "anthropic_api_key" => "remove_ai_key"}.each do |secret, remove|
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
     country: country, language_code: language_code, refresh: refresh, keyword_limit: keyword_limit, backlinks: backlinks?,
     ai: {key_set: ai?, model: ai_model}}
  end
end
