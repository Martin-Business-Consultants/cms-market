# frozen_string_literal: true

# Fetches DataForSEO's queued tasks that are done (Market::QueuedTask), and
# comes back in a few minutes while any are still waiting.
class Market::QueuedTasksJob < ApplicationJob
  def perform
    waiting = Market::QueuedTask.fetch_ready!
    self.class.set(wait: 3.minutes).perform_later if waiting.positive?
  end
end
