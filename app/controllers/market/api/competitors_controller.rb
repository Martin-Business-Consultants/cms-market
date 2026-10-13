# frozen_string_literal: true

module Market
  module Api
    # /api/market/competitors: each with its latest website reading and what changed.
    class CompetitorsController < BaseController
      requires_capability "market:read", only: [:index, :show]
      requires_capability "market:write", only: [:create, :update, :destroy]

      before_action :set_competitor, only: [:show, :update, :destroy]

      def index
        @competitors = Competitor.by_threat.to_a
        @readings = Reading.latest_for(@competitors)
        @own = Reading.own_latest
      end

      def show
        @readings = @competitor.readings.limit(12).to_a
      end

      def create
        existing = Competitor.matching(name: competitor_params[:name], website: competitor_params[:website])
        return refuse("#{existing.name} is already watched (id #{existing.id})") if existing

        @competitor = Competitor.create!(competitor_params)
        @competitor.check_later if @competitor.domain
        Finding.refresh_later
        @readings = []
        render :show, status: :created
      end

      def update
        was = @competitor.domain
        @competitor.update!(competitor_params)
        @competitor.check_later if @competitor.domain && @competitor.domain != was
        Finding.refresh_later
        @readings = @competitor.readings.limit(12).to_a
        render :show
      end

      def destroy
        @competitor.destroy!
        Finding.refresh_later
        head :no_content
      end

      private

      def set_competitor = @competitor = Competitor.find(params[:id])
      def competitor_params = params.require(:competitor).permit(:name, :website, :kind, :threat, :strengths, :weaknesses, :notes)
    end
  end
end
