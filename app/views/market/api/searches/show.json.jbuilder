# frozen_string_literal: true

settings = Market::Settings.current
json.sources({
  google: "Google's results for each tracked search, checked live from the business's area (DataForSEO SERP API)",
  ai: "Each tracked search asked of each AI, checked live (DataForSEO: Google AI Overview and AI Mode, ChatGPT and Gemini via LLM Scraper, Perplexity and Claude via LLM Responses)",
  ai_database: "AI share of voice and answers from DataForSEO's database of real ChatGPT and Google AI Overview answers (LLM Mentions)",
  estimate: "Visibility, keywords, keyword facts and who wins: DataForSEO Labs' estimates, country-wide",
  maps: "Google Maps from a grid across the area (DataForSEO SERP API)",
  business: "Google Business Profiles (DataForSEO Business Data API)",
  site: "The home page rendered and Lighthouse on a phone (DataForSEO On-Page API)",
  web: "Pages naming each business (DataForSEO Content Analysis API)"
})
json.sandbox settings.sandbox?
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
  json.ai_overview_citations site.ai_overview&.data
  json.business_profile site.business_profile&.data
  json.web_mentions site.web_mentions&.data
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
  json.local_pack row[:ranking]&.local_pack || []
  json.people_also_ask row[:ranking]&.questions || []
  json.facts row[:facts]
  json.ai(row[:ai].transform_values do |check|
    {answered: check.answered, named: check.mentioned, rank: check.mention_rank, cited: check.cited, verdict: check.verdict,
     named_businesses: check.named, sources: check.sources, model: check.model, prompt: check.prompt, answer: check.answer.to_s.truncate(1500),
     error: check.error, checked_at: check.checked_at}
  end)
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
json.ai_search do
  json.summary @data.ai_summary
  json.named_instead(@data.ai_named_others.map { |name, count| {name: name, answers: count} })
  json.cited_sites(@data.ai_cited_domains.map { |domain, count| {domain: domain, answers: count} })
  json.share_of_voice @data.market("ai_mentions")&.data
  json.answers_mentioning_site @data.market("ai_answers")&.data&.dig("answers")
end
json.who_wins @data.market("serp_competitors")&.data&.dig("sites")
json.site_health @data.market("site_health")&.data
