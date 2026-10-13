# frozen_string_literal: true

module Market
  module Competitors
    # Reads a competitor's website again now, in the background.
    class ChecksController < Market::ApplicationController
      requires_capability "market:write", only: :create

      def create
        competitor = Competitor.find(params[:competitor_id])
        return redirect_to(market_competitor_path(competitor), alert: "Add #{competitor.name}'s website first") unless competitor.domain

        competitor.check_later
        redirect_to market_competitor_path(competitor), notice: "Reading #{competitor.domain}: refresh in a few seconds"
      end
    end
  end
end
