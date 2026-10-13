# frozen_string_literal: true

# What the business wants from its marketing, measurably: a metric Market can
# read (calls from Google, a search's place on Maps, being named by AI…), where
# it stood when the goal was set, the target, and by when. Opportunities serve
# one.
class CreateMarketGoals < ActiveRecord::Migration[8.1]
  def change
    create_table :market_goals do |t|
      t.string :metric, null: false
      t.references :keyword, foreign_key: {to_table: :market_keywords, on_delete: :nullify}
      t.decimal :target, precision: 12, scale: 2, null: false
      t.decimal :baseline, precision: 12, scale: 2
      t.date :due_on
      t.string :state, null: false, default: "active"
      t.text :why
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_reference :market_opportunities, :goal, foreign_key: {to_table: :market_goals, on_delete: :nullify}
  end
end
