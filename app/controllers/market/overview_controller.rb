# frozen_string_literal: true

module Market
  # The market at a glance: what's missing from the profile, what the data
  # says (worst first), the best opportunities, and what competitors changed.
  class OverviewController < ApplicationController
    requires_capability "market:read", only: :show

    def show
      @profile = Profile.current
      @findings = Finding.open.by_severity.to_a
      @opportunities = Opportunity.by_priority(Opportunity.open.to_a).first(8)
      @changes = Reading.where.not(competitor_id: nil).where(taken_at: 30.days.ago..).where.not(differences: [nil, "[]"])
        .latest_first.includes(:competitor).limit(10).to_a
      @competitor_count = Competitor.count
      @own = Reading.own_latest
    end
  end
end
