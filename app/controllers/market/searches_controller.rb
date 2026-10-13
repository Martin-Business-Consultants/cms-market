# frozen_string_literal: true

module Market
  # Search: visibility against each competitor, the searches tracked and who
  # ranks where (with the site's page), and the sites sharing its keywords.
  # A row opens a sheet with its facts and the AI's suggestions (?sheet=), and
  # Search Console's figures show beside DataForSEO's when Google is connected.
  class SearchesController < ApplicationController
    requires_capability "market:read", only: :show

    def show
      @data = Search::Overview.new
      @settings = Settings.current
      @google = ::Google.search_console if defined?(::Google) && ::Google.respond_to?(:search_console)
      @sheet = params[:sheet].to_s.presence
      return unless @sheet && Workup.subject?(@sheet)

      @brief = Workup::Brief.new(@sheet)
      @workup = Workup.latest(@sheet)
    rescue ActiveRecord::RecordNotFound
      @sheet = nil
    end
  end
end
