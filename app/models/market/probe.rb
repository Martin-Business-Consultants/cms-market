# frozen_string_literal: true

require "resolv"
require "ipaddr"
require "net/http"

module Market
  # What a business's website says about how it markets itself, read from outside like any
  # visitor: its home page (title, headings, what it runs: ad and analytics tags, call tracking,
  # chat, reviews, booking; its structured data and social profiles) and its sitemap (how many
  # pages, how many are posts, locations and services, and how recently they changed). Every
  # part fails on its own, as an `error` in its facts. Only public addresses are fetched.
  class Probe
    TIMEOUT = 8
    MAX_BODY = 5.megabytes
    MAX_REDIRECTS = 5
    MAX_CHILD_SITEMAPS = 5
    USER_AGENT = "Libre Publish market check"

    class Refused < StandardError; end

    # What runs on a page, by what its markup includes.
    TOOLS = {
      "google_ads" => ["Google Ads", /\bAW-\d{6,}\b|googleadservices\.com/],
      "google_analytics" => ["Google Analytics", /\bG-[A-Z0-9]{6,12}\b|google-analytics\.com/],
      "tag_manager" => ["Google Tag Manager", /\bGTM-[A-Z0-9]{4,10}\b/],
      "meta_pixel" => ["Meta Pixel", /connect\.facebook\.net\/[^"']*fbevents|fbq\(\s*['"]init/],
      "tiktok_pixel" => ["TikTok Pixel", /analytics\.tiktok\.com/],
      "linkedin_insight" => ["LinkedIn Insight", /snap\.licdn\.com|_linkedin_partner_id/],
      "microsoft_ads" => ["Microsoft Ads (UET)", /bat\.bing\.com/],
      "call_tracking" => ["Call tracking", /callrail|calltrackingmetrics|invoca|whatconverts/i],
      "chat" => ["Chat", /intercom|driftt?\.com|tawk\.to|livechatinc|podium|tidio|hubspot\.com\/conversations|crisp\.chat/i],
      "reviews_widget" => ["Reviews widget", /birdeye|trustpilot|elfsight|reviews\.io|yotpo|grade\.us|nicejob/i],
      "booking" => ["Online booking", /calendly|housecallpro|servicetitan|acuityscheduling|squareup\.com\/appointments|booksy|vagaro/i],
      "email_capture" => ["Email signup", /klaviyo|mailchimp|list-manage\.com|convertkit|constantcontact/i],
      "consent_banner" => ["Consent banner", /cookiebot|onetrust|termly|iubenda|cookieyes|osano/i]
    }.freeze

    SOCIALS = {
      "facebook" => %r{https?://(?:www\.)?facebook\.com/(?!sharer|share|tr\b|plugins|dialog)[\w.\-/]+}i,
      "instagram" => %r{https?://(?:www\.)?instagram\.com/[\w.\-]+}i,
      "linkedin" => %r{https?://(?:www\.)?linkedin\.com/(?:company|in)/[\w.\-]+}i,
      "youtube" => %r{https?://(?:www\.)?youtube\.com/(?:@|c/|channel/|user/)[\w.\-]+}i,
      "tiktok" => %r{https?://(?:www\.)?tiktok\.com/@[\w.\-]+}i,
      "x" => %r{https?://(?:www\.)?(?:twitter|x)\.com/(?!share|intent)[\w]+}i,
      "pinterest" => %r{https?://(?:www\.)?pinterest\.com/[\w.\-]+}i,
      "google_business" => %r{https?://(?:g\.page/[\w.\-]+|maps\.app\.goo\.gl/\w+|(?:www\.)?google\.com/maps/place/[^"'\s]+)}i
    }.freeze

    SOCIAL_LABELS = {"facebook" => "Facebook", "instagram" => "Instagram", "linkedin" => "LinkedIn", "youtube" => "YouTube", "tiktok" => "TikTok",
                      "x" => "X", "pinterest" => "Pinterest", "google_business" => "Google Business Profile"}.freeze

    # Sitemap addresses by what they're likely to be.
    SECTIONS = {
      "posts" => %r{/(blog|news|articles?|insights|resources|posts|guides|learn)/[^/]+}i,
      "locations" => %r{/(locations?|areas?|service-areas?|cities|city|near-me)/[^/]+|-near-me\b}i,
      "services" => %r{/(services?|solutions|what-we-do|products?)/[^/]+}i
    }.freeze

    # "https://www.Example.com/about" → "example.com"
    def self.normalize(input)
      text = input.to_s.strip.downcase
      return nil if text.empty?

      host = URI.parse(text.include?("://") ? text : "https://#{text}").host.to_s
      host.delete_prefix("www.").presence || text
    rescue URI::InvalidURIError
      text
    end

    attr_reader :domain

    def initialize(domain, today: Date.current)
      @domain = self.class.normalize(domain)
      @today = today
    end

    def facts
      @facts ||= {"domain" => domain, "home_page" => part { home_page }, "sitemap" => part { sitemap }}
    end

    # The home page's facts from its markup: public so it can be checked without the network.
    def read_home(html, url: "https://#{domain}/", headers: {})
      text = html.to_s
      {
        "url" => url,
        "title" => text[%r{<title[^>]*>(.*?)</title>}mi, 1]&.then { squish(CGI.unescapeHTML(it)) }&.truncate(150),
        "description" => meta(text, "description")&.then { squish(CGI.unescapeHTML(it)) }&.truncate(250),
        "headings" => text.scan(%r{<h1[^>]*>(.*?)</h1>}mi).flatten.map { squish(strip_tags(it)) }.reject(&:empty?).first(3),
        "platform" => platform(text, headers),
        "tools" => TOOLS.filter_map { |key, (_label, pattern)| key if text.match?(pattern) },
        "socials" => SOCIALS.to_h { |key, pattern| [key, text[pattern]] }.compact,
        "schema_types" => schema_types(text),
        "phone_numbers" => text.scan(/href=["']tel:([^"']+)["']/i).flatten.map { it.gsub(/\D/, "") }.uniq { it.last(10) }.first(3),
        "forms" => text.scan(/<form\b/i).size,
        "words" => strip_tags(text.gsub(%r{<(script|style)\b.*?</\1>}mi, " ")).split.size
      }.compact
    end

    # What a sitemap's addresses (with their lastmod dates, or nil) say about the site.
    def read_sitemap(entries, url:)
      dates = entries.filter_map { |_, date| date }
      sections = SECTIONS.to_h { |key, pattern| [key, entries.count { |loc, _| loc.match?(pattern) }] }
      recent = entries.count { |loc, date| date && date >= @today - 90 && loc.match?(SECTIONS["posts"]) }
      {"url" => url, "pages" => entries.size, **sections, "posts_last_90_days" => recent,
        "last_changed" => dates.max&.iso8601, "sample" => entries.first(8).map(&:first)}
    end

    # The readable words on a page of the site (a path or a full address on its
    # domain), without its scripts, styles, navigation and footer, cut to `words`:
    # what the AI reads to fill in a profile. Nil when it can't be read.
    def page_text(path_or_url, words: 1200)
      url = path_or_url.to_s.match?(%r{\Ahttps?://}) ? path_or_url.to_s : "https://#{domain}/#{path_or_url.to_s.delete_prefix("/")}"
      return unless self.class.normalize(url) == domain

      response = follow(url)
      return unless response[:status] == 200

      text_of(response[:body]).split.first(words).join(" ").presence
    end

    def text_of(html)
      body = html.to_s.gsub(%r{<(script|style|noscript|svg|nav|footer|header)\b.*?</\1>}mi, " ")
      squish(strip_tags(body))
    end

    private

    def part
      yield
    rescue => error
      {"error" => "#{error.class.name.demodulize}: #{error.message}".truncate(200)}
    end

    def home_page
      response = follow("https://#{domain}/")
      raise response[:error] || "answered #{response[:status]}" unless response[:status] == 200

      read_home(response[:body], url: response[:url], headers: response[:headers] || {})
    end

    def sitemap
      candidates = (robots_sitemaps + %W[https://#{domain}/sitemap.xml https://#{domain}/sitemap_index.xml]).uniq
      candidates.each do |url|
        response = follow(url)
        next unless response[:status] == 200 && response[:body].to_s.include?("<loc")

        body = response[:body].to_s
        facts = read_sitemap(entries_from(body), url: response[:url])
        return facts unless body.include?("<sitemapindex")

        total = body.scan(/<sitemap>/i).size
        return facts.merge("sitemaps" => total, "sitemaps_read" => [total, MAX_CHILD_SITEMAPS].min)
      end
      raise "none found at #{candidates.join(", ")}"
    end

    def robots_sitemaps
      response = follow("https://#{domain}/robots.txt")
      response[:status] == 200 ? response[:body].to_s.scan(/^\s*sitemap:\s*(\S+)/i).flatten.uniq.first(3) : []
    end

    # A sitemap's [address, lastmod] pairs; an index's from its first few sitemaps.
    def entries_from(body)
      pairs = body.scan(%r{<(?:url|sitemap)>(.*?)</(?:url|sitemap)>}mi).flatten.filter_map do |block|
        loc = block[%r{<loc>\s*(.*?)\s*</loc>}mi, 1] or next
        [CGI.unescapeHTML(loc), (Date.parse(block[%r{<lastmod>\s*(.*?)\s*</lastmod>}mi, 1].to_s) rescue nil)]
      end
      return pairs unless body.include?("<sitemapindex")

      pairs.first(MAX_CHILD_SITEMAPS).flat_map do |url, _|
        response = follow(url)
        response[:status] == 200 ? entries_from(response[:body].to_s) : []
      end
    end

    def meta(html, name)
      html[/<meta[^>]+(?:name|property)=["']#{Regexp.escape(name)}["'][^>]*content=["']([^"']*)["']/i, 1] ||
        html[/<meta[^>]+content=["']([^"']*)["'][^>]*(?:name|property)=["']#{Regexp.escape(name)}["']/i, 1]
    end

    def platform(html, headers)
      generator = meta(html, "generator").to_s
      return generator.split.first(2).join(" ") if generator.present?
      return "WordPress" if html.include?("wp-content")
      return "Shopify" if html.include?("cdn.shopify.com")
      return "Wix" if html.include?("wixstatic.com")
      return "Squarespace" if html.include?("squarespace")
      return "Webflow" if html.include?("webflow")
      return "Duda" if html.include?("dudamobile") || html.include?("multiscreensite")
      return "GoDaddy" if html.include?("godaddy") || html.include?("img1.wsimg.com")
      return "Next.js" if html.include?("/_next/")
      return "Astro" if html.include?("/_astro/")

      "Vercel" if headers["server"].to_s.casecmp?("vercel")
    end

    def schema_types(html)
      html.scan(%r{<script[^>]+application/ld\+json[^>]*>(.*?)</script>}mi).flatten.flat_map do |json|
        types_in(JSON.parse(json))
      rescue JSON::ParserError
        []
      end.uniq.first(12)
    end

    def types_in(node)
      case node
      when Array then node.flat_map { types_in(it) }
      when Hash then Array(node["@type"]) + types_in(node["@graph"]) + node.except("@type", "@graph").values.select { it.is_a?(Hash) || it.is_a?(Array) }.flat_map { types_in(it) }
      else []
      end
    end

    def strip_tags(html) = html.gsub(/<[^>]+>/, " ").then { CGI.unescapeHTML(it) }
    def squish(text) = text.gsub(/\s+/, " ").strip

    def follow(url, accept: "*/*")
      hops = []
      MAX_REDIRECTS.times do
        response = fetch(url, accept: accept)
        return response.merge(url: url, hops: hops) unless response[:status].to_i.between?(300, 399) && response[:location]

        hops << "#{response[:status]} → #{response[:location]}"
        url = URI.join(url, response[:location]).to_s
      end
      {status: nil, url: url, hops: hops, error: "too many redirects"}
    rescue Refused, StandardError => error
      {status: nil, url: url, hops: hops, error: "#{error.class.name.demodulize}: #{error.message}".truncate(160)}
    end

    def fetch(url, accept: "*/*")
      uri = URI.parse(url)
      raise Refused, "only http and https" unless uri.is_a?(URI::HTTP)
      refuse_private!(uri.host)

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: TIMEOUT, read_timeout: TIMEOUT, ssl_timeout: TIMEOUT) do |http|
        request = Net::HTTP::Get.new(uri, "User-Agent" => USER_AGENT, "Accept" => accept)
        http.request(request) do |response|
          body = +""
          response.read_body { |chunk| body << chunk if body.bytesize < MAX_BODY }
          return {status: response.code.to_i, location: response["location"], body: body.byteslice(0, MAX_BODY).force_encoding(Encoding::UTF_8).scrub,
                   headers: response.each_header.to_h}
        end
      end
    end

    def refuse_private!(host)
      addresses = Resolv.getaddresses(host)
      raise Refused, "#{host} doesn't resolve" if addresses.empty?
      if addresses.any? { |address| ip = IPAddr.new(address); ip.private? || ip.loopback? || ip.link_local? || address.start_with?("0.") }
        raise Refused, "#{host} is a private address"
      end
    end
  end
end
