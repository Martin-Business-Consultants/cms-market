# frozen_string_literal: true

module Market
  # Charts drawn as inline SVG, so they follow the admin's colours (the
  # market-chart classes) and need nothing loaded: lines over time, and
  # horizontal bars. Every point is named on hover and in a table for screen
  # readers.
  module ChartHelper
    WIDTH = 640
    HEIGHT = 200
    PAD = {left: 44, right: 12, top: 12, bottom: 24}.freeze
    TONES = %w[market-chart__line--0 market-chart__line--1 market-chart__line--2 market-chart__line--3 market-chart__line--4 market-chart__line--5].freeze

    # series: Market::Report::Series; `lower_is_better` draws the axis upside down (positions).
    def market_line_chart(series, label:, lower_is_better: false, format: ->(value) { number_with_delimiter((value.abs >= 100 || value == value.round) ? value.round : value.round(1)) })
      series = series.select { it.points.any? }
      return tag.p("Nothing to chart yet.", class: "text-small text-muted") if series.empty?

      times = series.flat_map { it.points.map { |time, _| time.to_f } }
      values = series.flat_map { it.points.map(&:last) }
      t0, t1 = times.minmax
      top = [values.max.to_f, 1].max * 1.1
      bottom = lower_is_better ? [values.min.to_f - 1, 0].max : 0
      x = ->(time) { (t1 == t0) ? (PAD[:left] + WIDTH - PAD[:right]) / 2.0 : PAD[:left] + (time.to_f - t0) / (t1 - t0) * (WIDTH - PAD[:left] - PAD[:right]) }
      y = lambda do |value|
        share = (value.to_f - bottom) / (top - bottom)
        share = 1 - share if lower_is_better
        (HEIGHT - PAD[:bottom] - share * (HEIGHT - PAD[:top] - PAD[:bottom])).round(1)
      end

      svg = tag.svg(class: "market-chart", viewBox: "0 0 #{WIDTH} #{HEIGHT}", role: "img", aria: {label: label}, preserveAspectRatio: "none") do
        safe_join([
          tag.line(x1: PAD[:left], x2: WIDTH - PAD[:right], y1: HEIGHT - PAD[:bottom], y2: HEIGHT - PAD[:bottom], class: "market-chart__axis"),
          tag.line(x1: PAD[:left], x2: WIDTH - PAD[:right], y1: PAD[:top], y2: PAD[:top], class: "market-chart__grid"),
          tag.text(format.call(lower_is_better ? bottom : top), x: PAD[:left] - 6, y: PAD[:top] + 4, class: "market-chart__label", "text-anchor": "end"),
          tag.text(format.call(lower_is_better ? top : bottom), x: PAD[:left] - 6, y: HEIGHT - PAD[:bottom], class: "market-chart__label", "text-anchor": "end"),
          tag.text(l(Time.zone.at(t0).to_date, format: :short), x: PAD[:left], y: HEIGHT - 6, class: "market-chart__label"),
          ((t1 > t0) ? tag.text(l(Time.zone.at(t1).to_date, format: :short), x: WIDTH - PAD[:right], y: HEIGHT - 6, class: "market-chart__label", "text-anchor": "end") : nil),
          *series.each_with_index.map do |line, index|
            tone = market_tone(line, index)
            points = line.points.map { |time, value| "#{x.call(time).round(1)},#{y.call(value)}" }
            safe_join([
              ((points.size > 1) ? tag.polyline(points: points.join(" "), class: ["market-chart__line", tone]) : nil),
              *line.points.map do |time, value|
                tag.circle(cx: x.call(time).round(1), cy: y.call(value), r: 3, class: ["market-chart__dot", tone]) do
                  tag.title("#{line.name}: #{format.call(value)}, #{l(time.to_date, format: :long)}")
                end
              end
            ].compact)
          end
        ].compact)
      end
      safe_join([svg, market_legend(series)])
    end

    # The site's line in the accent colour; each competitor's in the next tone.
    def market_tone(line, index) = line.own ? "market-chart__line--own" : TONES[index % TONES.size]

    # rows: [[name, value, own?]]
    def market_bars(rows, label:)
      return tag.p("Nothing to chart yet.", class: "text-small text-muted") if rows.empty?

      max = [rows.map { it[1].to_f }.max, 1].max
      tag.ul(class: "market-bars", aria: {label: label}) do
        safe_join(rows.map do |name, value, own|
          tag.li(class: "market-bars__row") do
            safe_join([
              tag.span(name, class: class_names("market-bars__name text-small", "text-ink": own)),
              tag.svg(class: "market-bars__track", viewBox: "0 0 100 10", preserveAspectRatio: "none", aria: {hidden: true}) do
                tag.rect(x: 0, y: 0, height: 10, width: (value.to_f / max * 100).round(1), class: class_names("market-bars__bar", "market-bars__bar--own": own))
              end,
              tag.span(number_with_delimiter(value), class: "market-bars__value text-small")
            ])
          end
        end)
      end
    end

    # A score out of 100, as a bar.
    def market_meter(score, label:)
      tag.svg(class: "market-meter", viewBox: "0 0 100 10", preserveAspectRatio: "none", role: "img", aria: {label: label}) do
        tag.rect(x: 0, y: 0, height: 10, width: score.to_i.clamp(0, 100), class: "market-meter__bar")
      end
    end

    def market_legend(series)
      tag.ul(class: "market-legend text-small") do
        safe_join(series.each_with_index.map do |line, index|
          tag.li(safe_join([tag.span(class: ["market-legend__swatch", market_tone(line, index)]), line.name]))
        end)
      end
    end
  end
end
