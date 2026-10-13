# frozen_string_literal: true

module Market
  module Api
    # GET /api/market/links: the site's links and its competitors' (Market::Links).
    class LinksController < BaseController
      requires_capability "market:read", only: :show

      def show
        render json: Links.new.as_api
      end
    end
  end
end
