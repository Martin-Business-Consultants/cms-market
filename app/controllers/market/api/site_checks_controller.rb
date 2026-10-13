# frozen_string_literal: true

module Market
  module Api
    # POST /api/market/site_check: reads the site itself from outside, in the background.
    class SiteChecksController < BaseController
      requires_capability "market:write", only: :create

      def create
        domain = Profile.current.domain or return refuse("The site has no address: set it in Settings › General")

        CheckJob.perform_later
        render json: {status: "queued", message: "Reading #{domain}: it shows as own_website on /api/market/competitors in a few seconds."}, status: :accepted
      end
    end
  end
end
