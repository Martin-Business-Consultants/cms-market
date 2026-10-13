# frozen_string_literal: true

# The intake: a few answers about the business (name, website, ZIP, what it
# does), and what the AI filled in from its website and the CMS — the profile
# fields it set, and the competitors and searches it suggests checking.
class CreateMarketIntakes < ActiveRecord::Migration[8.1]
  def change
    create_table :market_intakes do |t|
      t.references :user
      t.string :state, null: false, default: "queued"
      t.text :answers
      t.text :summary
      t.text :filled
      t.text :competitor_suggestions
      t.text :keyword_suggestions
      t.text :to_check
      t.text :error
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
  end
end
