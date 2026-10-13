# frozen_string_literal: true

module Market
  module Api
    # POST /api/market/competitors/:id/check: reads its website again, in the background.
    class CompetitorChecksController < BaseController
      requires_capability "market:write", only: :create

      def create
        competitor = Competitor.find(params[:competitor_id])
        return refuse("#{competitor.name} has no website to read") unless competitor.domain

        competitor.check_later
        render json: {status: "queued", message: "Reading #{competitor.domain}: its reading and changes show on /api/market/competitors/#{competitor.id} in a few seconds."}, status: :accepted
      end
    end
  end
end
