# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'relay'

class Gnews
  # The sections Google publishes a feed for, in the order they are offered, named once
  # here and read by both views that list them. The values are what Google's URLs expect;
  # the words shown come from the locale files, so all seventeen languages get their own.
  SECTIONS = %w[HEADLINES WORLD NATION BUSINESS TECHNOLOGY ENTERTAINMENT SCIENCE SPORTS HEALTH].freeze

  def initialize(params = nil)
    resolve_location(params.delete(:country_code))
    resolve_language
    resolve_ceid
    @section = params.delete(:section)
    @useragent = params.delete(:useragent) || 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '\
     'Chrome/122.0.0.0 Safari/537.36'
  end

  def change_section(section)
    @section = section
  end

  def get_useragent
    @useragent
  end

  # Which country-and-language edition the feed is asked for: what a cache of that feed
  # has to be keyed by, so two readers with different editions never share a list.
  def get_ceid
    @ceid
  end

  # Everything here answers inside a few seconds or answers nil, never hangs. A resolve
  # with no timeout and no redirect cap sits for minutes when Google throttles this host's
  # address or walks it through a consent chain, and a page that takes minutes is one the
  # reader is told could not be opened. nil renders in an instant as the titled
  # unavailable page instead, which every browser can open.
  TIMEOUT_SECONDS = 5
  MAX_REDIRECTS = 5

  # Answers the publisher's URL, nil for a failure worth one more try, or :rate_limited
  # for Google's wall — asking direct again into a wall only builds it higher, so the
  # caller must not retry that one. What is worth one more try is the proxy: a dedicated
  # egress address whose reputation is this app's alone, spent only after the shared
  # address is walled so a month's small allowance goes on the mornings that need it.
  def get_article(url)
    res = fetch_article_page(URI(url))
    return :rate_limited if res&.code == Relay::RATE_LIMITED
    return nil unless res.is_a?(Net::HTTPSuccess)

    timestamp = get_timestamp(res.body)
    signature = get_signature(res.body)
    # Google serves a consent page instead of the article stub to some clients, which
    # has neither value in it. Better to say we cannot open it than to die on a nil —
    # but say so in the log too, or a run of these reads as nothing at all.
    if timestamp.nil? || signature.nil?
      Rails.logger.warn('News article stub carried no timestamp/signature - consent or variant page served')
      return nil
    end

    # A copy, not a mutation: the caller retries with the same URL when a resolve fails,
    # and a half-stripped string must not be what the second attempt fetches.
    rss_to_url(url.sub('https://news.google.com/rss/articles/', '').sub('?oc=5', ''),
               timestamp, signature)
  end

  def get_articles_from_api(search_query = nil)
    feed = fetch_feed(build_news_uri(search_query))
    return nil, nil if feed.nil?

    # nil is reserved for a feed we could not fetch, so an empty feed returns a list.
    articles = feed.dig('rss', 'channel', 'item') || []
    title = if !@section.nil? && @section.upcase != 'HEADLINES'
              feed.dig('rss', 'channel', 'title')
            else
              'Headlines - Latest - Google News'
            end
    [articles, title]
  end

  private

  # Google counts its allowance against the calling IP, which every reader on this host
  # shares, so a 429 here is nothing the reader in front of it did. The proxy — a
  # dedicated address whose reputation is this app's alone — fetches the feed once more,
  # and the public relays stay behind it as the last resort they always were.
  def fetch_feed(uri)
    res = Net::HTTP.get_response(uri)
    res = Net::HTTP.get_response(URI.parse(res['location'])) if res.code.start_with?('3')
    return feed_in(res.body) if res.is_a?(Net::HTTPSuccess)

    Rails.logger.warn("News feed refused by google - #{res.code}")
    return nil unless res.code == Relay::RATE_LIMITED

    fetch_feed_via_proxy(uri) ||
      Relay.fetch(uri, subject: 'News feed', impatient: true) { |body| feed_in(body) }
  end

  # One more try through the dedicated address. Anything short of a parseable feed
  # answers nil, and the relay chain gets its turn as before.
  def fetch_feed_via_proxy(uri)
    return nil unless proxy

    Rails.logger.warn('News feed rate limited - retrying via proxy')
    res = get_with_timeout(uri, via: proxy)
    res = get_with_timeout(URI(res['location']), via: proxy) if res&.code&.start_with?('3')
    return nil unless res.is_a?(Net::HTTPSuccess)

    feed_in(res.body)
  end

  # A relay reports its own success rather than Google's, and the first of them rewrites
  # what it fetches into prose, so a 200 proves nothing on its own: the body has to parse
  # as the feed before it is worth anything.
  def feed_in(body)
    feed = JSON.parse(Hash.from_xml(body).to_json)
    return nil unless feed.is_a?(Hash) && feed.dig('rss', 'channel').present?

    feed
  rescue StandardError
    # Hash.from_xml raises out of REXML for anything that is not XML at all, which is
    # exactly what a relay serving its own error page returns.
    nil
  end

  def resolve_location(country_code = 'us')
    supported = %w[gb us in fr au ru]
    @loc = if supported.include? country_code
             country_code
           else
             'us'
           end
  end

  def resolve_language
    locs = {
      'fr' => 'fr',
      'in' => 'hi',
      'us' => 'en-US',
      'gb' => 'en-GB',
      'au' => 'en-AU',
      'ru' => 'ru'
    }

    @language = locs[@loc]
  end

  def resolve_ceid
    c = @loc.upcase
    ceids = {
      'FR' => "#{c}:#{@language}",
      'IN' => "#{c}:#{@language}",
      'US' => "#{c}:en",
      'GB' => "#{c}:en",
      'AU' => "#{c}:en",
      'RU' => "#{c}:#{@language}"
    }

    @ceid = ceids[c]
  end

  def get_signature(html_source)
    match = html_source.match(/data-n-a-sg="([^"]+)"/)
    match ? match[1] : nil
  end

  def get_timestamp(html_source)
    match = html_source.match(/data-n-a-ts="([^"]+)"/)
    match ? match[1] : nil
  end

  def rss_to_url(url, timestamp, signature)
    uri = URI('https://news.google.com/_/DotsSplashUi/data/batchexecute') # ?rpcids=Fbv4je"
    req = '[[["Fbv4je","[\"garturlreq\",[[\"en-GB\",\"GB\",[\"FINANCE_TOP_INDICES\",\"WEB_TEST_1_0_0\"],null,null,1,1,\"GB:en\",null,0,null,null,null,null,null,0,5],\"en-GB\",\"GB\",1,[2,4,8],1,1,\"691331303\",0,0,null,0],\"' + url + '\",' + timestamp + ',\"' + signature + '\"]",null,"generic"]]]'
    res = batchexecute(uri, req)
    if res.code == Relay::RATE_LIMITED
      Rails.logger.warn("News article resolve rate limited#{proxy ? ' - retrying via proxy' : ' and no proxy configured'}")
      res = batchexecute(uri, req, via: proxy) if proxy
    end
    # Only a body Google answered with 200 is worth parsing. The rate-limit wall is a
    # page of links, and the fallback parse below used to fish the wall's own URL out of
    # it and hand that back as "the article" — which was then scraped, 429ed, and shown
    # to the reader as a source link to a captcha.
    return :rate_limited if res.code == Relay::RATE_LIMITED
    return nil unless res.is_a?(Net::HTTPSuccess)

    keep_off_google(resolved_url(res.body))
  rescue StandardError => e
    Rails.logger.warn("News article resolve refused - #{e.class}")
    nil
  end

  # Direct first, and once more through the proxy when the shared address is walled.
  # The wall is logged whether or not a proxy is there to answer it: a run of quiet
  # failures with no line saying why is how this went undiagnosed once already.
  def fetch_article_page(uri)
    res = follow_redirects(get_with_timeout(uri))
    return res unless res&.code == Relay::RATE_LIMITED

    Rails.logger.warn("News article stub rate limited#{proxy ? ' - retrying via proxy' : ' and no proxy configured'}")
    return res unless proxy

    follow_redirects(get_with_timeout(uri, via: proxy), via: proxy)
  end

  def batchexecute(uri, req, via: nil)
    Net::HTTP.start(uri.host, uri.port, *proxy_args(via), use_ssl: true,
                                                          open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) do |http|
      http.request(Net::HTTP::Post.new(uri).tap { |post| post.set_form_data('f.req' => req) })
    end
  end

  # Any ordinary HTTP proxy URL — a tinyproxy on a rented box works the same as the
  # add-ons. Read from the credentials file like the other keys, or from FIXIE_URL,
  # which is the variable the proxy add-ons inject on their own. Absent in development
  # and until one is provisioned, and everything above behaves as if the fallback did
  # not exist.
  def proxy
    @proxy ||= begin
      url = Rails.application.credentials.fixie&.url.presence || ENV['FIXIE_URL'].presence
      url && URI(url)
    end
  end

  def proxy_args(via)
    via ? [via.host, via.port, via.user, via.password] : []
  end

  # A resolved article lives on a publisher's site by definition, so anything still on
  # a Google host is some interstitial fished out of a page that was not the answer.
  # Every rejection is logged: a silent nil here renders as "could not open this
  # article" with nothing in the log to say why.
  def keep_off_google(resolved)
    if resolved.blank?
      Rails.logger.warn('News article resolve answered 200 with no URL in it')
      return nil
    end
    if URI(resolved).host&.end_with?('google.com')
      Rails.logger.warn("News article resolved to a google host, not a publisher - #{URI(resolved).host}")
      return nil
    end

    resolved
  rescue URI::InvalidURIError
    Rails.logger.warn('News article resolved to an unparseable URL')
    nil
  end

  # A few steps and no further: an uncapped chain is how a consent loop holds a page open
  # for minutes. The chain stays on whichever route it started — a proxied attempt that
  # hopped back to the walled address mid-chain would be the direct attempt again.
  def follow_redirects(res, via: nil)
    MAX_REDIRECTS.times do
      break unless res&.code&.start_with?('3')

      res = get_with_timeout(URI(res.to_hash['location'][0]), via: via)
    end
    res
  end

  # One request that answers inside the timeout or answers nil; the rescue covers DNS,
  # connection and read failures alike, all of which mean the same thing to the reader.
  def get_with_timeout(uri, via: nil)
    Net::HTTP.start(uri.host, uri.port, *proxy_args(via), use_ssl: uri.scheme == 'https',
                                                          open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) do |http|
      http.request(Net::HTTP::Get.new(uri, { 'user-agent' => @useragent }))
    end
  rescue StandardError => e
    Rails.logger.warn("News article fetch failed - #{e.class}")
    nil
  end

  # The URL arrives inside a JSON string inside a JSON array, behind a few characters of
  # anti-hijacking padding, so it is parsed out rather than pattern matched: URI.extract
  # stops at the first character it does not recognise and truncates a query string.
  # It stays as the fallback for a response this parse cannot read.
  def resolved_url(body)
    payload = JSON.parse(body.sub(/\A[^\[]*/, ''))
    nested = payload.flatten.compact.find { |part| part.is_a?(String) && part.include?('http') }

    JSON.parse(nested).flatten.find { |part| part.to_s.start_with?('http') }
  rescue JSON::ParserError, TypeError
    URI.extract(body, %w[http https]).first
  end

  def build_news_uri(search_query = nil)
    URI('https://news.google.com/rss')
    params = {
      hl: @language,
      gl: @loc.upcase,
      ceid: @ceid
    }
    uri = nil

    if search_query
      uri = URI('https://news.google.com/rss/search')
      params[:q] = search_query
    elsif !@section.nil? && @section.upcase != 'HEADLINES'
      uri = URI("https://news.google.com/rss/headlines/section/topic/#{@section.upcase}")
    else
      uri = URI('https://news.google.com/rss')
    end
    uri.query = URI.encode_www_form(params)
    uri
  end
end
