# frozen_string_literal: true

module Market
  module Competitors
    # Sizing a competitor up with the AI (create), and taking its strengths, weaknesses and threat onto the record (update).
    class AssessmentsController < Market::ApplicationController
      requires_capability "market:write", only: [:create, :update]

      before_action { @competitor = Competitor.find(params[:competitor_id]) }

      def create
        return redirect_to(market_competitor_path(@competitor), alert: Plan.ai_unavailable_reason) unless Plan.ai_available?

        @competitor.assess_later
        redirect_to market_competitor_path(@competitor), notice: "Sizing up #{@competitor.name}: a minute or so"
      end

      def update
        @competitor.adopt_assessment
        Finding.refresh_later
        redirect_to market_competitor_path(@competitor), notice: "Strengths, weaknesses and threat saved on #{@competitor.name}"
      end
    end
  end
end
