# frozen_string_literal: true

# Work DataForSEO does in its queue rather than at once (Google reviews):
# the task set at a pull, fetched when it's done (Market::QueuedTask).
class CreateMarketQueuedTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :market_queued_tasks do |t|
      t.string :kind, null: false
      t.references :competitor, foreign_key: {to_table: :market_competitors, on_delete: :cascade}
      t.references :pull, foreign_key: {to_table: :market_search_pulls, on_delete: :nullify}
      t.string :domain
      t.string :endpoint, null: false
      t.string :task_id, null: false
      t.string :state, null: false, default: "queued"
      t.integer :attempts, null: false, default: 0
      t.text :error
      t.datetime :posted_at, null: false
      t.datetime :finished_at
      t.timestamps
    end
    add_index :market_queued_tasks, :state
  end
end
