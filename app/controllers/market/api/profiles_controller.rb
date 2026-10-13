# frozen_string_literal: true

module Market
  module Api
    # GET|PATCH /api/market/profile
    class ProfilesController < BaseController
      requires_capability "market:read", only: :show
      requires_capability "market:write", only: :update

      def show
        @profile = Profile.current
      end

      def update
        @profile = Profile.update(params.require(:profile).permit(*Profile::FIELDS, *Profile::LOCAL_FIELDS, *Profile::IDENTITY_FIELDS))
        Finding.refresh_later
        render :show
      end
    end
  end
end
