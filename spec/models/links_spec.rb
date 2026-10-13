# frozen_string_literal: true

require "rails_helper"
require_relative "../support/market_helpers"

RSpec.describe "Market links" do
  before do
    site_address
    connect_search
  end

  describe Market::Search::Api do
    def api(*answers)
      @transport = MarketHelpers::FakeTransport.new(*answers.map { [200, it] })
      described_class.new(client: Market::Search::Client.new(transport: @transport))
    end

    def sent = @transport.calls.last[2].first

    it "reads a site's link profile, out of 100, with where its links come from" do
      result = {"rank" => 41, "backlinks" => 1200, "referring_domains" => 90, "referring_domains_nofollow" => 18, "broken_backlinks" => 7, "first_seen" => "2019-03-02 10:00:00 +00:00",
                "info" => {"target_spam_score" => 3}, "referring_links_tld" => {"com" => 60, "org" => 12, "io" => 0}, "referring_links_countries" => {"" => 4, "US" => 70}}
      profile = api(dataforseo([result])).backlinks("acme.example")

      expect(sent).to include(target: "acme.example", rank_scale: "one_hundred")
      expect(profile).to include("rank" => 41, "referring_domains" => 90, "referring_domains_nofollow" => 18, "broken_backlinks" => 7, "first_seen" => "2019-03-02",
        "spam_score" => 3, "tlds" => {"com" => 60, "org" => 12}, "countries" => {"US" => 70})
    end

    it "lists who links in, best first, and whether their links are followed" do
      items = [{"domain" => "news.example", "rank" => 60, "backlinks" => 4, "referring_links_attributes" => {"nofollow" => 4}, "backlinks_spam_score" => 2, "first_seen" => "2026-09-01 00:00:00 +00:00"},
        {"domain" => "chamber.example", "rank" => 50, "backlinks" => 2, "referring_links_attributes" => {"nofollow" => 1}}]
      found = api(dataforseo([{"total_count" => 2, "items" => items}])).referring_domains("acme.example")

      expect(sent).to include(order_by: ["rank,desc"], limit: 100)
      expect(found["sites"]).to eq([{"domain" => "news.example", "rank" => 60, "links" => 4, "follow" => false, "spam" => 2, "first_seen" => "2026-09-01"},
        {"domain" => "chamber.example", "rank" => 50, "links" => 2, "follow" => true, "spam" => 0}])
    end

    it "splits the last 90 days into links won and lost, and groups links to missing pages by the page" do
      items = [{"domain_from" => "news.example", "url_from" => "https://news.example/a", "url_to" => "https://acme.example/", "domain_from_rank" => 60, "dofollow" => true, "is_lost" => false, "first_seen" => 5.days.ago.iso8601},
        {"domain_from" => "old.example", "url_from" => "https://old.example/b", "url_to" => "https://acme.example/", "domain_from_rank" => 40, "dofollow" => true, "is_lost" => true, "last_seen" => 10.days.ago.iso8601},
        {"domain_from" => "ancient.example", "url_from" => "https://ancient.example/c", "url_to" => "https://acme.example/", "domain_from_rank" => 40, "is_lost" => true, "last_seen" => 2.years.ago.iso8601}]
      changes = api(dataforseo([{"items" => items}])).link_changes("acme.example")
      expect(sent).to include(mode: "one_per_domain", backlinks_status_type: "all")
      expect(sent[:filters][1]).to eq("or")
      expect(changes).to include("won_count" => 1, "lost_count" => 1)
      expect(changes["lost"].first).to include("domain" => "old.example", "follow" => true, "lost" => true)

      broken = [{"domain_from" => "a.example", "url_to" => "https://acme.example/old?x=1", "url_to_status_code" => 404, "domain_from_rank" => 30},
        {"domain_from" => "b.example", "url_to" => "https://acme.example/old?x=1", "url_to_status_code" => 404, "domain_from_rank" => 50},
        {"domain_from" => "c.example", "url_to" => "https://acme.example/gone", "url_to_status_code" => 410, "domain_from_rank" => 10}]
      pages = api(dataforseo([{"total_count" => 3, "items" => broken}])).broken_links("acme.example")["pages"]
      expect(sent[:filters]).to eq([["is_broken", "=", true]])
      expect(pages.first).to include("path" => "/old", "status" => 404, "sites" => 2, "best_rank" => 50)
      expect(pages.last).to include("path" => "/gone", "sites" => 1)
    end

    it "reads anchors, most-linked pages and sites with links like the site's" do
      anchors = api(dataforseo([{"total_count" => 1, "items" => [{"anchor" => " Acme Plumbing ", "referring_domains" => 5, "backlinks" => 9}]}])).anchors("acme.example")
      expect(anchors["anchors"]).to eq([{"anchor" => "Acme Plumbing", "sites" => 5, "links" => 9}])

      pages = api(dataforseo([{"items" => [{"url" => "https://rival.example/guide", "referring_domains" => 30, "backlinks" => 80, "rank" => 20}]}])).linked_pages("rival.example")
      expect(pages["pages"]).to eq([{"url" => "https://rival.example/guide", "sites" => 30, "links" => 80, "rank" => 20}])

      rivals = api(dataforseo([{"items" => [{"target" => "www.acme.example", "intersections" => 99}, {"target" => "drainkings.example", "rank" => 22, "intersections" => 14}]}])).link_competitors("acme.example")
      expect(rivals["sites"]).to eq([{"domain" => "drainkings.example", "rank" => 22, "shared" => 14}])
    end
  end

  describe "a pull with Backlinks, and what it says" do
    let!(:rival) { Market::Competitor.create!(name: "Rival", website: "https://rival.example") }

    before do
      Market::Settings.update("backlinks" => "1", "ai_platforms" => [], "extras" => [], "queue" => "0")
      Market::Keyword.track("emergency plumber")
    end

    it "pulls each site's links, the detail on the site's own weekly, and finds what to do about them" do
      fake = MarketHelpers::FakeApi.new
      Market::SearchPull.create!.run!(api: fake)
      expect(fake.calls).to include("backlinks:acme.example", "backlink_history:acme.example", "linked_pages:acme.example", "referring_domains:acme.example",
        "link_changes:acme.example", "broken_links:acme.example", "anchors:acme.example", "link_competitors:acme.example", "backlinks:rival.example",
        "linked_pages:rival.example", "link_gap")
      expect(fake.calls).not_to include("referring_domains:rival.example", "anchors:rival.example")

      travel 2.days do
        again = MarketHelpers::FakeApi.new
        Market::SearchPull.create!.run!(api: again)
        expect(again.calls).to include("backlinks:acme.example")
        expect(again.calls).not_to include("referring_domains:acme.example", "linked_pages:rival.example")
      end

      kinds = Market::Finding.pluck(:kind)
      expect(kinds).to include("links_broken", "links_lost", "links_pace", "anchors_keyword", "links_spammy", "link_gap", "linkable_pages", "backlinks_gap")
      broken = Market::Finding.find_by!(kind: "links_broken")
      expect(broken).to have_attributes(severity: "high", title: "3 sites link to 1 page on Acme Plumbing that no longer exists")
      expect(broken.related).to eq([:search, "links"])

      links = Market::Links.new
      expect(links.anchor_mix).to eq("keyword" => 57, "brand" => 21, "generic" => 14, "url" => 7)
      expect(links.link_rivals.map { it["domain"] }).to eq(["drainkings.example"])
      expect(links.facts).to include("Links to pages that no longer answer: /old-services (404, 3 sites)", "Lost in 90 days (worth winning back): chamber.example")

      Redirect.create!(source_path: "/old-services", destination_url: "/services", status_code: 301)
      Market::Finding.refresh
      expect(Market::Links.new.broken.first["redirect"]).to eq("/services")
      expect(Market::Finding.open.pluck(:kind)).not_to include("links_broken")

      expect(Market::Goal.create!(metric: "linking_sites", target: 40).current).to eq(10)
      expect(Market::Workup::Brief.new("links:own").to_s).to include("Win links", "springfieldnews.example")
    end
  end
end
