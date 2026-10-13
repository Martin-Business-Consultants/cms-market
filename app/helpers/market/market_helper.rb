# frozen_string_literal: true

module Market
  module MarketHelper
    # The comparison's tool columns: what a website shows about how a business markets itself.
    MARKET_COLUMNS = {
      "Ads" => %w[google_ads meta_pixel microsoft_ads tiktok_pixel linkedin_insight],
      "Measures" => %w[google_analytics tag_manager call_tracking],
      "Converts" => %w[chat booking reviews_widget email_capture]
    }.freeze

    SEVERITY_BADGES = {"high" => "badge badge--danger", "medium" => "badge badge--warning", "low" => "badge", "info" => "badge badge--info"}.freeze

    def market_severity_tag(finding)
      tag.span(finding.severity == "info" ? "Worth knowing" : finding.severity.capitalize, class: SEVERITY_BADGES.fetch(finding.severity))
    end

    def market_threat_tag(competitor)
      tag.span("#{competitor.threat.capitalize} threat", class: {"high" => "badge badge--danger", "medium" => "badge badge--warning"}.fetch(competitor.threat, "badge"))
    end

    def market_impact_tag(opportunity)
      tag.span("#{opportunity.impact.capitalize} impact", class: opportunity.impact == "high" ? "badge badge--success" : "badge")
    end

    def market_effort_tag(opportunity)
      tag.span("#{opportunity.effort.capitalize} effort", class: opportunity.effort == "low" ? "badge badge--success" : "badge")
    end

    def market_tool_labels(reading, keys = Market::Probe::TOOLS.keys)
      return [] unless reading

      keys.select { reading.runs?(it) }.map { Market::Probe::TOOLS.dig(it, 0) }
    end

    # Which of a column's tools a reading found: a lit dot each, named on hover and to screen readers.
    def market_tool_dots(reading, keys)
      return tag.span("—", class: "text-faint") unless reading&.read?

      found = keys.select { reading.runs?(it) }
      return tag.span("None", class: "text-small text-muted") if found.empty?

      safe_join(found.map do |key|
        label = Market::Probe::TOOLS.dig(key, 0)
        tag.span(class: "market-dot market-dot--on", title: label) + tag.span(label, class: "visually-hidden")
      end, " ")
    end

    # A reading's figure, or a dash; a floor ("1,214+") when only part of a big sitemap was read.
    def market_figure(reading, key)
      value = reading&.figure(key)
      return tag.span("—", class: "text-faint") if value.nil?
      return l(Date.parse(value), format: :short) if key.to_s == "last_changed"
      return "#{number_with_delimiter(value)}+" if reading.partial_sitemap? && key.to_s.in?(%w[pages posts locations services posts_last_90_days])

      value.is_a?(Integer) ? number_with_delimiter(value) : value
    end

    # One line on what a reading found: pages, posts, how fresh, what it runs.
    def market_reading_line(reading)
      return "Not read yet" unless reading
      return "Couldn't be read: #{reading.error}" unless reading.read?

      sitemap = reading.sitemap
      parts = []
      parts << "#{number_with_delimiter(sitemap["pages"])}#{"+" if reading.partial_sitemap?} pages" if sitemap["pages"]
      parts << "#{pluralize(sitemap["posts"], "post")} (#{sitemap["posts_last_90_days"]} in 90 days)" if sitemap["posts"].to_i.positive?
      parts << pluralize(sitemap["locations"], "location page") if sitemap["locations"].to_i.positive?
      ads = market_tool_labels(reading, MARKET_COLUMNS["Ads"])
      parts << "runs #{ads.to_sentence}" if ads.any?
      parts << "no sitemap" if reading.facts.dig("sitemap", "error")
      parts.join(" · ").presence || "Read; nothing to count"
    end

    # A figure and how it moved since the pull before: "1,240 ↑12%".
    def market_change(now, before)
      return tag.span("—", class: "text-faint") if now.nil?

      text = number_with_delimiter(now)
      return text if before.nil? || before.to_i.zero? || now == before

      change = ((now.to_f - before) * 100 / before).round
      safe_join([text, " ", tag.span("#{change.positive? ? "↑" : "↓"}#{change.abs}%", class: change.positive? ? "market-up" : "market-down")])
    end

    # A tracked position and how it moved ("4 ↑2"); lower is better.
    def market_position(now, before)
      return tag.span("—", class: "text-faint", title: "Not in the top #{Market::Search::Api::RANKING_DEPTH}") if now.nil?
      return now.to_s if before.nil? || before == now

      safe_join([now.to_s, " ", tag.span("#{(now < before) ? "↑" : "↓"}#{(before - now).abs}", class: (now < before) ? "market-up" : "market-down")])
    end

    def market_money(amount) = "$#{format("%.2f", amount.to_d)}"
  end
end
