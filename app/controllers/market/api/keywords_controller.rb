# frozen_string_literal: true

module Market
  module Api
    # /api/market/keywords: the searches tracked.
    class KeywordsController < BaseController
      requires_capability "market:read", only: :index
      requires_capability "market:write", only: [:create, :destroy]

      def index
        @keywords = Keyword.ordered.to_a
        @rankings = Ranking.latest_for(@keywords)
      end

      def create
        attributes = params.require(:keyword).permit(:keywords, :keyword, :source)
        added, skipped = Keyword.track(attributes[:keywords].presence || attributes[:keyword], source: attributes[:source])
        render json: {added: added.map { {id: it.id, keyword: it.keyword} }, skipped: skipped}, status: added.any? ? :created : :ok
      end

      def destroy
        Keyword.find(params[:id]).destroy!
        head :no_content
      end
    end
  end
end
