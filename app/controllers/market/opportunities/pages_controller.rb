# frozen_string_literal: true

module Market
  module Opportunities
    # A draft page started for an opportunity: the work begins in the CMS.
    class PagesController < Market::ApplicationController
      requires_capability "pages:write", only: :create
      requires_capability "market:write", only: :create

      def create
        opportunity = Opportunity.find(params[:opportunity_id])
        page = opportunity.start_page(by: Current.user, title: params.dig(:page, :title))
        redirect_to edit_page_path(page.path), notice: "Draft page started for “#{opportunity.title}”"
      rescue ActiveRecord::RecordInvalid => error
        redirect_to market_plan_path(anchor: "opportunities"), alert: error.record.errors.full_messages.to_sentence
      end
    end
  end
end
