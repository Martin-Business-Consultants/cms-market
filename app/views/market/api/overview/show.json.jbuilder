# frozen_string_literal: true

json.summary "#{@profile.business_name}: #{@competitors} #{"competitor".pluralize(@competitors)}, #{@findings.size} open #{"finding".pluralize(@findings.size)}" \
  "#{" (#{@findings.count { it.severity == "high" }} high)" if @findings.any? { it.severity == "high" }}, #{Market::Opportunity.open.count} open opportunities" \
  "#{"; missing from the profile: #{@profile.gaps.to_sentence}" if @profile.gaps.any?}"
json.profile do
  json.business_name @profile.business_name
  json.website @profile.website
  json.merge! @profile.to_h
  json.missing @profile.gaps
end
json.goals(@goals.map { Market::Goal.as_api(it) })
json.do_next(@guide.actions.map { |action| {key: action.key, kind: action.kind, title: action.title, why: action.why, urgent: action.tone == :urgent} })
json.setup(@guide.steps.map { |step| {key: step.key, title: step.title, done: step.done, optional: step.optional} })
json.site_read_at @own&.taken_at
json.findings_by_severity Market::Finding::SEVERITIES.index_with { |severity| @findings.count { it.severity == severity } }
json.top_findings @findings.first(10) do |finding|
  json.partial! "market/api/findings/finding", finding: finding
end
json.best_opportunities @opportunities do |opportunity|
  json.partial! "market/api/opportunities/opportunity", opportunity: opportunity
end
json.competitor_changes @changes do |reading|
  json.competitor({id: reading.competitor.id, name: reading.competitor.name})
  json.read_at reading.taken_at
  json.changes reading.differences
end
json.next ["GET /api/market/goals", "GET /api/market/findings?since=<as_of>", "GET /api/market/search", "GET /api/market/competitors", "POST /api/market/plans"]
