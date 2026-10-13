# frozen_string_literal: true

json.pulls @pulls do |pull|
  json.extract! pull, :id, :state, :force, :error, :notes, :created_at, :started_at, :finished_at
  json.cost pull.cost.to_f
  json.working pull.working?
end
