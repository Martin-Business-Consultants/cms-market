# frozen_string_literal: true

module Market
  module Competitors
    # One of the moves to beat a competitor, made an opportunity on the plan.
    class MovesController < Market::ApplicationController
      requires_capability "market:write", only: :create

      def create
        competitor = Competitor.find(params[:competitor_id])
        opportunity = competitor.move_to_opportunity(params[:index].to_i)
        redirect_to back_or(market_competitor_path(competitor)), notice: "On the plan: “#{opportunity.title}”"
      end
    end
  end
end
