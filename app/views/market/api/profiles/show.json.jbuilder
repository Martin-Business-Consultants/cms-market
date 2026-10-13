# frozen_string_literal: true

json.business_name @profile.business_name
json.website @profile.website
json.domain @profile.domain
json.merge! @profile.to_h
json.missing @profile.gaps
json.local @profile.local_h
