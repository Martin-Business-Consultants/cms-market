# frozen_string_literal: true

module Market
  # Search: visibility against each competitor, the searches tracked and who
  # ranks where (with the site's page), and the sites sharing its keywords.
  class SearchesController < ApplicationController
    requires_capability "market:read", only: :show

    def show
      @data = Search::Overview.new
      @settings = Settings.current
    end
  end
end
