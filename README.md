# Market

A plugin for the CMS (see `docs/plugins.md` in [Libre Publish](https://github.com/Martin-Business-Consultants/libre-publish)).

The big picture behind the site's SEO and marketing, beside the site it's about.

- **Get started** with a short intake: the business's name, website and ZIP, and a line on what it
  does. The AI plugin then reads the website (the home page and its about, services and locations
  pages) and what's in the CMS (its pages and the brand brief). From those it fills in the rest of
  the profile as a starting point: industry, area, offerings, audience, positioning, starting goals,
  search location, its name on Maps and a radius. It also suggests competitors and searches to watch,
  each a click from being added. It fills only empty fields and marks each one for a person to check;
  a field someone changes is theirs from then on. Agents and harnesses can run it too:
  `cms post /api/market/intake '{"intake":{"business_name":"…","website":"…","local_zip":"…"}}'`.
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
- **Local search** works from a ZIP (or postcode) and a radius in miles (Market › Profile), not the whole
  country. On every pull, each tracked search is checked on Google Maps from a grid of points across the
  area (3×3, 5×5 or 7×7). **Maps** lists the searches beside the open one: its grid with the business's
  map position at every point (green for the top 3, amber for 4 to 10, red for further or not found; choose
  a point for who's shown there), the average position, the share of points in the top 3, who leads the
  area with their rating and reviews (watch them in one click), next steps (close the review gap, win the
  part of the area it's weak in), and AI suggestions. Organic searches
  run from the ZIP too. The ZIP is located once with OpenStreetMap, and the business is found among the
  map results by its website or its name on Google Maps. Findings flag a search where it isn't on the map
  anywhere in the area, where it's weak across much of it, and where it slips.
- **Google** (with the [Google plugin](https://github.com/Martin-Business-Consultants/cms-google) connected):
  Search Console's real clicks and searches, Analytics' visits and enquiries, and the Business Profile's
  calls and reviews join everything above. Search shows the searches the site is close on (track them in a
  click) and the pages shown a lot but clicked little (open one for the AI's rewrite); findings flag those,
  clicks or enquiries falling, landing pages that convert nobody, calls falling and unanswered reviews; the
  report adds clicks, enquiries and the profile to the health score and charts them by week; Maps shows the
  profile's calls and reviews; and the AI's suggestions are written from Google's own figures.
- **Report** gives the market's health in one score out of 100, made of search visibility, the tracked
  searches, Google Maps, content and the open findings, and charts how each has moved: search traffic
  against each competitor, the site's keywords, tracked positions, the map, posting, content beside
  theirs, findings found and resolved, the plan's progress and what DataForSEO cost.
- **Competitors** each have next steps (read them, pull their search data, size them up, act on the
  findings about them, track the searches they win) and can be **sized up by the AI**: how they win,
  strengths and weaknesses (saved onto the competitor in one click), the threat, and moves to beat them,
  each an opportunity in one click.
- **Findings** say what all of it means, with the exact figures and where they came from. For example:
  keywords a competitor is on page one for and the site isn't, search traffic falling or a competitor's
  surging, tracked searches dropping, competitors outranking, running ads, publishing or with a page per
  town while the site doesn't, sites competing in search that aren't watched, and data going stale. Each
  has a stable key and is kept while it holds; dismiss one and it stays dismissed while it holds.
- **The plan** is drafted by the [AI plugin](https://github.com/Martin-Business-Consultants/cms-ai) (your provider, such as
  OpenCode Zen, set up once in Settings › AI), findings first, in the
  brand's voice (Settings › Brand context). It gives the state of the market, the angle to win on, and
  opportunities by channel, impact, effort and when. It can also suggest an industry, competitors and
  searches to track, each taken in one click after a person checks it.
- **AI suggestions** turn the plan into changes to the site. Open a site or a tracked search on the
  Search page (a sheet), a search on Maps, or an opportunity, and the AI reads the facts, the plan's big
  picture and angle, the brand brief and the site's pages, and suggests changes: a page's title, meta
  title and description, focus keyword, JSON-LD and wording; posts written in full; new pages; searches to
  track; tasks off the site. **Page changes and posts go to [Approvals](https://github.com/Martin-Business-Consultants/cms-approvals)**,
  where a person compares them with what's live, edits and puts them live; nothing here publishes.
  A new page starts as a draft, searches are tracked, and a task goes on the plan.

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
    cms get /api/market/report                                  # the health score, its parts and every charted series
    cms post /api/market/workups '{"subject":"keyword:4"}'      # AI suggestions: keyword:<id>, map:<keyword id>, visibility:own|<competitor id>, opportunity:<id>, finding:<id>, page:<id>
    cms get /api/market/workups/7                               # its changes, and what each became
    cms post /api/market/workups/7/changes/0 '{}'               # send one on: page changes and posts are held in Approvals

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
