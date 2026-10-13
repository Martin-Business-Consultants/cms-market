# frozen_string_literal: true

# Works the findings out again, after something they're drawn from changed.
class Market::FindingsJob < ApplicationJob
  def perform = Market::Finding.refresh
end
