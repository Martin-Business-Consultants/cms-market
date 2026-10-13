# frozen_string_literal: true

json.summary "#{@opportunities.size} #{(@state == "all") ? "" : "#{@state} "}#{"opportunity".pluralize(@opportunities.size)}"
json.opportunities @opportunities do |opportunity|
  json.partial! "market/api/opportunities/opportunity", opportunity: opportunity
end
