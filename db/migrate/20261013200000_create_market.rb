# frozen_string_literal: true

# Market's tables. The business itself is the site (its profile is in the
# core's Setting "market"): a reading, a search snapshot or a ranking with no
# competitor is the site's own.
class CreateMarket < ActiveRecord::Migration[8.1]
  def change
    create_table :market_competitors do |t|
      t.string :name, null: false
      t.string :website
      t.string :domain, index: {unique: true}
      t.string :kind, null: false, default: "direct"
      t.string :threat, null: false, default: "medium"
      t.text :strengths
      t.text :weaknesses
      t.text :notes
      t.timestamps
    end

    # A website read from outside (Market::Probe), and what changed since.
    create_table :market_readings do |t|
      t.references :competitor, foreign_key: {to_table: :market_competitors, on_delete: :cascade}
      t.string :domain, null: false
      t.text :facts
      t.text :differences
      t.text :error
      t.datetime :taken_at, null: false
      t.timestamps
      t.index [:competitor_id, :taken_at]
    end

    create_table :market_search_pulls do |t|
      t.references :user
      t.string :state, null: false, default: "queued"
      t.boolean :force, null: false, default: false
      t.decimal :cost, precision: 12, scale: 4, null: false, default: 0
      t.text :notes
      t.text :error
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    # Every call to DataForSEO, whatever came of it: the month's budget is
    # checked against these.
    create_table :market_search_requests do |t|
      t.references :pull, foreign_key: {to_table: :market_search_pulls, on_delete: :nullify}
      t.string :endpoint, null: false
      t.string :target
      t.integer :status_code
      t.string :status_message
      t.decimal :cost, precision: 12, scale: 4, null: false, default: 0
      t.integer :attempts, null: false, default: 1
      t.integer :duration_ms
      t.text :error
      t.datetime :created_at, null: false
      t.index :created_at
    end

    create_table :market_search_snapshots do |t|
      t.references :competitor, foreign_key: {to_table: :market_competitors, on_delete: :cascade}
      t.references :pull, foreign_key: {to_table: :market_search_pulls, on_delete: :nullify}
      t.string :domain, null: false
      t.string :kind, null: false
      t.string :location
      t.text :data
      t.datetime :taken_at, null: false
      t.timestamps
      t.index [:competitor_id, :kind, :taken_at]
    end

    create_table :market_keywords do |t|
      t.string :keyword, null: false, index: {unique: true}
      t.string :source, null: false, default: "manual"
      t.timestamps
    end

    create_table :market_rankings do |t|
      t.references :keyword, null: false, foreign_key: {to_table: :market_keywords, on_delete: :cascade}
      t.references :pull, foreign_key: {to_table: :market_search_pulls, on_delete: :nullify}
      t.string :location, null: false
      t.integer :position
      t.string :url
      t.text :results
      t.text :features
      t.datetime :checked_at, null: false
      t.timestamps
      t.index [:keyword_id, :checked_at]
    end

    # What the data says (Market::Finding::Analysis), one row per stable key.
    create_table :market_findings do |t|
      t.string :key, null: false, index: {unique: true}
      t.string :kind, null: false
      t.string :severity, null: false
      t.string :channel
      t.string :title, null: false
      t.text :detail
      t.text :evidence
      t.text :sources
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :changed_at, null: false, index: true
      t.datetime :resolved_at
      t.datetime :dismissed_at
      t.string :dismissed_by_name
      t.timestamps
    end

    create_table :market_plans do |t|
      t.references :user
      t.string :state, null: false, default: "queued"
      t.text :summary
      t.text :positioning
      t.text :industry_suggestion
      t.text :competitor_suggestions
      t.text :keyword_suggestions
      t.text :error
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    create_table :market_opportunities do |t|
      t.references :plan, foreign_key: {to_table: :market_plans, on_delete: :nullify}
      t.string :channel, null: false
      t.string :title, null: false
      t.text :detail
      t.text :evidence
      t.string :impact, null: false, default: "medium"
      t.string :effort, null: false, default: "medium"
      t.string :horizon, null: false, default: "next"
      t.string :state, null: false, default: "open"
      t.references :page
      t.string :decided_by_name
      t.datetime :decided_at
      t.timestamps
    end
  end
end
