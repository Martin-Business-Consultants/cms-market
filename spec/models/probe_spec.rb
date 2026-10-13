# frozen_string_literal: true

require "rails_helper"
require_relative "../support/market_helpers"

RSpec.describe Market::Probe do
  html = <<~HTML
    <html><head><title> Rival Plumbing |  Emergency &amp; drains </title>
    <meta name="description" content="24/7 plumbers in Springfield.">
    <meta name="generator" content="WordPress 6.6">
    <script async src="https://www.googletagmanager.com/gtag/js?id=AW-123456789"></script>
    <script>fbq('init', '123');</script>
    <script src="https://cdn.callrail.com/swap.js"></script>
    <script type="application/ld+json">{"@context":"https://schema.org","@graph":[{"@type":"Plumber"},{"@type":"WebSite"}]}</script>
    </head><body><h1>Plumbers <em>you</em> can trust</h1>
    <a href="tel:+1 (555) 010-0100">Call</a><a href="tel:5550100100">Call</a>
    <a href="https://www.facebook.com/rivalplumbing">Facebook</a><a href="https://www.facebook.com/sharer/sharer.php">Share</a>
    <a href="https://instagram.com/rival">Instagram</a>
    <form action="/contact"></form></body></html>
  HTML

  it "takes a domain without its scheme, path or www" do
    expect(described_class.normalize("https://www.Example.com/about")).to eq("example.com")
    expect(described_class.normalize("example.com")).to eq("example.com")
    expect(described_class.normalize(" ")).to be_nil
  end

  it "reads what a home page runs and how it presents itself" do
    home = described_class.new("rival.example").read_home(html)

    expect(home).to include("title" => "Rival Plumbing | Emergency & drains", "description" => "24/7 plumbers in Springfield.",
      "headings" => ["Plumbers you can trust"], "platform" => "WordPress 6.6", "tools" => %w[google_ads meta_pixel call_tracking],
      "schema_types" => %w[Plumber WebSite], "phone_numbers" => ["15550100100"], "forms" => 1)
    expect(home["socials"]).to eq("facebook" => "https://www.facebook.com/rivalplumbing", "instagram" => "https://instagram.com/rival")
  end

  it "counts a sitemap's pages, posts, locations and services, and how fresh they are" do
    today = Date.new(2026, 10, 13)
    entries = [["https://rival.example/", today - 2], ["https://rival.example/blog/winter-pipes", today - 10], ["https://rival.example/blog/old", today - 400],
      ["https://rival.example/locations/springfield", nil], ["https://rival.example/services/drains", nil]]

    expect(described_class.new("rival.example", today: today).read_sitemap(entries, url: "https://rival.example/sitemap.xml"))
      .to include("pages" => 5, "posts" => 2, "posts_last_90_days" => 1, "locations" => 1, "services" => 1, "last_changed" => "2026-10-11")
  end
end
