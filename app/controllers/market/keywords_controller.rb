# frozen_string_literal: true

module Market
  # Searches tracked: added one a line, and taken off.
  class KeywordsController < ApplicationController
    requires_capability "market:write", only: [:create, :destroy]

    def create
      attributes = params.require(:keyword).permit(:keywords, :source)
      added, skipped = Keyword.track(attributes[:keywords], source: attributes[:source])
      message = added.any? ? "Tracking #{added.map { "“#{it.keyword}”" }.to_sentence}" : "Nothing new to track"
      message += " (#{skipped} already tracked or over the limit)" if skipped.positive?
      redirect_to back_or(market_search_path(anchor: "tracked")), (added.any? ? :notice : :alert) => message
    end

    def destroy
      keyword = Keyword.find(params[:id])
      keyword.destroy!
      redirect_to market_search_path(anchor: "tracked"), notice: "Stopped tracking “#{keyword.keyword}”"
    end
  end
end
