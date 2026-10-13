# frozen_string_literal: true

# An opportunity made from a finding remembers which, so the finding shows it's planned.
class AddFindingKeyToMarketOpportunities < ActiveRecord::Migration[8.1]
  def change
    add_column :market_opportunities, :finding_key, :string
    add_index :market_opportunities, :finding_key
  end
end
