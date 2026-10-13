# frozen_string_literal: true

module Market
  # A competitor's changes made an opportunity on the plan.
  class ChangeOpportunitiesController < ApplicationController
    requires_capability "market:write", only: :create

    def create
      reading = Reading.where.not(competitor_id: nil).find(params[:change_id])
      opportunity = reading.to_opportunity
      redirect_to back_or(market_overview_path(tab: "changes", item: reading.id)), notice: "On the plan: “#{opportunity.title}”"
    end
  end
end
