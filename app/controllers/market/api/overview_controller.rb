# frozen_string_literal: true

module Market
  module Api
    # GET /api/market: the market at a glance.
    class OverviewController < BaseController
      requires_capability "market:read", only: :show

      def show
        @profile = Profile.current
        @findings = Finding.open.by_severity.to_a
        @opportunities = Opportunity.by_priority(Opportunity.open.to_a).first(10)
        @changes = Reading.where.not(competitor_id: nil).where(taken_at: 30.days.ago..).where.not(differences: [nil, "[]"])
          .latest_first.includes(:competitor).limit(20).to_a
        @own = Reading.own_latest
        @competitors = Competitor.count
      end
    end
  end
end
