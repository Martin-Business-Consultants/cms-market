# frozen_string_literal: true

module Market
  module Api
    # GET|PATCH /api/market/settings (secrets are never read back).
    class SettingsController < BaseController
      requires_capability "settings:read", only: :show
      requires_capability "settings:write", only: :update

      def show
        render json: Settings.current.to_h
      end

      def update
        settings = Settings.update(params.require(:settings).permit(:dataforseo_login, :dataforseo_password, :remove_dataforseo_password,
          :monthly_budget_dollars, :monthly_budget_cents, :country, :language_code, :refresh, :keyword_limit, :backlinks, :sandbox, ai_platforms: [], extras: []))
        Event.record("settings.market_updated")
        render json: settings.to_h
      end
    end
  end
end
