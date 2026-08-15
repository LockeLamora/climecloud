# frozen_string_literal: true

require 'net/http'
require 'uri'

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
    @useragent = params.delete(:useragent) || 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko)'\
     'Chrome/122.0.0.0 Safari/537.36'
  end

  def change_section(section)
    @section = section
  end

  def get_useragent
    @useragent
  end

  def get_article(url)
    res = Net::HTTP.get_response(URI(url), { 'user-agent' => @useragent })
    while res.code.start_with?('3')
      res = Net::HTTP.get_response(URI(res.to_hash['location'][0]), { 'user-agent' => @useragent })
    end

    timestamp = get_timestamp(res.body)
    signature = get_signature(res.body)
    # Google serves a consent page instead of the article to some clients, which has
    # neither value in it. Better to say we cannot open it than to die on a nil.
    return nil if timestamp.nil? || signature.nil?

    url.gsub!('https://news.google.com/rss/articles/', '')
    url.gsub!('?oc=5', '')
    rss_to_url(url, timestamp, signature)
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
  # shares, so a 429 here is nothing the reader in front of it did. A relay fetches the
  # feed once more from a different address.
  #
  # Only the feed. Opening an article takes a scrape of Google's own page for two data
  # attributes and then a POST to resolve the link, and none of the relays carry a POST.
  def fetch_feed(uri)
    res = Net::HTTP.get_response(uri)
    res = Net::HTTP.get_response(URI.parse(res['location'])) if res.code.start_with?('3')
    return feed_in(res.body) if res.is_a?(Net::HTTPSuccess)

    Rails.logger.warn("News feed refused by google - #{res.code}")
    return nil unless res.code == Relay::RATE_LIMITED

    Relay.fetch(uri, subject: 'News feed') { |body| feed_in(body) }
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
    uri = 'https://news.google.com/_/DotsSplashUi/data/batchexecute' # ?rpcids=Fbv4je"
    req = '[[["Fbv4je","[\"garturlreq\",[[\"en-GB\",\"GB\",[\"FINANCE_TOP_INDICES\",\"WEB_TEST_1_0_0\"],null,null,1,1,\"GB:en\",null,0,null,null,null,null,null,0,5],\"en-GB\",\"GB\",1,[2,4,8],1,1,\"691331303\",0,0,null,0],\"' + url + '\",' + timestamp + ',\"' + signature + '\"]",null,"generic"]]]'
    res = Net::HTTP.post_form URI(uri), { 'f.req' => req }
    resolved_url(res.body)
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
