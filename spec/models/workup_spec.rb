# frozen_string_literal: true

require "rails_helper"
require_relative "../support/market_helpers"

RSpec.describe Market::Workup do
  let(:user) { create(:user) }
  let!(:keyword) { Market::Keyword.track("emergency plumber").first.first }
  let(:page) do
    Page.create!(slug: "plumbing", title: "Plumbing", status: "published", locale: "en", seo: {"meta_description" => "Old"},
      blocks: [{"id" => "b1", "type" => "text", "data" => {"body" => "We fix pipes."}}])
  end
  let(:workup) { described_class.create!(subject: "keyword:#{keyword.id}", user: user) }

  let(:answer) do
    {"summary" => "The page doesn't say emergency.",
     "changes" => [
       proposal("update_page", "Say emergency on the plumbing page", page_path: "/plumbing", meta_title: "Emergency plumber", meta_description: "Same day.",
         json_ld: '{"@type":"Plumber","name":"Acme"}', text_edits: [{"field" => "blocks.0.data.body", "text" => "We fix pipes, day or night."}, {"field" => "blocks.0.data.nope", "text" => "x"}]),
       proposal("update_page", "Change a page that isn't there", page_path: "/nowhere"),
       proposal("new_post", "Write about burst pipes", page_title: "What to do when a pipe bursts", slug: "burst-pipes", body_markdown: "Turn the water off."),
       proposal("new_page", "A page for Springfield", page_title: "Plumber in Springfield"),
       proposal("track_searches", "Track the night searches", searches: ["24 hour plumber"]),
       proposal("task", "Post on the Google Business Profile", channel: "local")
     ]}
  end

  def proposal(kind, title, **fields)
    {"kind" => kind, "title" => title, "why" => "Because", "page_path" => "", "page_title" => "", "meta_title" => "", "meta_description" => "",
     "focus_keyword" => "", "json_ld" => "", "text_edits" => [], "slug" => "", "body_markdown" => "", "searches" => [], "channel" => "seo"}.merge(fields.stringify_keys)
  end

  before do
    site_address
    switch_plugin :ai, on: true
    switch_plugin :approvals, on: true
    Ai::Settings.update("provider" => "opencode", "api_key" => "zen-key")
    BlockType.create!(slug: "text", label: "Text", fields: [{"name" => "body", "type" => "text", "label" => "Body"}])
    Collection.create!(slug: "posts", name: "Posts", schema: {"fields" => []})
    Market::Plan.create!(state: "ready", summary: "Rival owns the towns.", positioning: "Same day, every day.")
    Current.api_user = user
    page
  end

  it "is drafted by the AI from the facts, the plan and the site's pages, dropping what couldn't be sent" do
    asked = nil
    allow(Ai).to receive(:structured) { |**request| asked = request; answer }
    workup.run!

    expect(asked[:prompt]).to include("emergency plumber", "Same day, every day.", "/plumbing — Plumbing", "meta description: Old")
    expect(workup.reload).to have_attributes(state: "ready", summary: "The page doesn't say emergency.")
    expect(workup.changes.map { it["title"] }).not_to include("Change a page that isn't there")
    expect(workup.changes.first["text_edits"]).to eq([{"field" => "blocks.0.data.body", "text" => "We fix pipes, day or night."}])
    expect(workup.changes.first["json_ld"]).to eq({"@type" => "Plumber", "name" => "Acme"})
  end

  it "sends page changes and posts to Approvals, never live, and the rest where they go" do
    allow(Ai).to receive(:structured).and_return(answer)
    workup.run!

    update = workup.send_change!(0, by: user)
    expect(update).to include("kind" => "update_page", "approval_id" => Integer)
    expect(page.reload).to have_attributes(title: "Plumbing", seo: {"meta_description" => "Old"})
    held = Approvals::Change.find(update["approval_id"])
    expect(held.payload["seo"]).to include("meta_title" => "Emergency plumber", "meta_description" => "Same day.", "json_ld" => {"@type" => "Plumber", "name" => "Acme"})
    expect(held.payload.dig("blocks", 0, "data", "body")).to eq("We fix pipes, day or night.")

    expect(workup.send_change!(1, by: user)).to include("approval_id" => Integer)
    expect(Approvals::Change.last).to have_attributes(action: "create", subject_type: "CollectionEntry")
    expect(Collection.find_by!(slug: "posts").entries.count).to eq(0)

    expect(workup.send_change!(2, by: user)["page_path"]).to eq("plumber-in-springfield")
    expect(Page.find_by!(slug: "plumber-in-springfield").status).to eq("draft")
    expect(workup.send_change!(3, by: user)["keywords"]).to eq(["24 hour plumber"])
    expect(Market::Opportunity.find(workup.send_change!(4, by: user)["opportunity_id"]).title).to eq("Post on the Google Business Profile")

    expect { workup.send_change!(0, by: user) }.not_to change(Approvals::Change, :count)
  end

  it "refuses page changes while nothing holds them for a person" do
    allow(Ai).to receive(:structured).and_return(answer)
    workup.run!
    switch_plugin :approvals, on: false

    expect { workup.send_change!(0, by: user) }.to raise_error(described_class::Refused, /Approvals/)
  end

  it "keeps why it failed" do
    allow(Ai).to receive(:structured).and_raise(Ai::Error, "OpenCode Zen is rate limiting this key")
    workup.run!
    expect(workup.reload).to have_attributes(state: "failed", error: "OpenCode Zen is rate limiting this key")
  end

  it "only takes subjects it knows" do
    expect(described_class.new(subject: "keyword:1; drop")).not_to be_valid
    expect { Market::Workup::Brief.new("page:1") }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
