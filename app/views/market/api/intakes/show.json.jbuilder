# frozen_string_literal: true

json.extract! @intake, :id, :state, :answers, :summary, :filled, :competitor_suggestions, :keyword_suggestions, :to_check, :error, :created_at, :finished_at
json.working @intake.working?
json.profile do
  json.business_name @profile.business_name
  json.website @profile.website
  json.merge! @profile.to_h
  json.local @profile.local_h
  json.to_check @profile.ai_filled
end
