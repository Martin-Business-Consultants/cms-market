# frozen_string_literal: true

# Content work for one thing on the Market screens, drafted by the install's
# AI (the AI plugin, cms-ai: Ai.structured) from what's known about it
# (Market::Workup::Brief): a tracked search ("keyword:12"), the map for one
# ("map:12"), a site's visibility ("visibility:own", "visibility:3"), its
# links ("links:own": winning links, as tasks and posts worth linking to), an
# opportunity ("opportunity:5"), a finding ("finding:9") or one of the site's
# pages ("page:4"). It answers with changes a person sends on
# one at a time (Market::Workup::Sending): a page's title, meta data and
# wording, held in Approvals until a person puts them live; a new post, held
# the same way; a draft page; searches to track; a task on the plan.
# Run in Market::WorkupJob; never raises.
class Market::Workup < ApplicationRecord
  include Sending

  STATES = %w[queued running ready failed].freeze
  STUCK_AFTER = 15.minutes
  MAX_CHANGES = 8
  KINDS = {
    "update_page" => "Update a page", "new_post" => "New post", "new_page" => "New page",
    "track_searches" => "Track searches", "task" => "Task"
  }.freeze

  belongs_to :user, optional: true

  serialize :answer, coder: JSON, type: Hash
  serialize :sent, coder: JSON, type: Hash

  SUBJECT = /\A(?:(?:keyword|map|opportunity|visibility|finding|page):\d+|visibility:own|links:own)\z/

  validates :subject, presence: true, format: {with: SUBJECT}
  validates :state, inclusion: {in: STATES}

  scope :latest_first, -> { order(id: :desc) }

  def self.subject?(subject) = subject.to_s.match?(SUBJECT)

  # The latest work-up of a subject.
  def self.latest(subject) = where(subject: subject).latest_first.first

  def self.start(subject, user:)
    create!(subject: subject, user: user).tap(&:run_later)
  end

  def working? = state.in?(%w[queued running]) && updated_at > STUCK_AFTER.ago
  def ready? = state == "ready"
  def failed? = state == "failed" || (state.in?(%w[queued running]) && !working?)
  def run_later = Market::WorkupJob.perform_later(self)

  def summary = answer["summary"].to_s
  def changes = Array(answer["changes"])
  def sent_for(index) = sent.to_h[index.to_s]

  # Called by Market::WorkupJob.
  def run!
    update!(state: "running", started_at: Time.current)
    raise ArgumentError, Market::Plan.ai_unavailable_reason unless Market::Plan.ai_available?

    brief = Brief.new(subject)
    answer = ::Ai.structured(purpose: "market_workup", system: instructions(brief), prompt: brief.to_s, schema: SCHEMA, user: user)
    update!(answer: {"summary" => answer["summary"].to_s.strip, "changes" => clean(Array(answer["changes"]), brief)},
      state: "ready", finished_at: Time.current, error: nil)
  rescue => error
    Rails.logger.error("[market] workup #{id}: #{error.class}: #{error.message}")
    known = error.is_a?(ArgumentError) || (defined?(::Ai::Error) && (error.is_a?(::Ai::Error) || error.is_a?(::Ai::Unavailable)))
    update_columns(state: "failed", error: (known ? error.message : "#{error.class.name.demodulize}: #{error.message}").truncate(500),
      finished_at: Time.current, updated_at: Time.current)
  end

  SCHEMA = {
    type: "object", additionalProperties: false, required: %w[summary changes],
    properties: {
      summary: {type: "string", description: "What the facts say and what to do about it, in two or three sentences."},
      changes: {type: "array", description: "Up to #{MAX_CHANGES} changes, best first. Fill only the fields a change's kind uses; leave the rest \"\" or [].", items: {
        type: "object", additionalProperties: false,
        required: %w[kind title why page_path page_title meta_title meta_description focus_keyword json_ld text_edits slug body_markdown searches channel],
        properties: {
          kind: {type: "string", enum: KINDS.keys, description: "update_page: change an existing page's title, meta data or wording. new_post: a post written in full. new_page: a page the site needs, which a person builds. track_searches: searches to watch. task: something done off the site (Google Business Profile, reviews, ads, links)."},
          title: {type: "string", description: "The change, as a short instruction."},
          why: {type: "string", description: "What in the facts makes it worth doing."},
          page_path: {type: "string", description: "update_page: the path of one of the site's pages listed, exactly as given."},
          page_title: {type: "string", description: "update_page, new_page, new_post: the new title, or \"\" to keep it."},
          meta_title: {type: "string", description: "Up to 60 characters, or \"\"."},
          meta_description: {type: "string", description: "Up to 155 characters, or \"\"."},
          focus_keyword: {type: "string"},
          json_ld: {type: "string", description: "update_page, new_page, new_post: schema.org JSON-LD for it (LocalBusiness or its subtype, Service, FAQPage, Article…), as a JSON string of one node or a list, from the facts given only; or \"\" to leave it."},
          text_edits: {type: "array", description: "update_page: wording to change, each one of the page's text fields listed for it, by its field id, with its new text in full.",
                       items: {type: "object", additionalProperties: false, required: %w[field text], properties: {field: {type: "string"}, text: {type: "string"}}}},
          slug: {type: "string", description: "new_page, new_post: lowercase-with-hyphens."},
          body_markdown: {type: "string", description: "new_post: the post in full, in Markdown, 500 to 1,000 words, in the brand's voice; no title heading."},
          searches: {type: "array", items: {type: "string"}, description: "track_searches: as people type them."},
          channel: {type: "string", enum: Market::Opportunity::CHANNELS.keys}
        }
      }}
    }
  }.freeze

  private

  def instructions(brief)
    brand = defined?(::BrandBrief) ? ::BrandBrief.to_h.map { |field, text| "#{field.to_s.humanize}: #{text}" }.join("\n") : ""
    [<<~TEXT, ("The brand brief the owners wrote:\n#{brand}" if brand.present?)].compact.join("\n\n")
      You are an SEO and content strategist working on a business's website through its CMS. You are given one thing to work on (#{brief.label}), the facts about it, and the site's pages with their titles and meta data; for the page that matters most, its wording, field by field.
      Everything serves the plan for the business: its big picture and the angle to win on, where given.
      Answer with the changes that would move it, best first: change existing pages before adding new ones (a better title, meta title and description, focus keyword, structured data (JSON-LD) where it's missing or thin, wording that says what the searcher wants), write posts in full where content is missing, and name the work done off the site (Google Business Profile, reviews, citations, ads) as tasks.
      - AI search counts: where AI assistants answer the search without naming the business, change the site so it's the clear answer (a page that says plainly what it does, where, for whom, with the facts the AI cites others for: services, area, prices, reviews, FAQs and LocalBusiness or Service JSON-LD), and name the sites they cite as tasks (get listed or reviewed there).
      - Ground every change in the facts, and say which in why. Never invent figures, reviews, prices, awards or claims about the business that aren't given.
      - Only change a page or field that's listed, by its exact path or field id; keep the wording's purpose and roughly its length.
      - Write as the business, in the brand's voice, plainly.
      Today is #{Date.current.to_fs(:long)}.
    TEXT
  end

  # JSON-LD as the AI wrote it, kept only when it parses into nodes with a type.
  def json_ld(text)
    value = JSON.parse(text.to_s)
    nodes = Array.wrap(value)
    (nodes.any? && nodes.all? { it.is_a?(Hash) && it["@type"].present? }) ? value : nil
  rescue JSON::ParserError
    nil
  end

  # Drops what can't be sent: an update to a page that isn't there, edits to fields that aren't its own.
  def clean(answers, brief)
    answers.first(MAX_CHANGES).filter_map do |change|
      next unless change.is_a?(Hash) && change["kind"].in?(KINDS.keys) && change["title"].present?

      change = change.transform_values { it.is_a?(String) ? it.strip : it }
      change["json_ld"] = json_ld(change["json_ld"])
      if change["kind"] == "update_page"
        fields = brief.fields_of(change["page_path"]) or next
        change["text_edits"] = Array(change["text_edits"]).select { it.is_a?(Hash) && fields.key?(it["field"]) && it["text"].present? }
      end
      change
    end
  end
end
