# frozen_string_literal: true

# Pulls the site's search data off the request (Market::SearchPull#run!): a minute or two.
class Market::SearchPullJob < ApplicationJob
  def perform(pull) = pull.run!
end
