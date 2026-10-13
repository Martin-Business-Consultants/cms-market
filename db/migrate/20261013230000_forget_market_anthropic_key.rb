# frozen_string_literal: true

# Plans are drafted by the AI plugin now: Market keeps no AI key or model of
# its own, so any it saved before goes.
class ForgetMarketAnthropicKey < ActiveRecord::Migration[8.1]
  def up
    return unless defined?(::Setting) && ::Setting.exists?(key: "market")

    ::Setting.set_secret("market", "anthropic_api_key" => "")
    ::Setting.unset("market", "ai_model")
  end

  def down
  end
end
