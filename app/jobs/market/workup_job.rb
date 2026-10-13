# frozen_string_literal: true

# Drafts a work-up off the request (Market::Workup#run!).
class Market::WorkupJob < ApplicationJob
  def perform(workup) = workup.run!
end
