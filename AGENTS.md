# Market, a Libre Publish plugin — guide for AI agents

This repository is a plugin for the Libre Publish CMS: a Rails engine loaded into an install from
`plugins/market`. It isn't an app on its own. Read the core's `docs/plugins.md` (the contract) and
`STYLE.md` (how code is written) first; this code follows both.

- Tables are `market_*`. One install is one site, so there's no client: a reading, search snapshot or
  ranking with no competitor is the site's own. Settings and the profile live in the core's Setting
  "market" (`Market::Settings`, `Market::Profile`); the DataForSEO password is among its secrets and
  is never rendered or read back.
- Register everything in `lib/market/engine.rb`'s `config.to_prepare`. Admin controllers inherit
  `Market::ApplicationController`, API ones `Market::Api::BaseController` (refusals are 409
  `{"error":"refused","message":…}`); every action declares its capability.
- `Market::Probe` reads a website from outside: public addresses only, timeouts, size caps, the first
  5 sitemaps of an index (counts are then a floor). `Market::Reading.take` keeps it with the
  differences from the reading before.
- `Market::Search::Client` is the only thing that calls DataForSEO. It checks the budget (the
  `SearchRequest` ledger) with a ceiling first, records every call, retries what may pass with
  backoff, and raises `AuthError`, `FundsError` and `BudgetError` (which stop a pull) or
  `InvalidError` and `UnavailableError` (which skip a part). `Market::SearchPull#run!` never raises.
- Local search: `Market::Profile` holds a ZIP, radius and grid; `Market::Geocoder` locates the ZIP
  once (OpenStreetMap). `Market::LocalGrid` lays the points; `SearchPull#local_scans` asks
  `Search::Api#maps` at each (Google Maps, a point and zoom) and keeps a `Market::LocalScan` per
  search. Organic rankings use the ZIP's centre as `location_coordinate` when it's set.
- `Market::Finding.refresh` upserts what `Finding::Analysis` works out by stable key, moves
  `changed_at` only on a change, and resolves what stops holding. It runs after every reading and
  pull, after profile and competitor changes, and nightly. `GET /api/market/findings?since=` is
  how a harness hears each change once; `as_of` has microseconds.
- Plans are drafted by the AI plugin (cms-ai): `Market::Plan#run!` asks `Ai.structured` with
  `Plan::Brief` and never raises; `Plan.ai_available?` checks the plugin is installed, on and set up,
  so Market works without it. Market keeps no AI key or model of its own.
- `Market::Opportunity#start_page` makes a draft Page (a free slug, the detail as its meta
  description) and plans the opportunity.
- Views use the admin's CSS vocabulary; what's Market's alone is a `market-*` class in
  `app/assets/stylesheets/market/market.css`. ReActionView renders `<%= a || tag.span(…) %>` as the
  span whatever `a` is: write a ternary or an if. Keep string comparisons out of `class` attributes:
  the architecture spec reads them as class names.

Check: `bin/rspec plugins/market/spec spec/architecture`, `bundle exec herb lint plugins/market/app/views`
and `bin/rubocop plugins/market`, all from the core.
