# frozen_string_literal: true

# The big picture for the site's business, drafted by the install's AI (the
# AI plugin, cms-ai: Ai.structured) from everything known (Market::Plan::Brief): the profile, the site and its
# content, each competitor's website, the search data, the tracked rankings,
# the findings and what's already planned. It answers with the state of the
# market, the angle to win on, an industry, competitors and searches worth
# checking, and opportunities, which a person turns into draft pages, marks
# done or dismisses. Run in Market::PlanJob; nothing changes on the site
# until a person acts.
class Market::Plan < ApplicationRecord
  STATES = %w[queued running ready failed].freeze
  STUCK_AFTER = 15.minutes
  MAX_OPPORTUNITIES = 16

  belongs_to :user, optional: true
  has_many :opportunities, dependent: :nullify

  serialize :industry_suggestion, coder: JSON, type: Hash
  serialize :competitor_suggestions, coder: JSON, type: Array
  serialize :keyword_suggestions, coder: JSON, type: Array

  validates :state, inclusion: {in: STATES}

  scope :latest_first, -> { order(id: :desc) }

  def self.drafting? = where(state: %w[queued running]).any?(&:working?)

  # Plans need the AI plugin (cms-ai), switched on and set up; Market works without it.
  def self.ai_available? = defined?(::Ai) && ::Ai.respond_to?(:available?) && ::Ai.available?

  def self.ai_unavailable_reason
    return "Plans are drafted by the AI plugin: install it (Martin-Business-Consultants/cms-ai) and set it up in Settings › AI" unless defined?(::Ai) && ::Ai.respond_to?(:unavailable_reason)

    ::Ai.unavailable_reason
  end

  def working? = state.in?(%w[queued running]) && updated_at > STUCK_AFTER.ago
  def ready? = state == "ready"
  def failed? = state == "failed" || (state.in?(%w[queued running]) && !working?)
  def run_later = Market::PlanJob.perform_later(self)

  # Its suggestions not taken yet.
  def new_competitor_suggestions
    known = Market::Competitor.pluck(:name, :domain)
    Array(competitor_suggestions).reject do |suggestion|
      domain = Market::Probe.normalize(suggestion["website"])
      known.any? { |name, known_domain| (domain && known_domain == domain) || name.casecmp?(suggestion["name"].to_s) }
    end
  end

  def new_keyword_suggestions = Array(keyword_suggestions) - Market::Keyword.pluck(:keyword)

  def industry_suggestion_new?
    name = industry_suggestion&.dig("name").to_s
    name.present? && !Market::Profile.current.industry.to_s.casecmp?(name)
  end

  # Called by Market::PlanJob. Never raises: what went wrong is kept in `error`.
  def run!
    update!(state: "running", started_at: Time.current)
    raise ArgumentError, self.class.ai_unavailable_reason unless self.class.ai_available?

    answer = ::Ai.structured(purpose: "market_plan", system: instructions, prompt: Brief.new.to_s, schema: SCHEMA, user: user)
    transaction do
      update!(summary: answer["summary"].to_s.strip, positioning: answer["positioning"].to_s.strip.presence,
        industry_suggestion: industry_from(answer["industry"]), competitor_suggestions: competitors_from(answer["competitors_to_check"]),
        keyword_suggestions: keywords_from(answer["keywords_to_track"]))
      add_opportunities(Array(answer["opportunities"]))
    end
    update!(state: "ready", finished_at: Time.current)
  rescue => error
    Rails.logger.error("[market] plan #{id}: #{error.class}: #{error.message}")
    known = error.is_a?(ArgumentError) || (defined?(::Ai::Error) && (error.is_a?(::Ai::Error) || error.is_a?(::Ai::Unavailable)))
    update_columns(state: "failed", error: (known ? error.message : "#{error.class.name.demodulize}: #{error.message}").truncate(500),
      finished_at: Time.current, updated_at: Time.current)
  end

  SCHEMA = {
    type: "object", additionalProperties: false, required: %w[summary positioning industry competitors_to_check keywords_to_track opportunities],
    properties: {
      summary: {type: "string", description: "The big picture of this business's market in 3 to 6 sentences: where it stands, who's winning and why, and what matters most now."},
      positioning: {type: "string", description: "The angle to win on, in one or two sentences: what it can own that competitors don't."},
      industry: {type: "object", additionalProperties: false, required: %w[name naics_code why], properties: {
        name: {type: "string", description: "A plain industry name, as specific as useful (\"Residential plumbing\", not \"Services\")."},
        naics_code: {type: "string", description: "The 2–6 digit NAICS code, or \"\" when unsure."},
        why: {type: "string"}
      }},
      competitors_to_check: {type: "array", description: "Businesses likely competing for the same customers that aren't listed yet. Only real ones you're confident exist; a person checks each.",
                             items: {type: "object", additionalProperties: false, required: %w[name website why],
                                     properties: {name: {type: "string"}, website: {type: "string", description: "Their site's domain, or \"\" when unsure."}, why: {type: "string"}}}},
      keywords_to_track: {type: "array", description: "Up to 15 searches its customers make that are worth winning and watching, as they'd type them, with the place where it matters (\"emergency dentist grand rapids\"). Not ones already tracked.",
                          items: {type: "string"}},
      opportunities: {type: "array", items: {
        type: "object", additionalProperties: false, required: %w[goal channel title detail evidence impact effort horizon],
        properties: {
          goal: {type: "string", description: "The id of the goal it serves (\"3\"), or \"\" when none of them."},
          channel: {type: "string", enum: Market::Opportunity::CHANNELS.keys},
          title: {type: "string", description: "What to do, as a short instruction (\"Publish a page for each town served\")."},
          detail: {type: "string", description: "How, in two or three sentences someone could start from."},
          evidence: {type: "string", description: "What in the facts shows it's worth doing (\"Two direct competitors have 15+ location pages; this site has none\")."},
          impact: {type: "string", enum: Market::Opportunity::IMPACTS},
          effort: {type: "string", enum: Market::Opportunity::EFFORTS},
          horizon: {type: "string", enum: Market::Opportunity::HORIZONS.keys}
        }
      }}
    }
  }.freeze

  private

  def instructions
    brand = defined?(::BrandBrief) ? ::BrandBrief.to_h.map { |field, text| "#{field.to_s.humanize}: #{text}" }.join("\n") : ""
    [<<~TEXT, ("The brand brief the owners wrote:\n#{brand}" if brand.present?)].compact.join("\n\n")
      You are a senior marketing strategist planning a business's SEO and marketing for the year. You are given its market profile, what's on its website (the pages and posts in its CMS, and a reading of the live site), readings of its competitors' websites taken from outside (pages and posts in their sitemaps, how recently they changed, the tools on their home pages: ad tags, analytics, call tracking, chat, reviews, booking; structured data, social profiles), how each competes, search data from DataForSEO when it's been pulled (visibility, estimated traffic, keywords, where everyone ranks for the searches tracked), findings already worked out from all of it, and the work already planned, done or dismissed.

      Give the big picture, then the opportunities that would win this market, best first.
      - Aim at the goals: each opportunity serves one where it can (say which), those behind pace first. A goal with nothing serving it gets something.
      - Act on the findings first: they are exact. Ground every opportunity in the facts and say which in evidence. Compare: where competitors are ahead (more location or service pages, regular posts, ads running, reviews shown, booking online), copy what works and beat it; where they're weak, take the ground.
      - Cover the channels that matter for this business, not all of them. Pages and posts it should publish are the most direct: the site is right here.
      - Mix quick wins (now) with the bigger moves (next, later). At most #{MAX_OPPORTUNITIES}; don't repeat anything already planned, done or dismissed.
      - Use the search figures as given (traffic is DataForSEO's estimate; say so). Never invent rankings, traffic, review counts or ad spend that aren't there. Where something needs checking, say so in detail.
      - Write plainly, for a business owner: specific, no jargon you don't need, in the brand's voice.
      Today is #{Date.current.to_fs(:long)}.
    TEXT
  end

  def industry_from(answer)
    return {} unless answer.is_a?(Hash) && answer["name"].present?

    answer.slice("name", "naics_code", "why").transform_values { it.to_s.strip }.compact_blank
  end

  def competitors_from(answers)
    Array(answers).filter_map do |answer|
      next unless answer.is_a?(Hash) && answer["name"].present?

      website = answer["website"].to_s.strip
      website = "https://#{website}" if website.present? && !website.match?(%r{\Ahttps?://})
      {"name" => answer["name"].to_s.strip, "website" => website.presence, "why" => answer["why"].to_s.strip.presence}.compact
    end.first(8)
  end

  def keywords_from(answers)
    tracked = Market::Keyword.pluck(:keyword)
    Array(answers).map { it.to_s.strip.squeeze(" ").downcase }.compact_blank.uniq.reject { tracked.include?(it) }.first(15)
  end

  def add_opportunities(answers)
    existing = Market::Opportunity.pluck(:title).map(&:downcase)
    goals = Market::Goal.active.pluck(:id).map(&:to_s)
    answers.first(MAX_OPPORTUNITIES).each do |answer|
      title = answer["title"].to_s.strip
      next if title.empty? || existing.include?(title.downcase)

      opportunities.create!(title: title, detail: answer["detail"].to_s.strip.presence, evidence: answer["evidence"].to_s.strip.presence,
        channel: answer["channel"].presence_in(Market::Opportunity::CHANNELS.keys) || "seo",
        impact: answer["impact"].presence_in(Market::Opportunity::IMPACTS) || "medium",
        effort: answer["effort"].presence_in(Market::Opportunity::EFFORTS) || "medium",
        horizon: answer["horizon"].presence_in(Market::Opportunity::HORIZONS.keys) || "next",
        goal_id: answer["goal"].to_s[/\d+/].presence_in(goals))
      existing << title.downcase
    end
  end
end
