# frozen_string_literal: true

module Market
  module Api
    # GET|POST /api/market/intake: the starting point.
    class IntakesController < BaseController
      requires_capability "market:read", only: :show
      requires_capability "market:write", only: :create

      def show
        @intake = Intake.latest_first.first or return render(json: {error: "not_found", message: "No intake yet: POST /api/market/intake"}, status: :not_found)
        @profile = Profile.current
      end

      def create
        return refuse("The AI is already filling in the profile") if Intake.working?

        @intake = Intake.start(params.require(:intake).permit(:business_name, :website, :local_zip, :about), user: Current.user)
        @profile = Profile.current
        render :show, status: @intake.failed? ? :ok : :accepted
      end
    end
  end
end
