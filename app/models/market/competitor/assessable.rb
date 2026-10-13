# frozen_string_literal: true

# A competitor sized up by the install's AI (the AI plugin) from what's known
# about it and about the business: its readings, its search data, the
# keywords it wins, the map, the findings about it. The answer is kept on the
# competitor (strengths, weaknesses, threat, and moves to beat it); a person
# takes the strengths and weaknesses onto the record, and makes moves
# opportunities. Run in Market::AssessmentJob; never raises.
module Market::Competitor::Assessable
  extend ActiveSupport::Concern

  MOVES = 5

  included do
    serialize :analysis, coder: JSON, type: Hash
  end

  def assessing? = analysis_state.in?(%w[queued running]) && updated_at > 15.minutes.ago
  def assessed? = analysis_state == "ready" && analysis.present?
  def moves = Array(analysis&.dig("moves"))

  def assess_later
    update_columns(analysis_state: "queued", analysis_error: nil, updated_at: Time.current)
    Market::AssessmentJob.perform_later(self)
  end

  def move_key(index) = "competitor:#{id}:move:#{moves[index].to_h["title"].to_s.parameterize.first(60)}"
  def move_opportunity(index) = Market::Opportunity.where(finding_key: move_key(index)).order(:id).last

  # A move made an opportunity on the plan.
  def move_to_opportunity(index)
    move = moves[index] or raise ActiveRecord::RecordNotFound
    move_opportunity(index) || Market::Opportunity.create!(finding_key: move_key(index), title: move["title"].to_s.truncate(200),
      channel: move["channel"].presence_in(Market::Opportunity::CHANNELS.keys) || "seo", detail: move["detail"].presence,
      evidence: "To beat #{name}: #{move["why"]}".truncate(1000), impact: move["impact"].presence_in(Market::Opportunity::IMPACTS) || "medium",
      effort: move["effort"].presence_in(Market::Opportunity::EFFORTS) || "medium", horizon: "next")
  end

  # Takes the assessment's strengths, weaknesses and threat onto the competitor.
  def adopt_assessment
    update!(strengths: Array(analysis["strengths"]).join("\n").presence || strengths, weaknesses: Array(analysis["weaknesses"]).join("\n").presence || weaknesses,
      threat: analysis["threat"].presence_in(Market::Competitor::THREATS) || threat)
  end

  # Called by Market::AssessmentJob.
  def assess!
    update_columns(analysis_state: "running", updated_at: Time.current)
    raise ArgumentError, Market::Plan.ai_unavailable_reason unless Market::Plan.ai_available?

    answer = ::Ai.structured(purpose: "market_competitor", system: assessment_instructions, prompt: assessment_brief, schema: ASSESSMENT_SCHEMA)
    update_columns(analysis: answer.slice("summary", "strengths", "weaknesses", "threat", "threat_why", "moves").merge("moves" => Array(answer["moves"]).first(MOVES)),
      analysis_state: "ready", analysed_at: Time.current, analysis_error: nil, updated_at: Time.current)
  rescue => error
    Rails.logger.error("[market] assessing competitor #{id}: #{error.class}: #{error.message}")
    known = error.is_a?(ArgumentError) || (defined?(::Ai::Error) && (error.is_a?(::Ai::Error) || error.is_a?(::Ai::Unavailable)))
    update_columns(analysis_state: "failed", analysis_error: (known ? error.message : "#{error.class.name.demodulize}: #{error.message}").truncate(500), updated_at: Time.current)
  end

  ASSESSMENT_SCHEMA = {
    type: "object", additionalProperties: false, required: %w[summary strengths weaknesses threat threat_why moves],
    properties: {
      summary: {type: "string", description: "Two or three sentences: how this competitor wins customers and where it stands against the business."},
      strengths: {type: "array", items: {type: "string"}, description: "What it does well, from the facts, up to 5, each a short line."},
      weaknesses: {type: "array", items: {type: "string"}, description: "Where it's weak or open to being beaten, up to 5."},
      threat: {type: "string", enum: Market::Competitor::THREATS},
      threat_why: {type: "string"},
      moves: {type: "array", description: "Up to #{MOVES} specific moves for the business to beat this competitor, best first.", items: {
        type: "object", additionalProperties: false, required: %w[title channel detail why impact effort],
        properties: {
          title: {type: "string", description: "What to do, as a short instruction."},
          channel: {type: "string", enum: Market::Opportunity::CHANNELS.keys},
          detail: {type: "string", description: "How, in two sentences."},
          why: {type: "string", description: "What about this competitor makes it worth doing."},
          impact: {type: "string", enum: Market::Opportunity::IMPACTS},
          effort: {type: "string", enum: Market::Opportunity::EFFORTS}
        }
      }}
    }
  }.freeze

  private

  def assessment_instructions
    <<~TEXT
      You are a marketing strategist sizing up one competitor of a business, to plan how the business beats it. You are given the business's profile, readings of both websites taken from outside, search data where it's been pulled (visibility, the keywords each wins), where they rank on Google Maps across the business's area, and the findings already worked out.
      Be specific to this competitor and ground everything in the facts given; never invent reviews, prices or rankings that aren't there. Moves should be things the business can do itself: pages, posts, ads, its Google Business Profile, reviews, offers.
      Today is #{Date.current.to_fs(:long)}.
    TEXT
  end

  def assessment_brief
    profile = Market::Profile.current
    own = Market::Reading.own_latest
    theirs = latest_reading
    search = Market::SearchSnapshot.latest_by_site([id])
    findings = Market::Finding.open.select { it.key.end_with?(":#{domain}") || it.evidence.to_s.include?(name) }
    leads = Market::LocalScan.latest_for(Market::Keyword.all).values.filter_map(&:first)
      .filter_map { |scan| leader = scan.leaders.find { it["title"].to_s.casecmp?(name) || Market::Probe.normalize(it["domain"]) == domain } and "#{scan.keyword.keyword}: top 3 at #{leader["top3_points"]} of #{scan.points.size} points" }
    [
      "The business: #{profile.business_name} (#{profile.website})\n" + Market::Profile::FIELDS.filter_map { |field| "#{Market::Profile::LABELS[field]}: #{profile.public_send(field)}" if profile.public_send(field) }.join("\n"),
      "The competitor: #{name} (#{website || "no website"}), #{kind_label.downcase}, #{threat} threat#{"\nNotes: #{notes}" if notes.present?}",
      ("The business's website: #{JSON.generate(own.facts)}" if own),
      (theirs ? "The competitor's website (read #{theirs.taken_at.to_date.to_fs(:long)}): #{JSON.generate(theirs.facts)}\nRecent changes: #{Array(theirs.differences).join("; ")}" : "The competitor's website hasn't been read."),
      (search[id].present? ? "The competitor's search data: #{JSON.generate(search[id].transform_values { it.first&.data })}" : nil),
      (search[nil].present? ? "The business's search data: #{JSON.generate(search[nil].slice("overview").transform_values { it.first&.data })}" : nil),
      ("On Google Maps across the business's area, the competitor leads: #{leads.join("; ")}" if leads.any?),
      ("Findings about it: #{findings.map { "#{it.title} #{JSON.generate(it.evidence)}" }.join("\n").truncate(4000)}" if findings.any?)
    ].compact.join("\n\n")
  end
end
