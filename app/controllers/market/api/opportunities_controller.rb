# frozen_string_literal: true

module Market
  module Api
    # /api/market/opportunities: best first.
    class OpportunitiesController < BaseController
      STATES = %w[open planned done dismissed active all].freeze

      requires_capability "market:read", only: :index
      requires_capability "market:write", only: [:create, :update, :destroy]

      def index
        @state = params[:state].presence_in(STATES) || "active"
        scope = Opportunity.includes(:page)
        scope = scope.where(state: (@state == "active") ? Opportunity::ACTIVE : @state) unless @state == "all"
        scope = scope.where(channel: params[:channel]) if params[:channel].present?
        scope = scope.where(horizon: params[:horizon]) if params[:horizon].present?
        @opportunities = Opportunity.by_priority(scope.to_a)
      end

      def create
        @opportunity = Opportunity.create!(opportunity_params.except(:state))
        render partial: "market/api/opportunities/opportunity", locals: {opportunity: @opportunity}, status: :created
      end

      def update
        @opportunity = Opportunity.find(params[:id])
        attributes = opportunity_params
        case attributes.delete(:state)
        when "done" then @opportunity.complete(by: Current.user)
        when "dismissed" then @opportunity.dismiss(by: Current.user)
        when "planned" then @opportunity.plan_it(by: Current.user)
        when "open" then @opportunity.reopen
        end
        @opportunity.update!(attributes) if attributes.present?
        render partial: "market/api/opportunities/opportunity", locals: {opportunity: @opportunity}
      end

      def destroy
        Opportunity.find(params[:id]).destroy!
        head :no_content
      end

      private

      def opportunity_params = params.require(:opportunity).permit(:state, :title, :channel, :detail, :evidence, :impact, :effort, :horizon)
    end
  end
end
