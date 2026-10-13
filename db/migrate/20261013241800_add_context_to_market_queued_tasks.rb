# frozen_string_literal: true

# Queued tasks now carry most of a pull (Standard: Google's results, Maps
# points, AI answers, Business Profile posts, other review sites): the tracked
# search each is for, and what else it needs to be put to use (`meta`: the
# platform, a Maps point, the result once it's in).
class AddContextToMarketQueuedTasks < ActiveRecord::Migration[8.1]
  def change
    add_reference :market_queued_tasks, :keyword, foreign_key: {to_table: :market_keywords, on_delete: :cascade}
    add_column :market_queued_tasks, :meta, :text
    add_index :market_queued_tasks, [:pull_id, :kind]
  end
end
