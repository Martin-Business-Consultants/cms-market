# frozen_string_literal: true

module Market
  # Checks the DataForSEO login by asking for the balance (which costs nothing).
  class SettingsChecksController < ::Settings::BaseController
    include PluginGated
    plugin :market

    requires_capability "settings:write", only: :create

    def create
      balance = Market::Settings.check!
      redirect_to settings_market_path, notice: "Connected to DataForSEO: $#{format("%.2f", balance)} on the account"
    rescue Market::Search::Client::Error => error
      Market::Settings.note_error(error.message)
      redirect_to settings_market_path, alert: error.message
    end
  end
end
