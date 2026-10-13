# frozen_string_literal: true

# Sizes up a competitor off the request (Market::Competitor::Assessable#assess!).
class Market::AssessmentJob < ApplicationJob
  def perform(competitor) = competitor.assess!
end
