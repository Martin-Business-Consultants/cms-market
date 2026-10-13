# frozen_string_literal: true

module Market
  # Search: visibility against each competitor, the searches tracked and who
  # ranks where (with the site's page), and the sites sharing its keywords.
  # A row opens a sheet with its facts and the AI's suggestions (?sheet=), and
  # Search Console's figures show beside DataForSEO's when Google is connected.
  class SearchesController < ApplicationController
    # Each tab, and what it shows and from where.
    TABS = {
      "searches" => ["Searches", "The searches customers make: where the site is on Google, on Maps and in each AI's answer for each, what it's worth, and what to write around it."],
      "ai" => ["AI", "How AI assistants answer the tracked searches (ChatGPT, Gemini, Perplexity, Claude, Copilot, Google's AI Overview and AI Mode): whether they name the business, and who and what they cite instead."],
      "local" => ["Local", "Where the business shows on Google Maps, point by point across its area."],
      "website" => ["Website", "The site itself against the competitors: how visible each is in search (estimated), over the year, their links, the home page's health, and the web naming them."],
      "reputation" => ["Reputation", "What customers see and say: each business's reviews on Google (and Trustpilot, Tripadvisor), and its Business Profile."]
    }.freeze

    requires_capability "market:read", only: :show

    def show
      @data = Search::Overview.new
      @settings = Settings.current
      @tab = params[:tab].presence_in(TABS.keys - ["local"]) || "searches"
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
