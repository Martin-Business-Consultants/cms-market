# frozen_string_literal: true

module Market
  module Api
    # The plugin's API (/api/market…, listed in /api/manifest): a 404 while
    # it's off, every action declaring its capability.
    class BaseController < ::Api::BaseController
      include PluginGated
      plugin :market
      enforce_authorization

      helper Market::MarketHelper

      private

      def refuse(message, status: :conflict) = render(json: {error: "refused", message: message}, status: status)
    end
  end
end
