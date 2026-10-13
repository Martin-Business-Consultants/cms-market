# frozen_string_literal: true

json.summary "#{@findings.size} #{(@state == "all") ? "" : "#{@state} "}#{"finding".pluralize(@findings.size)}#{" changed since #{@since.iso8601}" if @since}"
json.as_of @as_of.utc.iso8601(6)
json.findings @findings do |finding|
  json.partial! "market/api/findings/finding", finding: finding
end
