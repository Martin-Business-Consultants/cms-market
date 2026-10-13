# frozen_string_literal: true

require_relative "lib/market/version"

Gem::Specification.new do |spec|
  spec.name = "market"
  spec.version = Market::VERSION
  spec.summary = "Market for Libre Publish: the site's competitors watched, its search data, findings and a plan for the SEO and marketing that wins its market"
  spec.authors = ["Martin Business Consultants"]
  spec.license = "FSL-1.1-MIT"
  spec.files = Dir["{app,config,db,lib}/**/*"]
  spec.required_ruby_version = ">= 3.3"
  spec.add_dependency "rails", ">= 8.1"
end
