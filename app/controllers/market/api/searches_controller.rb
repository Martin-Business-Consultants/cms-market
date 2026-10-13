# frozen_string_literal: true

module Market
  module Api
    # GET /api/market/search?keywords=50: every site's visibility now and
    # before, the keywords each ranks for, the tracked searches with everyone's
    # positions and the site's page, and the sites sharing its keywords.
    class SearchesController < BaseController
      requires_capability "market:read", only: :show

      def show
        @limit = params[:keywords].to_i.clamp(0, 500).nonzero? || 50
        @data = Search::Overview.new
      end
    end
  end
end
