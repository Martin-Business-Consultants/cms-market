# frozen_string_literal: true

json.plans @plans do |plan|
  json.extract! plan, :id, :state, :summary, :positioning, :industry_suggestion, :competitor_suggestions, :keyword_suggestions, :error, :created_at, :finished_at
  json.working plan.working?
  json.opportunity_ids plan.opportunities.map(&:id)
end
