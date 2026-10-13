# frozen_string_literal: true

module Market
  # AI work-ups (Market::Workup): one subject's facts and its latest work-up
  # (show), and a new one drafted (create). Search opens them in a sheet; an
  # opportunity's opens here.
  class WorkupsController < ApplicationController
    requires_capability "market:read", only: :show
    requires_capability "market:write", only: :create

    def show
      @subject = params.require(:subject)
      @brief = Workup::Brief.new(@subject)
      @workup = Workup.latest(@subject)
    rescue ActiveRecord::RecordNotFound
      redirect_to market_overview_path, alert: "That's gone"
    end

    def create
      subject = params.require(:subject)
      back = back_or(market_work_path(subject: subject))
      return redirect_to(back, alert: Plan.ai_unavailable_reason) unless Plan.ai_available?

      Workup::Brief.new(subject)
      Workup.latest(subject)&.then { return redirect_to(back) if it.working? }
      Workup.start(subject, user: Current.user)
      redirect_to back, notice: "Working it out: a minute or so"
    rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid
      redirect_to market_overview_path, alert: "That's gone"
    end
  end
end
