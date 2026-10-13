# frozen_string_literal: true

module Market
  # Competitors, and the site beside them: what each website shows (pages,
  # posts, locations, services, the tools it runs), read weekly.
  class CompetitorsController < ApplicationController
    requires_capability "market:read", only: [:index, :show]
    requires_capability "market:write", only: [:new, :create, :edit, :update, :destroy]

    before_action :set_competitor, only: [:show, :edit, :update, :destroy]

    def index
      @competitors = Competitor.by_threat.to_a
      @readings = Reading.latest_for(@competitors)
      @own = Reading.own_latest
      @profile = Profile.current
      findings = Finding.open.to_a
      tracked = Keyword.pluck(:keyword)
      settings = Settings.current
      @steps = @competitors.to_h { [it.id, Competitor::NextSteps.new(it, settings: settings, findings: findings, tracked: tracked)] }
    end

    def show
      @readings = @competitor.readings.to_a
      @steps = Competitor::NextSteps.new(@competitor)
      @search = SearchSnapshot.latest_by_site([@competitor.id]).fetch(@competitor.id, {}).transform_values { it.first&.data }
    end

    def new
      @competitor = Competitor.new(name: params[:name], website: params[:website])
    end

    def create
      existing = Competitor.matching(name: competitor_params[:name], website: competitor_params[:website])
      return redirect_to(market_competitor_path(existing), notice: "#{existing.name} is already watched") if existing

      @competitor = Competitor.new(competitor_params)
      if @competitor.save
        @competitor.check_later if @competitor.domain
        Finding.refresh_later
        redirect_to market_competitor_path(@competitor), notice: "#{@competitor.name} added; reading its website"
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      was = @competitor.domain
      if @competitor.update(competitor_params)
        @competitor.check_later if @competitor.domain && @competitor.domain != was
        Finding.refresh_later
        redirect_to market_competitor_path(@competitor), notice: "Saved"
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @competitor.destroy!
      Finding.refresh_later
      redirect_to market_competitors_path, notice: "#{@competitor.name} removed"
    end

    private

    def set_competitor = @competitor = Competitor.find(params[:competitor_id] || params[:id])
    def competitor_params = params.require(:competitor).permit(:name, :website, :kind, :threat, :strengths, :weaknesses, :notes)
  end
end
