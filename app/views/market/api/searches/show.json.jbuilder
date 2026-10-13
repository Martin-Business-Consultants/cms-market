# frozen_string_literal: true

settings = Market::Settings.current
json.summary @data.pulled? ? "Search data from DataForSEO (#{settings.country}), pulled #{@data.last_pull&.finished_at&.to_date&.to_fs(:long)}" : "No search data yet"
json.country settings.country
json.search_location @data.profile.search_location
json.local_area @data.profile.local_h
json.last_pull do
  if @data.last_pull
    json.extract! @data.last_pull, :id, :state, :error, :notes, :finished_at
    json.cost @data.last_pull.cost.to_f
  else
    json.nil!
  end
end
json.sites @data.sites do |site|
  json.name site.name
  json.domain site.domain
  json.this_site site.own?
  json.competitor_id site.competitor&.id
  json.overview site.overview&.data
  json.overview_at site.overview&.taken_at
  json.previous_overview site.previous&.data
  json.previous_overview_at site.previous&.taken_at
  json.backlinks site.backlinks&.data
  json.keywords_total site.keywords&.data&.dig("total")
  json.keywords Array(site.keywords&.data&.dig("keywords")).first(@limit)
end
json.tracked @data.tracked do |row|
  json.id row[:keyword].id
  json.keyword row[:keyword].keyword
  json.source row[:keyword].source
  json.checked_at row[:ranking]&.checked_at
  json.location row[:ranking]&.location
  json.position row[:position]
  json.position_before row[:before]
  json.url row[:ranking]&.url
  json.page row[:page] ? {path: row[:page].path, title: row[:page].title, status: row[:page].status} : nil
  json.competitors row[:competitors]
  json.on_the_page row[:ranking]&.features || []
  if (scan = row[:local])
    json.local do
      json.extract! scan, :zip, :radius_miles, :grid, :average_position, :top3_share, :found_points, :leaders, :points, :checked_at
      json.average_position_before row[:local_before]&.average_position
    end
  else
    json.local nil
  end
end
json.also_competing_in_search @data.unwatched
