# frozen_string_literal: true

# Reads one website off the request (a competitor's, or the site's own for
# nil), then works out the findings again.
class Market::CheckJob < ApplicationJob
  def perform(competitor = nil)
    competitor ? competitor.check_now : Market::Reading.take
    Market::Finding.refresh
  end
end
