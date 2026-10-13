# Market

A plugin for the CMS (see `docs/plugins.md` in [Libre Publish](https://github.com/Martin-Business-Consultants/libre-publish)).

The big picture behind the site's SEO and marketing, beside the site it's about.

## How it fits together

**Goals → Search → Findings → Plan → Do next.** Set what the marketing is for; Market measures where
the business stands; findings say what that means; the plan turns it into opportunities aimed at the
goals; the Overview hands you the next few things to do, one at a time.

- **Overview**: the goals and how each is going, **Do next** (the few things most worth doing now: goals
  falling behind, the worst findings, and the plan's opportunities, those serving a goal and this
  month's first) beside the one open, where it's acted on, the steps left to get set up, and what
  competitors changed.
- **Plan**: the goals (set, change, remove), the big picture and the angle to win on, and the
  opportunities grouped by the goal they serve. Each opens beside the list: work it out with the AI, put
  it on the [content calendar](https://github.com/Martin-Business-Consultants/cms-calendar), start a draft
  page, mark it done.
- **Findings**: what the data means, with the figures and where they're from.
- **Search**: where the business stands, in five tabs. **Searches** (the tracked searches on Google, Maps
  and each AI, what each is worth, and the searches worth writing about), **AI**, **Local** (the Maps grid),
  **Website** (visibility and its year of history, links, the site's health) and **Reputation** (reviews,
  Business Profiles, Trustpilot and Tripadvisor).
- **Competitors**: each one's website, search side (visits by month, best pages, profile, posts, reviews)
  and next steps. **Report**: the goals and the market's health over time.

**Goals** are measured from what Market already has: calls, enquiries and clicks (with the Google plugin),
visits from search, a search's place on Google or share of the Maps top 3, the share of AI answers naming
the business, reviews and rating. Each keeps where it started, and says whether it's on pace for its date.

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
  - **without buying twice:** a part pulled in the last day isn't paid for again (history and AI
    history: in the last 25 days);
  - **saving money** (on by default, Settings › Market): the checks that can wait (Google's results for
    each tracked search, every Maps point, AI Mode, ChatGPT, Gemini and Bing Copilot) go through
    DataForSEO's Standard queue, about a third of the Live price, in batches; they arrive within minutes
    and Search says how many are on their way;
  - **when you choose:** when someone asks, or every week or month.
- **AI search**, as part of Search: each tracked search is asked, on every pull, of **Google's AI Overview**
  (with the results page) and **AI Mode**, **ChatGPT** and **Gemini** (their real search answers, through
  DataForSEO's LLM Scraper), **Bing Copilot** (Bing's AI answer), and **Perplexity** and **Claude** (asked with web search on, through LLM
  Responses). For each: whether it answered, named the business (and its place among the businesses Market
  knows), cited its site, who it named instead and what it cited. Beside them, the **AI share of voice**
  (how often real ChatGPT and Google AI answers mention the site and each competitor, from DataForSEO's
  LLM Mentions database), what those answers say about the site, the searches Google's AI Overviews cite
  each site for (Labs), and AI search volume beside Google's for each tracked search. Findings flag searches
  the AIs answer without the business, competitors they name more, the sites they lean on, and a share of
  voice far behind; the AI's suggestions are written to get the business named. **What AI cites for the
  topic**: the sites and pages AI answers mention most for the tracked searches, and the site's mentions
  month by month. Settings › Market chooses which AIs to ask.
- **What to write, and when**: searches around the tracked ones worth writing about (volume, difficulty,
  intent, whether it's a question), and **seasonality**: the month each search peaks, so a post goes out two
  months before. A finding flags searches coming into season; each idea is a click from tracking or from the
  content calendar, which suggests the date.
- **A year of history**: each site's estimated visits and keywords month by month (the report backfills its
  chart with it), and each competitor's **best pages**, the ones that bring them the most search traffic.
- **Business Profiles, beyond the listing**: customers' questions (and which are unanswered), each
  business's posts and how often it posts; findings flag unanswered questions and a competitor posting more.
- **Other review sites** (Also pull, off by default): Trustpilot and Tripadvisor reviews beside Google's.
- **Every figure says where it's from** on Search: Google Search Console (real), Google checked live, AI
  answers checked live, the AI answers database, DataForSEO Labs estimates, Google Maps, Business
  Profiles, the site check, web mentions.
- **More from DataForSEO** (Settings › Market › Also pull): keyword facts (volume, AI volume, difficulty,
  intent, CPC, trend), who wins the tracked searches, each site's Google Business Profile side by side
  (rating, reviews, photos, claimed, hours, description, categories), the home page's health (rendered as
  Google does, and Lighthouse on a phone), and web mentions with their tone. The questions people also ask
  and the map pack come with each Google check. **Test mode** pulls from DataForSEO's free sandbox.
- **Google reviews** (Also pull): the latest 50 of the site (with the other sites' reviews Google shows) and
  of each competitor, from DataForSEO's queue; they arrive a few minutes after the pull. The AI reads them
  for what customers praise and complain about, with advice for the business; Search shows the rating,
  pace, share answered, and the unanswered ones to answer; findings flag unanswered reviews, a competitor
  getting reviews faster, and recurring complaints.
- **Searches a month in the business's city** (keyword facts): Google Ads' volume and cost per click for
  each tracked search where the business is, its city found once in Google Ads' locations from the profile.
- **Links** (Search › Links; Settings › Market › Backlinks too, DataForSEO's Backlinks subscription): each
  site's linking sites over the year, new and lost, followed share, links to missing pages and rank; then,
  in the order worth doing them:
  - **win back** links to pages that no longer answer: each old address with the sites linking to it, and
    a **redirect in one click** to the page that replaced it (a 301 in Tools › Redirects; it takes
    `redirects:write`); and good links lost in the last 90 days, to ask for back;
  - **who links** to the site, best first (followed or not, spammy-looking), and **the words** they link
    with: the business's name, its address, "click here", a search it wants to win, or other;
  - **where to get more**: the sites linking to competitors but not to the site, the competitors' pages that
    earn the most links, and sites with a link profile like the site's (watch them in a click).

  Findings flag links to missing pages, good links lost, a competitor winning links faster, too many
  exact-match anchors (or too few by name), spammy linking sites (with when disavowing is worth it), the
  link gap and pages that earn competitors links. **Plan the outreach with AI** turns it into tasks (who to
  ask, what to ask for) and posts worth linking to. A goal can be **sites linking to the site**. The profile
  and year are pulled each time; the detail on the site's own links weekly.
- **Local search** works from a ZIP (or postcode) and a radius in miles (Market › Profile), not the whole
  country. On every pull, each tracked search is checked on Google Maps from a grid of points across the
  area (3×3, 5×5 or 7×7). **Search › Local** lists the searches beside the open one: its grid laid on a map of the area (OpenStreetMap), with the business's
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

    cms get /api/market                                         # at a glance: goals, do_next, setup, findings by severity, best opportunities, changes
    cms get /api/market/links                                   # profiles, who links in, won and lost, broken (and if redirected), anchors, link gap
    cms get /api/market/goals                                   # the goals with progress and pace, and the metrics there are
    cms post /api/market/goals '{"goal":{"metric":"calls","target":40,"due_on":"2027-01-31"}}'
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
