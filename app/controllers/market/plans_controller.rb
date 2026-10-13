# frozen_string_literal: true

module Market
  # The plan: the goals and how each is going, the big picture the AI drafted
  # (and its suggestions to take), and the opportunities, grouped by when,
  # beside the one open, where it's worked out and acted on.
  class PlansController < ApplicationController
    TABS = {"open" => "Open", "done" => "Done", "dismissed" => "Dismissed"}.freeze

    requires_capability "market:read", only: :show
    requires_capability "market:write", only: :create

    def show
      @plans = Plan.latest_first.includes(:user).limit(12).to_a
      @plan = @plans.first
      @goals = Goal.ordered.includes(:keyword).where.not(state: "dropped").to_a
      @settings = Settings.current
      @tab = params[:tab].presence_in(TABS.keys) || "open"
      all = Opportunity.includes(:page, :goal).to_a
      @counts = {"open" => all.count(&:active?), "done" => all.count { it.state == "done" }, "dismissed" => all.count { it.state == "dismissed" }}
      shown = all.select { (@tab == "open") ? it.active? : it.state == @tab }
      @opportunities = Opportunity.by_priority(shown).sort_by { [it.goal_id ? 0 : 1, Opportunity::HORIZONS.keys.index(it.horizon)] }
      @opportunity = shown.find { it.id.to_s == params[:item].to_s } || @opportunities.first
    end

    def create
      return redirect_to(market_plan_path, alert: Plan.ai_unavailable_reason) unless Plan.ai_available?
      return redirect_to(market_plan_path, alert: "A plan is already being drafted") if Plan.drafting?

      Plan.create!(user: Current.user).run_later
      redirect_to market_plan_path, notice: "Drafting the plan, aimed at the goals: a minute or two"
    end
  end
end
