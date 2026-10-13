# frozen_string_literal: true

# One thing the data says about the site's market, worked out by
# Market::Finding::Analysis from the website readings, the search data and the
# tracked rankings. Its key is stable ("keyword_gap:rival.example"), so a
# finding lives on while it holds: `changed_at` moves when it appears, comes
# back or changes, and it's resolved when it no longer holds. Dismissed, it
# stays dismissed while it holds. Refreshed after every reading and pull, and
# nightly; `since` on the API answers only what changed.
class Market::Finding < ApplicationRecord
  SEVERITIES = %w[high medium low info].freeze
  STATES = %w[open resolved dismissed].freeze

  serialize :evidence, coder: JSON, type: Hash
  serialize :sources, coder: JSON, type: Array

  validates :severity, inclusion: {in: SEVERITIES}

  scope :open, -> { where(resolved_at: nil, dismissed_at: nil) }
  scope :by_severity, -> { in_order_of(:severity, SEVERITIES).order(changed_at: :desc) }
  scope :in_state, ->(state) {
    case state
    when "open" then open
    when "resolved" then where.not(resolved_at: nil)
    when "dismissed" then where(resolved_at: nil).where.not(dismissed_at: nil)
    else all
    end
  }

  def state = resolved_at ? "resolved" : (dismissed_at ? "dismissed" : "open")
  def channel_label = Market::Opportunity::CHANNELS[channel]

  # The opportunity made from it, when there is one.
  def opportunity = Market::Opportunity.where(finding_key: key).order(:id).last

  # Turns it into an opportunity on the plan: its words, its channel, sized by how much it matters.
  def to_opportunity
    opportunity || Market::Opportunity.create!(finding_key: key, title: title.truncate(200), channel: channel.presence_in(Market::Opportunity::CHANNELS.keys) || "seo",
      detail: detail, evidence: "From a finding (#{kind.humanize.downcase}): #{JSON.generate(evidence).truncate(500)}",
      impact: {"high" => "high", "medium" => "medium"}.fetch(severity, "low"), effort: "medium", horizon: (severity == "high") ? "now" : "next")
  end

  # Where in Market its subject is: a competitor, the search data, the map, the profile.
  def related
    domain = evidence["domain"]
    competitor = domain && Market::Competitor.find_by(domain: domain)
    case kind
    when /\Alocal/, "gbp_calls_falling" then [:local, nil]
    when /\Aai_/ then [:ai, nil]
    when /\Agbp_(unclaimed|missing|photos)\z/, "site_slow", "site_issues", "web_mentions_gap", "questions_to_answer" then [:search, nil]
    when "gsc_low_clicks" then (page = ::Page.find_by(path: evidence["page_path"])) ? [:page, page] : [:search, nil]
    when "ga_leaky_pages", "ga_key_events_falling", "gbp_unanswered_reviews", "gsc_clicks_falling" then [:google, nil]
    when "keyword_gap", "competitor_surge", "site_changes" then competitor ? [:competitor, competitor] : [:search, nil]
    when "profile_gaps" then [:profile, nil]
    when "no_competitors", "location_pages", "content_freshness", "conversion_tools", "competitor_ads", "stale_site" then [:competitors, nil]
    else [:search, nil]
    end
  end

  def dismiss(by:) = update(dismissed_at: Time.current, dismissed_by_name: by.try(:name).presence || by.try(:email), changed_at: Time.current)
  def reopen = update(dismissed_at: nil, dismissed_by_name: nil, changed_at: Time.current)

  # Works the findings out again: new ones added, held ones updated
  # (changed_at moves only when what they say changes), gone ones resolved.
  # Answers the open ones.
  def self.refresh(now: Time.current)
    found = Analysis.new.findings
    existing = all.index_by(&:key)
    transaction do
      found.each do |attributes|
        attributes = attributes.deep_stringify_keys
        row = existing.delete(attributes["key"]) || new(key: attributes["key"], first_seen_at: now)
        moved = row.new_record? || row.resolved_at || row.title != attributes["title"] || row.severity != attributes["severity"] || row.evidence != attributes["evidence"]
        row.assign_attributes(attributes.except("key").merge("last_seen_at" => now, "resolved_at" => nil))
        row.changed_at = now if moved
        row.save!
      end
      existing.each_value { |row| row.update!(resolved_at: now, changed_at: now) unless row.resolved_at }
    end
    open
  end

  def self.refresh_later = Market::FindingsJob.perform_later
end
