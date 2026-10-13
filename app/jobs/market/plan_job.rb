# frozen_string_literal: true

# Drafts a plan off the request (Market::Plan#run!): Claude takes a minute or two.
class Market::PlanJob < ApplicationJob
  def perform(plan) = plan.run!
end
