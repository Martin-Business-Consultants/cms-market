# frozen_string_literal: true

json.keywords @keywords do |keyword|
  ranking = @rankings[keyword.id]&.first
  json.extract! keyword, :id, :keyword, :source, :created_at
  json.position ranking&.position
  json.checked_at ranking&.checked_at
end
