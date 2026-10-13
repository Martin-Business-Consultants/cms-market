# frozen_string_literal: true

module Market
  # The plugin's admin pages: a 404 while it's off, in the core's layout.
  class ApplicationController < ::ApplicationController
    include PluginGated
    plugin :market

    helper Market::MarketHelper, Market::ChartHelper

    private

    # Where to go back to after an action taken from another screen (the overview's tabs): a path
    # on this site, else the default.
    def back_or(default)
      url = params[:return_to].to_s
      (url.start_with?("/") && !url.start_with?("//")) ? url : default
    end
  end
end
