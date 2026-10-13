# frozen_string_literal: true

module Market
  # The business's market profile (Market::Profile).
  class ProfilesController < ApplicationController
    requires_capability "market:write", only: [:edit, :update]

    def edit
      @profile = Profile.current
    end

    def update
      Profile.update(params.require(:profile).permit(*Profile::FIELDS))
      Finding.refresh_later
      redirect_to market_overview_path, notice: "Profile saved"
    end
  end
end
