# frozen_string_literal: true

module Market
  # Opportunities: added by hand, marked done, dismissed or open again, deleted.
  class OpportunitiesController < ApplicationController
    requires_capability "market:read", only: :index
    requires_capability "market:write", only: [:create, :update, :destroy]

    def index
      redirect_to market_plan_path(anchor: "opportunities")
    end

    def create
      opportunity = Opportunity.new(params.require(:opportunity).permit(:title, :channel, :detail, :evidence, :impact, :effort, :horizon, :goal_id))
      if opportunity.save
        redirect_to back_or(market_plan_path(item: opportunity.id)), notice: "Added “#{opportunity.title}”"
      else
        redirect_to market_plan_path(anchor: "opportunities"), alert: opportunity.errors.full_messages.to_sentence
      end
    end

    def update
      opportunity = Opportunity.find(params[:id])
      attributes = params.require(:opportunity).permit(:state, :title, :channel, :detail, :evidence, :impact, :effort, :horizon, :goal_id)
      case attributes.delete(:state)
      when "done" then opportunity.complete(by: Current.user)
      when "dismissed" then opportunity.dismiss(by: Current.user)
      when "planned" then opportunity.plan_it(by: Current.user)
      when "open" then opportunity.reopen
      end
      opportunity.update(attributes) if attributes.present?
      redirect_to back_or(market_plan_path(anchor: "opportunities")), notice: "“#{opportunity.title}”: #{opportunity.state}"
    end

    def destroy
      opportunity = Opportunity.find(params[:id])
      opportunity.destroy!
      redirect_to back_or(market_plan_path(anchor: "opportunities")), notice: "Deleted “#{opportunity.title}”"
    end
  end
end
