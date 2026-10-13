# frozen_string_literal: true

module Market
  # Reads the site itself from outside now, as competitors are read.
  class SiteChecksController < ApplicationController
    requires_capability "market:write", only: :create

    def create
      return redirect_to(market_competitors_path, alert: "Set the site's address in Settings › General first") unless Profile.current.domain

      CheckJob.perform_later
      redirect_to market_competitors_path, notice: "Reading #{Profile.current.domain}: refresh in a few seconds"
    end
  end
end
