# frozen_string_literal: true

# Local search: one tracked search checked on Google Maps from every point of
# a grid across the profile's ZIP and radius — where the business showed at
# each, who led, and the figures across the area.
class CreateMarketLocalScans < ActiveRecord::Migration[8.1]
  def change
    create_table :market_local_scans do |t|
      t.references :keyword, null: false, foreign_key: {to_table: :market_keywords, on_delete: :cascade}
      t.references :pull, foreign_key: {to_table: :market_search_pulls, on_delete: :nullify}
      t.string :zip
      t.float :center_lat, null: false
      t.float :center_lng, null: false
      t.float :radius_miles, null: false
      t.integer :grid, null: false
      t.text :points
      t.text :leaders
      t.float :average_position
      t.float :top3_share
      t.integer :found_points, null: false, default: 0
      t.datetime :checked_at, null: false
      t.timestamps
      t.index [:keyword_id, :checked_at]
    end
  end
end
