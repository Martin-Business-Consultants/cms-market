# frozen_string_literal: true

module Market
  # Maps: each tracked search on Google Maps across the business's area, and
  # the open one beside the list: the grid point by point, who leads, the
  # next steps and the AI's work-up.
  class MapsController < ApplicationController
    requires_capability "market:read", only: :show

    def show
      @profile = Profile.current
      @settings = Settings.current
      @keywords = Keyword.ordered.to_a
      @scans = LocalScan.latest_for(@keywords)
      @keyword = @keywords.find { it.id == params[:keyword].to_i } || @keywords.find { @scans[it.id] } || @keywords.first
      @point = params[:point].to_s
      @steps = MapSteps.new(@keyword, @scans[@keyword.id]&.first, profile: @profile, settings: @settings) if @keyword
    end
  end
end
