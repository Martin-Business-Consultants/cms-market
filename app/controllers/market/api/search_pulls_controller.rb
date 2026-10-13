# frozen_string_literal: true

module Market
  module Api
    # /api/market/search/pulls: their state, cost and notes; POST spends from the month's budget.
    class SearchPullsController < BaseController
      requires_capability "market:read", only: :index
      requires_capability "market:search", only: :create

      def index
        @pulls = SearchPull.latest_first.includes(:user).limit(30).to_a
      end

      def create
        refusal = SearchPull.refusal
        return refuse(refusal) if refusal

        pull = SearchPull.create!(user: Current.user, force: ActiveModel::Type::Boolean.new.cast(params.dig(:pull, :force)) || false)
        pull.run_later
        @pulls = [pull]
        render :index, status: :accepted
      end
    end
  end
end
