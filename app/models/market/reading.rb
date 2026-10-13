# frozen_string_literal: true

# One reading of a website from outside (Market::Probe): a competitor's, or
# the site's own when it has no competitor. Keeps what changed since the
# reading before, in plain words: a new ad tag, a page count that jumped,
# posts published, a new heading.
class Market::Reading < ApplicationRecord
  belongs_to :competitor, optional: true

  serialize :facts, coder: JSON, type: Hash
  serialize :differences, coder: JSON, type: Array

  scope :latest_first, -> { order(taken_at: :desc, id: :desc) }
  scope :own, -> { where(competitor_id: nil) }

  # The latest reading of each competitor, by competitor id: one query for a list.
  def self.latest_for(competitors)
    ids = Array(competitors).map(&:id)
    return {} if ids.empty?

    where(id: where(competitor_id: ids).group(:competitor_id).maximum(:id).values).index_by(&:competitor_id)
  end

  def self.own_latest = own.latest_first.first

  # Reads the website now (a competitor's, or the site's own for nil) and keeps
  # what it found. Never raises for the website's sake: what couldn't be read
  # is in the facts, and `error` when nothing could.
  def self.take(competitor = nil, probe: nil)
    domain = competitor ? competitor.domain : Market::Profile.current.domain
    raise ArgumentError, "no website to read" if domain.blank?

    probe ||= Market::Probe.new(domain)
    previous = where(competitor: competitor).latest_first.first
    facts = probe.facts
    parts = facts.except("domain").values
    create!(competitor: competitor, domain: probe.domain, facts: facts, taken_at: Time.current,
      differences: previous&.read? ? Changes.between(previous.facts, facts) : [],
      error: (parts.map { it["error"] }.compact.join("; ") if parts.all? { it.is_a?(Hash) && it["error"] }))
  end

  def own? = competitor_id.nil?
  def read? = error.blank?
  def home = (facts["home_page"].is_a?(Hash) && !facts["home_page"]["error"]) ? facts["home_page"] : {}
  def sitemap = (facts["sitemap"].is_a?(Hash) && !facts["sitemap"]["error"]) ? facts["sitemap"] : {}
  def tools = Array(home["tools"])
  def socials = (home["socials"] || {}).keys
  def runs?(tool) = tools.include?(tool.to_s)

  # A big site's sitemap index is read only so far (Probe::MAX_CHILD_SITEMAPS): its counts are a floor.
  def partial_sitemap? = sitemap["sitemaps"].to_i > sitemap["sitemaps_read"].to_i

  def figure(key)
    case key.to_s
    when "pages", "posts", "locations", "services", "posts_last_90_days", "last_changed" then sitemap[key.to_s]
    when "platform", "words" then home[key.to_s]
    when "socials" then socials.size
    end
  end

  # What changed between two readings, in plain words.
  module Changes
    extend self

    Reading = Struct.new(:facts) do
      def home = part("home_page")
      def sitemap = part("sitemap")
      def tools = Array(home["tools"])
      def socials = (home["socials"] || {}).keys
      def part(key) = (facts.is_a?(Hash) && facts[key].is_a?(Hash) && !facts[key]["error"]) ? facts[key] : {}
    end

    def between(before, after)
      was = Reading.new(before)
      now = Reading.new(after)
      [
        *text_change("Home page title", was.home["title"], now.home["title"]),
        *text_change("Main heading", Array(was.home["headings"]).first, Array(now.home["headings"]).first),
        *text_change("Platform", was.home["platform"], now.home["platform"]),
        *(now.tools - was.tools).map { "Now runs #{tool_label(it)}" },
        *(was.tools - now.tools).map { "No longer runs #{tool_label(it)}" },
        *(now.socials - was.socials).map { "Added a #{Market::Probe::SOCIAL_LABELS.fetch(it, it.humanize)} profile" },
        *(Array(now.home["schema_types"]) - Array(was.home["schema_types"])).first(3).map { "Added #{it} structured data" },
        *count_change("pages", was.sitemap["pages"], now.sitemap["pages"], threshold: 5),
        *count_change("posts", was.sitemap["posts"], now.sitemap["posts"], threshold: 1),
        *count_change("location pages", was.sitemap["locations"], now.sitemap["locations"], threshold: 1),
        *count_change("service pages", was.sitemap["services"], now.sitemap["services"], threshold: 1)
      ]
    end

    private

    def text_change(label, was, now)
      return [] if was.blank? || now.blank? || was == now

      ["#{label}: “#{was.to_s.truncate(80)}” → “#{now.to_s.truncate(80)}”"]
    end

    def count_change(noun, was, now, threshold:)
      return [] unless was.is_a?(Integer) && now.is_a?(Integer)

      delta = now - was
      return [] if delta.abs < threshold || (noun == "pages" && delta.abs < was * 0.1)

      ["#{delta.positive? ? "+" : "−"}#{delta.abs} #{noun} (now #{now})"]
    end

    def tool_label(key) = Market::Probe::TOOLS.dig(key, 0) || key.humanize
  end
end
