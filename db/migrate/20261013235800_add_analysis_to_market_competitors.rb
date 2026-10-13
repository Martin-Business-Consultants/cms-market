# frozen_string_literal: true

# A competitor sized up by the AI: what it does well and badly, how much of a
# threat it is and why, and the moves that would beat it.
class AddAnalysisToMarketCompetitors < ActiveRecord::Migration[8.1]
  def change
    add_column :market_competitors, :analysis, :text
    add_column :market_competitors, :analysis_state, :string
    add_column :market_competitors, :analysis_error, :text
    add_column :market_competitors, :analysed_at, :datetime
  end
end
