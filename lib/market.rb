# frozen_string_literal: true

require "market/version"
require "market/engine"

# Market: the big picture behind the site's SEO and marketing. The business's
# profile (industry, area, offerings, audience, goals); its competitors, their
# websites read from outside every week and what changes in them kept; search
# data from DataForSEO (visibility, keywords, who ranks where for the searches
# that matter); findings worked out from all of it, with exact evidence; and a
# plan drafted by the AI plugin (cms-ai), whose opportunities can start draft
# pages here.
# Installed from its own repository; off by default.
module Market
  # Plugin tables are prefixed with the plugin's key.
  def self.table_name_prefix = "market_"
end
