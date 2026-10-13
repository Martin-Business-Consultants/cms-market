# frozen_string_literal: true

# Content work drafted by the AI for one thing on the Market screens (a
# tracked search, the map for one, a site's visibility, an opportunity):
# changes to the site's pages, new posts, searches to track, and what's been
# sent on (to Approvals, or done here) of each.
class CreateMarketWorkups < ActiveRecord::Migration[8.1]
  def change
    create_table :market_workups do |t|
      t.string :subject, null: false
      t.string :state, null: false, default: "queued"
      t.text :answer
      t.text :sent
      t.text :error
      t.references :user, foreign_key: {on_delete: :nullify}
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :market_workups, [:subject, :id]
  end
end
