# frozen_string_literal: true

module Market
  # Where Market starts: the goals and how each is going, the few things most
  # worth doing now (Market::Guide) beside the one open, where it's acted on,
  # the steps left to get set up, and what competitors changed lately.
  class OverviewController < ApplicationController
    requires_capability "market:read", only: :show

    def show
      @profile = Profile.current
      @guide = Guide.new(profile: @profile)
      @goals = Goal.active.ordered.includes(:keyword).to_a
      @actions = @guide.actions
      @action = @actions.find { it.key == params[:item].to_s } || @actions.first
      @changes = Reading.where.not(competitor_id: nil).where(taken_at: 30.days.ago..).where.not(differences: [nil, "[]"])
        .latest_first.includes(:competitor).limit(6).to_a
    end
  end
end
