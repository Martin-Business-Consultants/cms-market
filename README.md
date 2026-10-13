# Market

A plugin for the CMS (see `docs/plugins.md` in [Libre Publish](https://github.com/Martin-Business-Consultants/libre-publish)).

The big picture behind the site's SEO and marketing, beside the site it's about.

- **The profile** says what the business is: its industry, where and whom it serves, what it sells, how it
  wants to be seen, what it's after, and where its customers search from (Market › Profile). Its website
  is the site itself (Settings › General).
- **Competitors** have their websites read from outside every week, as a visitor would. A reading covers:
  - the sitemap: pages, posts (and how many in the last 90 days), location and service pages, and when
    the site last changed;
  - the home page: the ad, analytics, call tracking, chat, reviews, booking and email tools it runs, its
    socials and its structured data.

  What changes between readings is kept ("Now runs Google Ads", "+12 location pages"). The site is read
  the same way and compared with them in one table.
- **Search data from [DataForSEO](https://dataforseo.com)**, on your own account (Settings › Market),
  covers each site's visibility (keywords in the top 3, 10 and 20, estimated traffic, paid keywords,
  compared with the pull before), the keywords each ranks for, the sites that share the site's keywords
  but aren't watched yet, backlinks if you have that subscription, and where everyone ranks for the
  searches you track, checked from the business's own city, with the CMS page that ranks. It runs:
  - **with spending capped:** every request is checked against the month's budget first and kept with
    its cost;
  - **with retries:** what may pass (timeouts, rate limits, "try again") is tried again with backoff;
  - **stopping safely:** a wrong login, an empty account or a spent budget stops a pull and keeps what
    it got;
  - **without buying twice:** a part pulled in the last day isn't paid for again;
  - **when you choose:** when someone asks, or every week or month.
- **Findings** say what all of it means, with the exact figures and where they came from. For example:
  keywords a competitor is on page one for and the site isn't, search traffic falling or a competitor's
  surging, tracked searches dropping, competitors outranking, running ads, publishing or with a page per
  town while the site doesn't, sites competing in search that aren't watched, and data going stale. Each
  has a stable key and is kept while it holds; dismiss one and it stays dismissed while it holds.
- **The plan** is drafted by the [AI plugin](https://github.com/Martin-Business-Consultants/cms-ai) (your provider, such as
  OpenCode Zen, set up once in Settings › AI), findings first, in the
  brand's voice (Settings › Brand context). It gives the state of the market, the angle to win on, and
  opportunities by channel, impact, effort and when. It can also suggest an industry, competitors and
  searches to track, each taken in one click after a person checks it. **An opportunity starts a draft
  page in one click**, so the work begins in the CMS. Nothing on the site changes until a person acts.

## For agents and a local harness

Everything is at `/api/market/…`, listed in `/api/manifest`, so the `cms` CLI reaches it:

    cms get /api/market                                         # at a glance: profile, findings by severity, best opportunities, changes
    cms get "/api/market/findings?since=2026-10-13T09:00:00Z"   # only what appeared, changed, resolved or was dismissed since
    cms get /api/market/findings                                # keep its as_of; pass it as since next time
    cms get "/api/market/search?keywords=200"                   # visibility, keywords, tracked searches with the page that ranks
    cms get /api/market/competitors                             # each with its latest reading and changes, and the site's own
    cms post /api/market/keywords '{"keyword":{"keywords":"emergency dentist grand rapids"}}'
    cms post /api/market/search/pulls '{}'                      # spends from the month's budget (market:search)
    cms post /api/market/plans '{}'                             # the AI drafts a plan (a minute or two)
    cms post /api/market/opportunities/12/page '{}'             # a draft page for an opportunity

A refusal says why, with HTTP 409 (`{"error":"refused","message":"Connect DataForSEO in Settings › Market first"}`).

Capabilities: `market:read`, `market:write` and `market:search` (pulls, which spend). Editors start
with all three, authors with read, and the Agent role with read and write. Settings › Market takes
`settings:read` and `settings:write`; secrets are never read back.

Install it into a CMS checkout (core 1.32 or newer):

    bin/rails "plugins:install[https://github.com/Martin-Business-Consultants/cms-market]"

or add it from Settings › Plugins, then switch it on. Its specs run inside the CMS, with the plugin
in `plugins/market`:

    bin/rspec plugins/market/spec

To release, bump `lib/market/version.rb`, commit, and tag `vX.Y.Z`.
