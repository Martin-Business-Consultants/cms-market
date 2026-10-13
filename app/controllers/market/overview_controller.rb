# frozen_string_literal: true

module Market
  # The market at a glance: the profile and what's missing from it, then three
  # tabs, each a list beside the one open, where it's acted on: what the data
  # says, the best opportunities, and what competitors changed.
  class OverviewController < ApplicationController
    TABS = {"findings" => "What the data says", "opportunities" => "Best opportunities", "changes" => "What competitors changed"}.freeze

    requires_capability "market:read", only: :show

    def show
      @profile = Profile.current
      @own = Reading.own_latest
      @competitor_count = Competitor.count
      @findings = Finding.open.by_severity.to_a
      @opportunities = Opportunity.by_priority(Opportunity.active.includes(:page).to_a)
      @changes = Reading.where.not(competitor_id: nil).where(taken_at: 60.days.ago..).where.not(differences: [nil, "[]"])
        .latest_first.includes(:competitor).limit(30).to_a
      @tab = params[:tab].presence_in(TABS.keys) || "findings"
      @items = {"findings" => @findings, "opportunities" => @opportunities, "changes" => @changes}.fetch(@tab)
      @item = @items.find { it.id.to_s == params[:item].to_s } || @items.first
    end
  end
end
