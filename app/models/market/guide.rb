# frozen_string_literal: true

# What to do next in Market, worked out from where things stand: getting set
# up (each step, done or not, and why it matters), then the few things most
# worth doing now, ranked toward the goals: the plan's opportunities (those
# serving a goal, quick wins and this month's first), the worst findings no
# one has acted on, and goals falling behind.
class Market::Guide
  Step = Data.define(:key, :title, :why, :done, :label, :path, :optional)
  Action = Data.define(:key, :title, :why, :kind, :record, :tone)

  include Rails.application.routes.url_helpers

  NEXT = 5

  def initialize(profile: Market::Profile.current, settings: Market::Settings.current)
    @profile = profile
    @settings = settings
  end

  # Setting up, in order: each step and whether it's done.
  def steps
    @steps ||= [
      Step.new(key: :profile, title: "Describe the business", why: "What it sells, to whom and where: every finding, plan and suggestion starts here.",
        done: @profile.industry.present? && (@profile.service_area.present? || @profile.local?), label: "Describe it", path: edit_market_profile_path, optional: false),
      Step.new(key: :goals, title: "Set a goal or two", why: "What the marketing is for, measurably (calls, a place on Maps, being named by AI), so the plan aims at it.",
        done: Market::Goal.active.exists?, label: "Set goals", path: market_plan_path(anchor: "goals"), optional: false),
      Step.new(key: :competitors, title: "Name the competitors", why: "The businesses customers choose instead: their websites are read every week and compared.",
        done: Market::Competitor.count >= 2, label: "Add competitors", path: new_market_competitor_path, optional: false),
      Step.new(key: :searches, title: "Track the searches customers make", why: "What people type to find a business like this one: each is checked on Google, Maps and the AIs.",
        done: Market::Keyword.count >= 3, label: "Track searches", path: market_search_path(anchor: "tracked"), optional: false),
      Step.new(key: :dataforseo, title: "Connect DataForSEO", why: "Where the search data comes from, on your own account, within a monthly budget you set.",
        done: @settings.search_connected?, label: "Connect it", path: settings_market_path, optional: false),
      Step.new(key: :pull, title: "Pull the search data", why: "The first look at how the site, the competitors and the searches stand.",
        done: Market::SearchPull.where(state: %w[ready partial]).exists?, label: "Go to Search", path: market_search_path, optional: false),
      (google_step if defined?(::Google) && Cms::Plugins.enabled?(:google)),
      Step.new(key: :ai, title: "Set up the AI", why: "It drafts the plan, sizes up competitors and writes the suggestions; Market works without it, more slowly.",
        done: Market::Plan.ai_available?, label: "Set it up", path: "/#{Cms::PATH}/settings/ai", optional: true),
      Step.new(key: :plan, title: "Draft the plan", why: "The big picture and the opportunities, from everything known, aimed at the goals.",
        done: Market::Plan.where(state: "ready").exists?, label: "Go to the plan", path: market_plan_path, optional: false)
    ].compact
  end

  def set_up? = steps.reject(&:optional).all?(&:done)
  def next_step = steps.find { !it.done }

  # The few things most worth doing now.
  def actions
    @actions ||= begin
      goals = Market::Goal.active.to_a
      behind = goals.select { it.on_pace? == false }.map do |goal|
        Action.new(key: "goal:#{goal.id}", title: "#{goal.title} is behind", why: "#{goal.describe(goal.current)} now, #{goal.describe(goal.target)} by #{goal.due_on&.to_fs(:long)}.",
          kind: :goal, record: goal, tone: :urgent)
      end
      opportunities = Market::Opportunity.by_priority(Market::Opportunity.active.includes(:goal).to_a)
        .sort_by { [it.goal_id ? 0 : 1, (it.horizon == "now") ? 0 : 1, -it.priority] }.map do |opportunity|
          Action.new(key: "opportunity:#{opportunity.id}", title: opportunity.title,
            why: [("For: #{opportunity.goal.title}" if opportunity.goal), "#{opportunity.impact.capitalize} impact, #{opportunity.effort} effort", opportunity.horizon_label].compact.join(" · "),
            kind: :opportunity, record: opportunity, tone: (opportunity.quick_win? ? :quick : :normal))
        end
      findings = Market::Finding.open.where(severity: "high").by_severity.reject(&:opportunity).first(3).map do |finding|
        Action.new(key: "finding:#{finding.id}", title: finding.title, why: finding.detail.to_s.truncate(140), kind: :finding, record: finding, tone: :urgent)
      end
      (behind + findings + opportunities).first(NEXT)
    end
  end

  private

  def google_step
    Step.new(key: :google, title: "Connect Google", why: "Real clicks, enquiries, calls and reviews (Search Console, Analytics, Business Profile) to measure the goals by.",
      done: ::Google::Settings.current.connected?, label: "Connect Google", path: "/#{Cms::PATH}/settings/google", optional: true)
  end
end
