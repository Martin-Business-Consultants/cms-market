# frozen_string_literal: true

module Market
  # Pulls of search data: the history, and a new one, which spends from the month's budget.
  class SearchPullsController < ApplicationController
    requires_capability "market:read", only: :index
    requires_capability "market:search", only: :create

    def index
      @pulls = SearchPull.latest_first.includes(:user).limit(30).to_a
    end

    def create
      refusal = SearchPull.refusal
      return redirect_to(back_or(market_search_path), alert: refusal) if refusal

      pull = SearchPull.create!(user: Current.user, force: ActiveModel::Type::Boolean.new.cast(params.dig(:pull, :force)) || false)
      pull.run_later
      redirect_to back_or(market_search_path), notice: "Pulling search data: a minute or two. At most $#{format("%.2f", SearchPull.ceiling)}."
    end
  end
end
