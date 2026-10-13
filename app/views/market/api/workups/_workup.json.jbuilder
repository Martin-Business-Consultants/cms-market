# frozen_string_literal: true

json.call(workup, :id, :subject, :state, :error, :started_at, :finished_at, :created_at)
json.working workup.working?
json.summary workup.summary
json.changes workup.changes.each_with_index.to_a do |change, index|
  json.index index
  json.merge! change
  json.sent workup.sent_for(index)
end
