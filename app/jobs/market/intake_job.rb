# frozen_string_literal: true

# Fills in the profile off the request (Market::Intake#run!): reading the site and asking the AI take a minute or two.
class Market::IntakeJob < ApplicationJob
  def perform(intake) = intake.run!
end
