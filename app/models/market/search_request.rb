# frozen_string_literal: true

# One call to DataForSEO, whatever came of it: the ledger the month's budget
# is checked against, and the history Settings › Market shows.
class Market::SearchRequest < ApplicationRecord
  belongs_to :pull, class_name: "Market::SearchPull", optional: true

  scope :latest_first, -> { order(created_at: :desc, id: :desc) }

  def ok? = status_code == 20000 && error.blank?
end
