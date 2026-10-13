# frozen_string_literal: true

module Market
  # A CMS plugin (docs/plugins.md): it extends the core only through
  # Cms::Plugins, and the core never names it.
  class Engine < ::Rails::Engine
    initializer "market.migrations" do |app|
      config.paths["db/migrate"].expanded.each { |path| app.config.paths["db/migrate"] << path }
    end

    initializer "market.routes" do |app|
      app.routes.append do
        admin = proc do
          get "market", to: "market/overview#show", as: :market_overview
          scope "market", module: "market", as: "market" do
            resource :intake, only: [:new, :create, :show]
            resource :profile, only: [:edit, :update]
            resource :site_check, only: :create
            resources :competitors do
              resource :check, only: :create, controller: "competitors/checks"
            end
            resource :search, only: :show, controller: "searches"
            resources :search_pulls, only: [:index, :create], path: "search/pulls"
            resources :keywords, only: [:create, :destroy]
            resources :findings, only: [:index, :update] do
              post :refresh, on: :collection
            end
            resource :plan, only: :show
            resources :plans, only: :create
            resources :opportunities, only: [:index, :create, :update, :destroy] do
              resource :page, only: :create, controller: "opportunities/pages"
            end
          end

          scope "settings", as: "settings" do
            resource :market, only: [:show, :update], controller: "market/settings" do
              resource :check, only: :create, controller: "market/settings_checks"
            end
          end
        end
        defined?(Cms::PATH) ? scope(path: Cms::PATH, &admin) : admin.call

        scope "api", defaults: {format: :json} do
          get "market", to: "market/api/overview#show", as: :api_market
          scope "market", module: "market/api", as: "api_market" do
            resource :intake, only: [:show, :create]
            resource :profile, only: [:show, :update]
            resources :findings, only: [:index, :update] do
              post :refresh, on: :collection
            end
            resources :competitors, only: [:index, :show, :create, :update, :destroy] do
              resource :check, only: :create, controller: "competitor_checks"
            end
            resource :site_check, only: :create
            resource :search, only: :show, controller: "searches"
            resources :search_pulls, only: [:index, :create], path: "search/pulls"
            resources :keywords, only: [:index, :create, :destroy]
            resources :plans, only: [:index, :create]
            resources :opportunities, only: [:index, :create, :update, :destroy] do
              resource :page, only: :create, controller: "opportunity_pages"
            end
            resource :settings, only: [:show, :update]
          end
        end
      end
    end

    config.to_prepare do
      Cms::Plugins.register :market, name: "Market", version: Market::VERSION, author: "Martin Business Consultants",
        enabled_by_default: false, requires: ">= 1.32", homepage: "https://github.com/Martin-Business-Consultants/cms-market",
        description: "The big picture behind the site's SEO and marketing: its competitors' websites watched every week, " \
                     "search data from DataForSEO, findings with the exact figures behind them, and a plan drafted by " \
                     "the AI plugin whose opportunities start draft pages here."

      Cms::Plugins.menu :market, :market, label: "Market", icon: "chart", group: "Content", after: [:leads, :forms, :globals],
        path: -> { market_overview_path }, capability: "market:read"
      Cms::Plugins.submenu :market, :market, label: "Overview", path: -> { market_overview_path }, capability: "market:read"
      Cms::Plugins.submenu :market, :market, label: "Findings", path: -> { market_findings_path }, capability: "market:read", after: "Overview"
      Cms::Plugins.submenu :market, :market, label: "Competitors", path: -> { market_competitors_path }, capability: "market:read", after: "Findings"
      Cms::Plugins.submenu :market, :market, label: "Search", path: -> { market_search_path }, capability: "market:read", after: "Competitors"
      Cms::Plugins.submenu :market, :market, label: "Plan", path: -> { market_plan_path }, capability: "market:read", after: "Search"
      Cms::Plugins.submenu :market, :market, label: "Profile", path: -> { edit_market_profile_path }, capability: "market:write", after: "Plan"

      Cms::Plugins.permissions :market, "Market", %w[market:read market:write market:search],
        after: ["Leads", "Commerce", "Forms", "Globals"],
        defaults: {editor: %w[market:read market:write market:search], author: %w[market:read], agent: %w[market:read market:write]}
      Cms::Plugins.settings :market, "Market", -> { settings_market_path },
        description: "The DataForSEO account search data comes from, its monthly budget, and where searches are measured.",
        capability: "settings:read"

      Cms::Plugins.slot :dashboard, :market, "market/slots/dashboard"
      Cms::Plugins.stylesheet :market, "market/market"
      Cms::Plugins.counts :market, competitors: -> { Market::Competitor.count }, findings: -> { Market::Finding.open.count }
      Cms::Plugins.nightly :market, -> { Market::NightlyJob.perform_later }

      Cms::Plugins.api :market, "/api/market",
        description: "The market at a glance: the profile and what's missing from it, open findings by severity, the best opportunities, what competitors changed lately."
      Cms::Plugins.api :market, "/api/market/findings",
        description: "What the data says, worst first: each finding's stable key, kind, severity, channel, title, detail, exact evidence and sources. " \
                     "?since=<ISO time> answers only what appeared, changed, resolved or was dismissed after it (pass back as_of); ?state, ?severity, ?kind, ?channel. " \
                     "PATCH /api/market/findings/:id {\"finding\":{\"state\":\"dismissed\"|\"open\"}}; POST /api/market/findings/refresh."
      Cms::Plugins.api :market, "/api/market/intake",
        description: "The starting point: POST {\"intake\":{\"business_name\",\"website\",\"local_zip\",\"about\"}} saves them and has the AI fill in the rest of the profile from the site (a minute or two); GET answers the latest: what it filled, its summary, and the competitors and searches it suggests checking."
      Cms::Plugins.api :market, "/api/market/profile", description: "The business's market profile: industry, area, offerings, audience, positioning, goals, search_location."
      Cms::Plugins.api :market, "/api/market/competitors",
        description: "Competitors with their latest website reading and changes: list, show, create (name, website, kind, threat), update, delete. POST /api/market/competitors/:id/check reads one now; POST /api/market/site_check reads the site."
      Cms::Plugins.api :market, "/api/market/search",
        description: "Search data from DataForSEO: every site's visibility now and before, its keywords (?keywords=50..500), the tracked searches with everyone's positions and the site's page, and sites sharing its keywords."
      Cms::Plugins.api :market, "/api/market/search/pulls",
        description: "Pulls of search data (GET: their state, cost and notes). POST spends from the month's DataForSEO budget (market:search); {\"pull\":{\"force\":true}} buys parts pulled in the last day again."
      Cms::Plugins.api :market, "/api/market/keywords", description: "Searches tracked: list, add ({\"keyword\":{\"keywords\":\"one a line\"}}), remove."
      Cms::Plugins.api :market, "/api/market/plans", description: "Plans drafted by the AI plugin (the latest first); POST drafts a new one from everything known (a minute or two)."
      Cms::Plugins.api :market, "/api/market/opportunities",
        description: "Opportunities, best first (?state, ?channel, ?horizon): add, change (state: done, dismissed, planned, open), delete. POST /api/market/opportunities/:id/page starts a draft page for one."
      Cms::Plugins.api :market, "/api/market/settings", description: "Settings › Market (read with settings:read, change with settings:write; secrets are never read back)."
    end
  end
end
