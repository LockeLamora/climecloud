# frozen_string_literal: true

require 'article_rules'
require 'net/http'
require 'nokogiri'

module Scraper
  # A reader on a slow connection is already waiting. Without these a single unresponsive
  # publisher held a worker for forty two seconds, and once for two minutes before dying.
  OPEN_TIMEOUT_SECONDS = 5
  READ_TIMEOUT_SECONDS = 8
  # Publishers redirect between editions, to AMP, and to consent pages. Enough to follow
  # the ordinary ones without chasing a loop.
  MAX_REDIRECTS = 3
  SEPARATOR = '<br /><br />'
  # Furniture that sits inside the article container as often as outside it, and was being
  # read as part of the story. The class matches are for paid placements, which are written
  # in full sentences and so survive every other filter: equity release, "browse radios and
  # music centres", "less scrolling, more great TV".
  # The accessibility-only entries are there because text meant for a screen reader is
  # still text: one publisher spells its quotation marks out in hidden spans, so an article
  # arrived reading `he said double quotation mark the budget is fine`. Nothing here
  # rewrites a quote — typed, &quot; and curly all survive — those were the page's own words.
  BOILERPLATE = [
    'script, style, noscript, nav, header, footer, aside, form, figcaption, iframe',
    '[class*="promo"], [class*="advert"], [class*="sponsor"], [class*="partner"]',
    '[class*="affiliate"], [class*="newsletter"], [class*="related"], [class*="recommend"]',
    '[id*="advert"], [id*="promo"]',
    '[aria-hidden="true"], .sr-only, .visually-hidden, .visuallyhidden',
    '.screen-reader-text, .screen-reader-only, .assistive-text'
  ].join(', ').freeze
  # Where an article usually sits, tried in order. Without this the fallback was every
  # paragraph on the page, which meant cookie notices, related story teasers and the
  # footer arrived as prose on a 240 pixel screen.
  CONTAINERS = ['article', '[itemprop="articleBody"]', 'main', '.article-body',
                '.article__body', '.story-body', '.post-content', '.entry-content'].freeze
  # Bylines, datelines, photo captions and "Share this" are all shorter than a sentence.
  MIN_PARAGRAPH_LENGTH = 40

  # Anything the network can raise on the way to a page we do not control. Left
  # unrescued, each of these was a 500 rather than a page saying it could not be opened.
  NETWORK_ERRORS = [
    Net::ReadTimeout, Net::OpenTimeout, EOFError, SocketError, Errno::ECONNRESET,
    Errno::ECONNREFUSED, Errno::EHOSTUNREACH, OpenSSL::SSL::SSLError, URI::InvalidURIError
  ].freeze

  # Returns the article text, or the reason it could not be given. One fetch: the page
  # used to be requested twice, once to check the status and again to read it, and the
  # status was checked on the URL before redirects rather than the page finally served.
  # That let a 403 through on a site that redirected elsewhere.
  def self.scrape_article(url, useragent)
    response = fetch(url, useragent)
    return { error: I18n.t('news.cannot_load') } if response.nil?

    text = extract_text(response.body, response.uri.to_s)
    if text.blank?
      # Logged because it was not: a page that loads and yields no paragraphs took this
      # path silently, so there was no way to tell how often the CSS rules come up empty
      # against a redesign, or which sites need a rule of their own.
      Rails.logger.warn("Cannot parse page - no text matched - url #{response.uri}")
      return { error: I18n.t('news.cannot_parse') }
    end

    { text: text }
  end

  # Redirects are followed here rather than by the parser, so the status of the page
  # actually served is the one that decides whether there is anything to read.
  def self.fetch(url, useragent, redirects = 0)
    response = get(url, useragent)
    return nil if response.nil?

    if response.is_a?(Net::HTTPRedirection) && redirects < MAX_REDIRECTS
      location = response['location']
      return nil if location.blank?

      return fetch(URI.join(url, location).to_s, useragent, redirects + 1)
    end

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("Cannot load page - response #{response.code} - url #{url}")
      return nil
    end

    response
  end

  def self.get(url, useragent)
    address = URI(url)
    request = Net::HTTP::Get.new(address, { 'user-agent' => useragent })

    Net::HTTP.start(address.host, address.port,
                    use_ssl: address.scheme == 'https',
                    open_timeout: OPEN_TIMEOUT_SECONDS,
                    read_timeout: READ_TIMEOUT_SECONDS) do |http|
      http.request(request)
    end
  rescue *NETWORK_ERRORS => e
    Rails.logger.warn("Cannot reach page - #{e.class}: #{e.message} - url #{url}")
    nil
  end

  def self.extract_text(body, url)
    document = Nokogiri::HTML(body)

    # Read before the boilerplate is stripped, because it lives in a script tag.
    structured = readable(structured_body(document))
    return structured.join(SEPARATOR) if structured.any?

    document.css(BOILERPLATE).each(&:remove)
    from_markup(document, url).join(SEPARATOR)
  rescue StandardError => e
    Rails.logger.warn("Cannot parse page - #{e.class}: #{e.message} - url #{url}")
    nil
  end

  # The schema.org articleBody most publishers embed for search engines. It is the story
  # without the furniture, so it beats anything guessed from the markup.
  def self.structured_body(document)
    document.css('script[type="application/ld+json"]').each do |script|
      body = article_body(JSON.parse(script.text))
      return body.split(/\n+/) if body.present?
    rescue JSON::ParserError
      next
    end

    []
  end

  # Publishers nest it differently: a bare object, a list of them, or under @graph.
  def self.article_body(data)
    case data
    when Array then data.filter_map { |entry| article_body(entry) }.first
    when Hash
      return data['articleBody'] if data['articleBody'].is_a?(String)

      article_body(data['@graph']) if data['@graph']
    end
  end

  def self.from_markup(document, url)
    paragraphs = candidates(document, url)
    text = readable(paragraphs)
    # Some articles really are a handful of one line paragraphs, so a filter that leaves
    # nothing behind hands back what it was given rather than an empty page.
    text.any? ? text : tidy(paragraphs).uniq
  end

  # A rule written for the domain wins, then the containers an article usually sits in.
  # There is deliberately no fallback to every paragraph on the page: doing that put
  # advertising on screen dressed as the story, and saying the page could not be read is
  # worth more than that. The log line names the site, so a rule can be written for it.
  def self.candidates(document, url)
    rule = ArticleRules.for(url)
    return document.css(rule).map(&:text) unless rule == ArticleRules::DEFAULT

    CONTAINERS.each do |container|
      found = document.css("#{container} #{ArticleRules::DEFAULT}").map(&:text)
      return found if tidy(found).any?
    end

    []
  end

  def self.readable(paragraphs)
    tidy(paragraphs).reject { |text| text.length < MIN_PARAGRAPH_LENGTH }.uniq
  end

  # Newspaper markup is full of line breaks and indentation that arrive as whitespace.
  def self.tidy(paragraphs)
    paragraphs.to_a.map { |text| text.to_s.gsub(/\s+/, ' ').strip }.reject(&:blank?)
  end
end
