# frozen_string_literal: true

# The starting point: a few answers (the business's name, website, ZIP and a
# line on what it does), then the install's AI (the AI plugin) reads the
# website and what's in the CMS and fills in as much of the profile as it can.
# It fills only what's still empty, marks each field it filled for a person to
# check (Market::Profile#ai_filled), and suggests competitors and searches to
# check, each a click from being added. Run in Market::IntakeJob; never raises.
class Market::Intake < ApplicationRecord
  STATES = %w[queued running ready failed].freeze
  STUCK_AFTER = 15.minutes
  PAGES = 3
  FIELDS = %w[industry naics_code service_area offerings audience positioning goals search_location maps_name].freeze

  belongs_to :user, optional: true

  serialize :answers, coder: JSON, type: Hash
  serialize :filled, coder: JSON, type: Array
  serialize :competitor_suggestions, coder: JSON, type: Array
  serialize :keyword_suggestions, coder: JSON, type: Array
  serialize :to_check, coder: JSON, type: Array

  validates :state, inclusion: {in: STATES}

  scope :latest_first, -> { order(id: :desc) }

  # Saves the answers on the profile, then has the AI fill in the rest when it can.
  def self.start(answers, user: nil, geocoder: Market::Geocoder)
    answers = answers.to_h.stringify_keys.slice("business_name", "website", "local_zip", "about").transform_values { it.to_s.strip }.compact_blank
    profile = {"business_name" => answers["business_name"], "website" => answers["website"], "local_zip" => answers["local_zip"]}.compact
    profile["notes"] = answers["about"] if answers["about"] && Market::Profile.current.notes.blank?
    Market::Profile.update(profile, geocoder)
    intake = create!(user: user, answers: answers, state: Market::Plan.ai_available? ? "queued" : "failed",
      error: (Market::Plan.ai_unavailable_reason unless Market::Plan.ai_available?))
    intake.run_later if intake.state == "queued"
    intake
  end

  def self.working? = where(state: %w[queued running]).any?(&:working?)

  def working? = state.in?(%w[queued running]) && updated_at > STUCK_AFTER.ago
  def ready? = state == "ready"
  def failed? = state == "failed" || (state.in?(%w[queued running]) && !working?)
  def run_later = Market::IntakeJob.perform_later(self)

  def new_competitor_suggestions
    known = Market::Competitor.pluck(:name, :domain)
    Array(competitor_suggestions).reject do |suggestion|
      domain = Market::Probe.normalize(suggestion["website"])
      known.any? { |name, known_domain| (domain && known_domain == domain) || name.casecmp?(suggestion["name"].to_s) }
    end
  end

  def new_keyword_suggestions = Array(keyword_suggestions) - Market::Keyword.pluck(:keyword)

  # Called by Market::IntakeJob. Never raises: what went wrong is kept in `error`.
  def run!(probe: nil)
    update!(state: "running", started_at: Time.current)
    profile = Market::Profile.current
    probe ||= profile.domain && Market::Probe.new(profile.domain)
    answer = ::Ai.structured(purpose: "market_intake", system: instructions, prompt: brief(profile, probe), schema: SCHEMA, user: user)
    values = FIELDS.index_with { field_value(answer, it) }
    values["local_radius_miles"] = answer["local_radius_miles"].to_i if Market::Profile::RADII.include?(answer["local_radius_miles"].to_i) && Market::Profile.current.stored["local_radius_miles"].blank?
    filled = Market::Profile.fill_in(values)
    update!(state: "ready", finished_at: Time.current, summary: answer["summary"].to_s.strip.presence, filled: filled,
      competitor_suggestions: competitors_from(answer["competitors_to_check"]), keyword_suggestions: keywords_from(answer["keywords_to_track"]),
      to_check: Array(answer["to_check"]).map(&:to_s).compact_blank.first(8))
    Market::Finding.refresh
  rescue => error
    Rails.logger.error("[market] intake #{id}: #{error.class}: #{error.message}")
    known = defined?(::Ai::Error) && (error.is_a?(::Ai::Error) || error.is_a?(::Ai::Unavailable))
    update_columns(state: "failed", error: (known ? error.message : "#{error.class.name.demodulize}: #{error.message}").truncate(500), finished_at: Time.current, updated_at: Time.current)
  end

  SCHEMA = {
    type: "object", additionalProperties: false,
    required: %w[summary industry naics_code service_area offerings audience positioning goals search_location maps_name local_radius_miles competitors_to_check keywords_to_track to_check],
    properties: {
      summary: {type: "string", description: "Two sentences: what this business is and who it's for, as the website shows it."},
      industry: {type: "string", description: "A plain industry name, as specific as useful (\"Residential plumbing\", not \"Services\")."},
      naics_code: {type: "string", description: "The 2–6 digit NAICS code, or \"\" when unsure."},
      service_area: {type: "string", description: "Where it serves: towns, counties or regions, as the site says. \"\" when the site doesn't say."},
      offerings: {type: "string", description: "What it sells, the main services or products first, one line."},
      audience: {type: "string", description: "Who it serves: homeowners, businesses, families…"},
      positioning: {type: "string", description: "How it presents itself against others: fastest, local and family-run, premium… from the site's own words."},
      goals: {type: "string", description: "Sensible starting marketing goals for a business like this (more calls, booked appointments, quote requests…), for a person to correct."},
      search_location: {type: "string", description: "Where its customers search from, as a DataForSEO location: \"City,State,Country\" (\"Grand Rapids,Michigan,United States\"). \"\" when unsure."},
      maps_name: {type: "string", description: "Its name as it likely appears on Google Maps."},
      local_radius_miles: {type: "integer", enum: Market::Profile::RADII, description: "How far its customers likely come from, in miles."},
      competitors_to_check: {type: "array", description: "Up to 6 real businesses likely competing for the same customers in the same area. Only ones you're confident exist; a person checks each.",
                             items: {type: "object", additionalProperties: false, required: %w[name website why],
                                     properties: {name: {type: "string"}, website: {type: "string", description: "Their domain, or \"\" when unsure."}, why: {type: "string"}}}},
      keywords_to_track: {type: "array", description: "Up to 10 searches its customers make, as they'd type them, with the place where it matters (\"emergency plumber grand rapids\").",
                          items: {type: "string"}},
      to_check: {type: "array", description: "Short notes on what you weren't sure of and a person should check.", items: {type: "string"}}
    }
  }.freeze

  private

  def field_value(answer, field)
    value = (field == "industry") ? answer["industry"] : answer[field]
    value.to_s.strip.presence
  end

  def instructions
    <<~TEXT
      You help a business owner set up a marketing profile for their own business, so its SEO and marketing can be planned. You are given what they told you (its name, website, ZIP and a line on what it does), the text of its website's main pages and what was found on them, and what's in its CMS (its pages and its brand brief).

      Fill in what the website and the CMS show. Use the site's own words where they're good. Never invent facts: where something isn't shown, give "" (or your best careful guess where the field says so) and say what to check in to_check. Competitors must be real businesses you're confident exist in that area; give "" for a website you're not sure of.
      Today is #{Date.current.to_fs(:long)}.
    TEXT
  end

  def brief(profile, probe)
    parts = ["What they told us:\n#{answers.map { |field, value| "#{field.humanize}: #{value}" }.join("\n")}"]
    parts << "Location: #{profile.local_place} (ZIP #{profile.local_zip})" if profile.local?
    if probe
      facts = probe.facts
      parts << "What the home page shows:\n#{JSON.generate(facts["home_page"])}"
      parts << "The home page's text:\n#{probe.page_text("/")}"
      pages_from(facts).each { |url| (text = probe.page_text(url)) && parts << "The text of #{url}:\n#{text}" }
    else
      parts << "No website to read."
    end
    parts << cms_part
    brand = defined?(::BrandBrief) ? ::BrandBrief.to_h.compact_blank : {}
    parts << "The brand brief the owners wrote:\n#{brand.map { |field, text| "#{field.to_s.humanize}: #{text}" }.join("\n")}" if brand.any?
    parts.compact.join("\n\n")
  end

  # A few of the site's pages worth reading: about, services, locations, contact.
  def pages_from(facts)
    sample = Array(facts.dig("sitemap", "sample"))
    sample.select { it.match?(%r{/(about|services?|locations?|areas?|contact|who-we-are)}i) }.first(PAGES)
  end

  def cms_part
    pages = ::Page.where(status: "published").order(updated_at: :desc).limit(40).map do |page|
      [page.path, page.title, page.seo.to_h["meta_description"].presence].compact.join(" — ")
    end
    "Pages in the CMS:\n#{pages.join("\n")}" if pages.any?
  end

  def competitors_from(answers)
    Array(answers).filter_map do |answer|
      next unless answer.is_a?(Hash) && answer["name"].present?

      website = answer["website"].to_s.strip
      website = "https://#{website}" if website.present? && !website.match?(%r{\Ahttps?://})
      {"name" => answer["name"].to_s.strip, "website" => website.presence, "why" => answer["why"].to_s.strip.presence}.compact
    end.first(6)
  end

  def keywords_from(answers)
    tracked = Market::Keyword.pluck(:keyword)
    Array(answers).map { it.to_s.strip.squeeze(" ").downcase }.compact_blank.uniq.reject { tracked.include?(it) }.first(10)
  end
end
