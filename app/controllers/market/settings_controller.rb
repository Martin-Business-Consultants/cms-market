# frozen_string_literal: true

module Market
  # Settings › Market (Market::Settings).
  class SettingsController < ::Settings::BaseController
    include PluginGated
    plugin :market

    requires_capability "settings:read", only: :show
    requires_capability "settings:write", only: :update

    def show
      @settings = Settings.current
      @requests = SearchRequest.latest_first.limit(25).to_a
    end

    def update
      Settings.update(params.require(:market).permit(:dataforseo_login, :dataforseo_password, :remove_dataforseo_password, :monthly_budget_dollars,
        :country, :language_code, :refresh, :keyword_limit, :backlinks, :sandbox, ai_platforms: [], extras: []))
      Event.record("settings.market_updated")
      redirect_to settings_market_path, notice: "Saved"
    end
  end
end
