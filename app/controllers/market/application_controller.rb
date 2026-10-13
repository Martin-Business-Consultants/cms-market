# frozen_string_literal: true

module Market
  # The plugin's admin pages: a 404 while it's off, in the core's layout.
  class ApplicationController < ::ApplicationController
    include PluginGated
    plugin :market

    helper Market::MarketHelper
  end
end
