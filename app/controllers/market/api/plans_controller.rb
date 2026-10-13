# frozen_string_literal: true

module Market
  module Api
    # /api/market/plans: the latest first; POST drafts a new one (a minute or two).
    class PlansController < BaseController
      requires_capability "market:read", only: :index
      requires_capability "market:write", only: :create

      def index
        @plans = Plan.latest_first.includes(:opportunities).limit(12).to_a
      end

      def create
        return refuse("Add an Anthropic API key in Settings › Market first") unless Settings.current.ai?
        return refuse("A plan is already being drafted") if Plan.drafting?

        plan = Plan.create!(user: Current.user)
        plan.run_later
        @plans = [plan]
        render :index, status: :accepted
      end
    end
  end
end
