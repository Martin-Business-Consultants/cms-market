# frozen_string_literal: true

# One tracked search asked of one AI at one pull (Market::SearchPull, through
# DataForSEO): Google's AI Overview (on the results page) and AI Mode, ChatGPT
# and Gemini (their real search answers), Perplexity and Claude (asked with
# web search on). Kept: whether it answered at all, whether it named the
# business (and in what order among the businesses it named) and cited its
# website, who else it named, and the sources it cited.
class Market::AiCheck < ApplicationRecord
  PLATFORMS = {
    "google_ai_overview" => {name: "AI Overview", owner: "Google", how: "the AI Overview on Google's results page"},
    "google_ai_mode" => {name: "AI Mode", owner: "Google", how: "Google's AI Mode answer"},
    "chat_gpt" => {name: "ChatGPT", owner: "OpenAI", how: "ChatGPT's search answer"},
    "gemini" => {name: "Gemini", owner: "Google", how: "Gemini's answer"},
    "perplexity" => {name: "Perplexity", owner: "Perplexity", how: "Perplexity's answer (Sonar, searching the web)"},
    "claude" => {name: "Claude", owner: "Anthropic", how: "Claude's answer, searching the web"},
    "bing_copilot" => {name: "Copilot", owner: "Microsoft", how: "the Copilot answer on Bing's results page"}
  }.freeze

  belongs_to :keyword
  belongs_to :pull, class_name: "Market::SearchPull", optional: true

  serialize :named, coder: JSON, type: Array
  serialize :sources, coder: JSON, type: Array

  validates :platform, inclusion: {in: PLATFORMS.keys}

  scope :latest_first, -> { order(checked_at: :desc, id: :desc) }

  def self.platform_name(platform) = PLATFORMS.dig(platform, :name)

  # The latest check of each search on each platform: {keyword_id => {platform => check}}.
  def self.latest_for(keywords)
    ids = where(keyword_id: Array(keywords).map(&:id)).group(:keyword_id, :platform).maximum(:id).values
    where(id: ids).group_by(&:keyword_id).transform_values { it.index_by(&:platform) }
  end

  def platform_name = self.class.platform_name(platform)

  # How it went, in one word: named and cited, named, cited, not named, or no answer.
  def verdict
    return "no_answer" unless answered
    return "named_cited" if mentioned && cited
    return "named" if mentioned
    return "cited" if cited

    "missing"
  end

  def competitors_named = named.reject { it["own"] }
  def source_domains = sources.filter_map { it["domain"] }.uniq

  # Builds a check from an answer: its text, the sources it cited, and the
  # businesses it showed as cards (ChatGPT's), found by name or website.
  def self.from_answer(keyword:, platform:, text:, sources: [], businesses: [], model: nil, prompt: nil, pull: nil, brands: Brands.new)
    text = text.to_s
    businesses = Array(businesses)
    sources = Array(sources).filter_map do |source|
      domain = Market::Probe.normalize(source["domain"].presence || source["url"])
      {"domain" => domain, "url" => source["url"], "title" => source["title"].to_s.truncate(150)}.compact if domain || source["url"]
    end.uniq { it["url"] || it["domain"] }.first(25)
    named = brands.named_in(text, businesses)
    own = named.find { it["own"] }
    new(keyword: keyword, platform: platform, model: model, prompt: prompt, pull: pull, answered: text.strip.present? || businesses.any?,
      mentioned: own.present?, mention_rank: own&.dig("rank"), cited: sources.any? { brands.own_domain?(it["domain"]) },
      named: named.first(15), sources: sources, answer: text.truncate(6000), checked_at: Time.current)
  end

  # A platform that didn't answer (no AI Overview on the page), kept as such.
  def self.unanswered(keyword:, platform:, pull: nil, error: nil)
    new(keyword: keyword, platform: platform, pull: pull, answered: false, error: error, named: [], sources: [], checked_at: Time.current)
  end
end
