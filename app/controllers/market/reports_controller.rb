# frozen_string_literal: true

module Market
  # Report: the market's health in one score and its parts, and how each
  # figure has moved, charted (Market::Report).
  class ReportsController < ApplicationController
    PERIODS = {"3m" => 3.months, "6m" => 6.months, "12m" => 12.months}.freeze

    requires_capability "market:read", only: :show

    def show
      @period = params[:period].presence_in(PERIODS.keys) || "6m"
      @report = Report.new(since: PERIODS.fetch(@period).ago)
    end
  end
end
