# frozen_string_literal: true

# AI search: each tracked search asked of an AI (Google's AI Overview and AI
# Mode, ChatGPT, Gemini, Perplexity, Claude) at one pull: whether it answered,
# whether it named the business and cited its site, who else it named, and
# what it cited. And, for Google's own results, the map pack and the
# questions people also ask.
class CreateMarketAiChecks < ActiveRecord::Migration[8.1]
  def change
    create_table :market_ai_checks do |t|
      t.references :keyword, null: false, foreign_key: {to_table: :market_keywords, on_delete: :cascade}
      t.references :pull, foreign_key: {to_table: :market_search_pulls, on_delete: :nullify}
      t.string :platform, null: false
      t.string :model
      t.string :prompt
      t.boolean :answered, null: false, default: false
      t.boolean :mentioned, null: false, default: false
      t.boolean :cited, null: false, default: false
      t.integer :mention_rank
      t.text :named
      t.text :sources
      t.text :answer
      t.text :error
      t.datetime :checked_at, null: false
      t.timestamps
    end
    add_index :market_ai_checks, [:keyword_id, :platform, :checked_at]

    add_column :market_rankings, :local_pack, :text
    add_column :market_rankings, :questions, :text
  end
end
