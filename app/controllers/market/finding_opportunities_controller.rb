# frozen_string_literal: true

module Market
  # A finding made an opportunity on the plan.
  class FindingOpportunitiesController < ApplicationController
    requires_capability "market:write", only: :create

    def create
      finding = Finding.find(params[:finding_id])
      opportunity = finding.to_opportunity
      redirect_to back_or(market_findings_path(state: params[:state].presence, finding: finding.id)), notice: "On the plan: “#{opportunity.title}”"
    end
  end
end
