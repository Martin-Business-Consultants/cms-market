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

    # Where a figure comes from, said the same way everywhere on Search.
    SOURCES = {
      console: ["Google Search Console", "Real clicks and searches, from the business's own Google account"],
      live: ["Google, checked live", "Google's results for each search, checked from the business's area by DataForSEO"],
      ai: ["AI answers, checked live", "Each search asked of each AI by DataForSEO, from the business's country"],
      ai_db: ["AI answers database", "DataForSEO's database of real ChatGPT and Google AI Overview answers"],
      estimate: ["Estimate", "DataForSEO Labs' estimate from its own crawl of Google, country-wide"],
      maps: ["Google Maps, checked live", "Maps checked from points across the business's area by DataForSEO"],
      business: ["Business Profile", "Google Business Profiles as customers see them, read by DataForSEO"],
      site: ["Site check", "The home page rendered as Google does, and Lighthouse on a phone, by DataForSEO"],
      web: ["Web mentions", "Pages across the web that name the business, found by DataForSEO"],
      reviews: ["Google reviews", "Each business's latest Google reviews, read by DataForSEO (its queue) and the AI plugin"],
      backlinks: ["Backlinks", "Links from other sites, from DataForSEO's Backlinks index"],
      ads: ["Google Ads", "Searches a month and cost per click from Google Ads, through DataForSEO"]
    }.freeze

    def market_source(kind)
      label, title = SOURCES.fetch(kind)
      tag.span(label, class: "market-source", title: title)
    end

    # One AI's answer to one search, as a mark: named and cited, named, cited only, not named, or no answer.
    AI_MARKS = {"named_cited" => ["●", "Named, and cited its site", "market-ai market-ai--named"], "named" => ["●", "Named", "market-ai market-ai--named"],
                "cited" => ["◐", "Cited its site, without naming it", "market-ai market-ai--cited"], "missing" => ["○", "Answered without it", "market-ai market-ai--missing"],
                "no_answer" => ["–", "No answer", "market-ai"]}.freeze

    def market_ai_mark(check)
      return tag.span("·", class: "market-ai", title: "Not asked yet") unless check

      mark, label, classes = AI_MARKS.fetch(check.verdict)
      rank = (check.mention_rank && check.mention_rank > 0) ? " ##{check.mention_rank}" : ""
      tag.span(class: classes, title: "#{check.platform_name}: #{label}#{rank}#{" (#{check.error})" if check.error.present?}") do
        safe_join([mark, (check.mentioned && check.mention_rank ? tag.sup(check.mention_rank) : nil), tag.span("#{check.platform_name}: #{label}", class: "visually-hidden")].compact)
      end
    end

    def market_channel_label(channel) = Market::Opportunity::CHANNELS[channel]
    def market_change_kind(kind) = Market::Workup::KINDS[kind]

    def market_money(amount) = "$#{format("%.2f", amount.to_d)}"

    # A finding's evidence, readable: a hash as labelled facts, a list of like
    # records as a small table, a list of words as chips, figures with commas.
    def market_evidence(value, depth: 0)
      case value
      when Hash
        tag.dl(class: "market-facts text-small") do
          safe_join(value.compact_blank.map { |key, item| safe_join([tag.dt(key.to_s.humanize), tag.dd(market_evidence(item, depth: depth + 1))]) })
        end
      when Array
        if value.all?(Hash) && value.any?
          columns = value.flat_map(&:keys).uniq.first(6)
          tag.table(class: "data-table market-evidence-table") do
            safe_join([
              tag.thead(tag.tr(safe_join(columns.map { tag.th(it.to_s.humanize) }))),
              tag.tbody(safe_join(value.first(15).map { |row| tag.tr(safe_join(columns.map { tag.td(market_evidence(row[it], depth: depth + 1)) })) }))
            ])
          end
        elsif value.any?
          tag.ul(safe_join(value.first(20).map { tag.li(it.to_s) }), class: "market-chips text-small")
        else
          tag.span("None", class: "text-muted")
        end
      when Float then number_with_delimiter(value.round(2))
      when Integer then number_with_delimiter(value)
      when true then "Yes"
      when false then "No"
      when nil then tag.span("—", class: "text-faint")
      else value.to_s
      end
    end
  end
end
