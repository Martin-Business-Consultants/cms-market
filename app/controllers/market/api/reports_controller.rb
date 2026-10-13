# frozen_string_literal: true

module Market
  module Api
    # /api/market/report: the health score, its parts, and every series the Report screen charts (?months=3|6|12).
    class ReportsController < BaseController
      requires_capability "market:read", only: :show

      def show
        months = params[:months].to_i.presence_in([3, 6, 12]) || 6
        @report = Report.new(since: months.months.ago)
      end
    end
  end
end
