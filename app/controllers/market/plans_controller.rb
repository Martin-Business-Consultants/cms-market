# frozen_string_literal: true

module Market
  # The plan: the latest one Claude drafted, its suggestions to take, the
  # opportunities, and earlier plans; and a new one.
  class PlansController < ApplicationController
    requires_capability "market:read", only: :show
    requires_capability "market:write", only: :create

    def show
      @plans = Plan.latest_first.includes(:user).limit(12).to_a
      @plan = @plans.first
      @opportunities = Opportunity.by_priority(Opportunity.includes(:page).to_a)
      @settings = Settings.current
    end

    def create
      return redirect_to(market_plan_path, alert: "Add an Anthropic API key in Settings › Market first") unless Settings.current.ai?
      return redirect_to(market_plan_path, alert: "A plan is already being drafted") if Plan.drafting?

      Plan.create!(user: Current.user).run_later
      redirect_to market_plan_path, notice: "Drafting the plan: a minute or two"
    end
  end
end
