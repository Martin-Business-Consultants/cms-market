# frozen_string_literal: true

series = ->(list) { list.map { {name: it.name, own: it.own, points: it.points.map { |time, value| [time.iso8601, value] }} } }
json.since @report.since.iso8601
json.score @report.score
json.grade @report.grade
json.parts @report.parts.map { {key: it.key, label: it.label, score: it.score, detail: it.detail} }
json.visibility series.call(@report.visibility)
json.own_keywords series.call(@report.own_keywords)
json.rankings series.call(@report.rankings)
json.maps series.call(@report.maps)
json.posting series.call(@report.posting)
json.content(@report.content.map { |name, pages, posts, locations, services, own| {name:, pages:, posts_last_90_days: posts, locations:, services:, own:} })
json.findings_by_week series.call(@report.findings_by_week)
json.open_findings @report.open_findings
json.opportunities @report.opportunities
json.spend(@report.spend.map { |month, cost| {month: month.strftime("%Y-%m"), cost: cost.to_f} })
