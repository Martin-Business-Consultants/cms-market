# frozen_string_literal: true

module Market
  module Api
    # POST /api/market/opportunities/:id/page: a draft page started for it.
    class OpportunityPagesController < BaseController
      requires_capability "market:write", only: :create
      requires_capability "pages:write", only: :create

      def create
        opportunity = Opportunity.find(params[:opportunity_id])
        return refuse("“#{opportunity.title}” already has a page: /api/pages/#{opportunity.page.path}") if opportunity.page

        page = opportunity.start_page(by: Current.user, title: params.dig(:page, :title))
        render json: {page: {id: page.id, path: page.path, title: page.title, status: page.status, api: "/api/pages/#{page.path}"},
                      opportunity: {id: opportunity.id, state: opportunity.state}}, status: :created
      end
    end
  end
end
