# frozen_string_literal: true

# Drafts a plan off the request (Market::Plan#run!): the AI takes a minute or two.
class Market::PlanJob < ApplicationJob
  def perform(plan) = plan.run!
end
