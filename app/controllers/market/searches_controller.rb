# frozen_string_literal: true

module Market
  # Search: visibility against each competitor, the searches tracked and who
  # ranks where (with the site's page), and the sites sharing its keywords.
  # A row opens a sheet with its facts and the AI's suggestions (?sheet=).
  class SearchesController < ApplicationController
    requires_capability "market:read", only: :show

    def show
      @data = Search::Overview.new
      @settings = Settings.current
      @sheet = params[:sheet].to_s.presence_in(sheets)
      return unless @sheet

      @brief = Workup::Brief.new(@sheet)
      @workup = Workup.latest(@sheet)
    end

    private

    # What can open in the sheet: a site's visibility, a tracked search.
    def sheets
      ["visibility:own", *@data.competitor_sites.map { "visibility:#{it.competitor.id}" }, *@data.keywords.map { "keyword:#{it.id}" }]
    end
  end
end
