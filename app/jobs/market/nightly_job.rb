# frozen_string_literal: true

# The nightly run: websites not read this week are read again (one job each,
# so a slow site holds up nothing else), the site's search data is pulled
# when Settings › Market's refresh says it's due (within the month's budget,
# which each call checks), and the findings are worked out again, so the
# age-based ones (stale data, recent site changes) come and go on their own.
class Market::NightlyJob < ApplicationJob
  def perform
    return unless Cms::Plugins.enabled?(:market)

    read_due_websites
    pull_if_due
    Market::FindingsJob.perform_later
  end

  private

  def read_due_websites
    competitors = Market::Competitor.watchable.to_a
    latest = Market::Reading.latest_for(competitors)
    competitors.each { |competitor| Market::CheckJob.perform_later(competitor) if latest[competitor.id].nil? || latest[competitor.id].taken_at < Market::Competitor::CHECK_EVERY.ago }
    own = Market::Reading.own_latest
    Market::CheckJob.perform_later if Market::Profile.current.domain && (own.nil? || own.taken_at < Market::Competitor::CHECK_EVERY.ago)
  end

  def pull_if_due
    settings = Market::Settings.current
    every = settings.refresh_every
    return unless every && settings.search_connected? && settings.remaining_budget.positive? && Market::Profile.current.domain

    last = Market::SearchPull.where(state: %w[ready partial queued running]).maximum(:created_at)
    Market::SearchPull.create!.run_later if last.nil? || last <= every.ago + 1.hour
  end
end
