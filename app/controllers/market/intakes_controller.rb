# frozen_string_literal: true

module Market
  # The starting point: a few answers, then the AI fills in what it can.
  class IntakesController < ApplicationController
    requires_capability "market:read", only: :show
    requires_capability "market:write", only: [:new, :create]

    def new
      @profile = Profile.current
    end

    def create
      return redirect_to(market_intake_path, alert: "The AI is already filling in the profile") if Intake.working?

      intake = Intake.start(params.require(:intake).permit(:business_name, :website, :local_zip, :about), user: Current.user)
      if intake.failed?
        redirect_to edit_market_profile_path, alert: "Saved. #{intake.error}: fill in the rest here."
      else
        redirect_to market_intake_path, notice: "Saved. The AI is reading the site and filling in the rest"
      end
    end

    def show
      @intake = Intake.latest_first.first or return redirect_to(new_market_intake_path)
      @profile = Profile.current
    end
  end
end
