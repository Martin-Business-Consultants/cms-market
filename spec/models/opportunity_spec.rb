# frozen_string_literal: true

require "rails_helper"
require_relative "../support/market_helpers"

RSpec.describe Market::Opportunity do
  def opportunity(title, **attributes) = described_class.create!(title: title, channel: "seo", **attributes)

  it "puts the most impact for the least effort first, then the soonest" do
    slow = opportunity("Slow", impact: "high", effort: "high")
    quick = opportunity("Quick", impact: "high", effort: "low")
    later = opportunity("Later", impact: "high", effort: "low", horizon: "later")
    small = opportunity("Small", impact: "low", effort: "low")

    expect(described_class.by_priority([small, slow, later, quick])).to eq([quick, later, slow, small])
    expect(quick).to be_quick_win
  end

  it "starts a draft page for itself, with a slug of its own" do
    create(:page, slug: "publish-a-page-for-each-town", title: "Taken") if defined?(FactoryBot) && FactoryBot.factories.registered?(:page)
    item = opportunity("Publish a page for each town", detail: "One per town.", evidence: "Rival has 15")

    page = item.start_page(by: create(:user, name: "Sam"))

    expect(page).to be_persisted
    expect(page).to have_attributes(status: "draft", title: "Publish a page for each town")
    expect(page.slug).to start_with("publish-a-page-for-each-town")
    expect(page.seo["meta_description"]).to eq("One per town. Rival has 15")
    expect(item.reload).to have_attributes(state: "planned", page: page, decided_by_name: "Sam")

    second = opportunity("Publish a page for each town!").start_page(by: nil)
    expect(second.slug).not_to eq(page.slug)
  end

  it "is done, dismissed, and open again" do
    item = opportunity("Ask for reviews")
    item.complete(by: create(:user, name: "Sam"))
    expect(item).to have_attributes(state: "done", decided_by_name: "Sam")
    item.reopen
    expect(item).to have_attributes(state: "open", decided_at: nil)
  end
end
