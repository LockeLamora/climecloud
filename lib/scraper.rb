# frozen_string_literal: true

require 'article_rules'
require 'net/http'
require 'nokogiri'

module Scraper
  # A reader on a slow connection is already waiting, so an unresponsive publisher gets a
  # few seconds and no more, rather than holding a worker for as long as it likes.
  OPEN_TIMEOUT_SECONDS = 5
  READ_TIMEOUT_SECONDS = 8
  # Publishers redirect between editions, to AMP, and to consent pages. Enough to follow
  # the ordinary ones without chasing a loop.
  MAX_REDIRECTS = 3
  SEPARATOR = '<br /><br />'
  # Furniture that sits inside the article container as often as outside it. The class
  # matches catch paid placements, which are written in full sentences and so pass every
  # other filter: equity release, "browse radios and music centres", "less scrolling, more
  # great TV".
  #
  # The accessibility entries are here because text meant for a screen reader is still
  # text, and some publishers spell their punctuation out in hidden spans. Quotation marks
  # themselves are untouched: typed, &quot; and curly all come through as written.
  BOILERPLATE = [
    'script, style, noscript, nav, header, footer, aside, form, figcaption, iframe',
    '[class*="promo"], [class*="advert"], [class*="sponsor"], [class*="partner"]',
    '[class*="affiliate"], [class*="newsletter"], [class*="related"], [class*="recommend"]',
    '[id*="advert"], [id*="promo"]',
    '[aria-hidden="true"], .sr-only, .visually-hidden, .visuallyhidden',
    '.screen-reader-text, .screen-reader-only, .assistive-text'
  ].join(', ').freeze
  # Where an article usually sits, tried in order. Narrowing to these keeps cookie
  # notices, story teasers and the footer off a 240 pixel screen.
  CONTAINERS = ['article', '[itemprop="articleBody"]', 'main', '.article-body',
                '.article__body', '.story-body', '.post-content', '.entry-content'].freeze
  # Bylines, datelines, photo captions and "Share this" are all shorter than a sentence.
  MIN_PARAGRAPH_LENGTH = 40

  # Anything the network can raise on the way to a page we do not control. Rescued so the
  # reader gets a page saying it could not be opened, rather than a 500.
  NETWORK_ERRORS = [
    Net::ReadTimeout, Net::OpenTimeout, EOFError, SocketError, Errno::ECONNRESET,
    Errno::ECONNREFUSED, Errno::EHOSTUNREACH, OpenSSL::SSL::SSLError, URI::InvalidURIError
  ].freeze

  # Returns the article text, or the reason it could not be given. One fetch, and the
  # status that decides is the one from the page finally served after redirects.
  def self.scrape_article(url, useragent)
    response = fetch(url, useragent)
    return { error: I18n.t('news.cannot_load') } if response.nil?

    text = extract_text(response.body, response.uri.to_s)
    if text.blank?
      # Logged with the URL, so a redesign that empties the CSS rules is visible in the
      # log and the site can be given a rule of its own.
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

  # The headers a browser sends when a person follows a link. Some publishers' edges (ITV
  # among them) refuse a request that carries a browser's user-agent without the rest of a
  # browser's headers, killing the connection rather than answering it, so the whole set
  # travels together.
  BROWSER_HEADERS = {
    'accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'accept-language' => 'en-GB,en;q=0.9',
    'upgrade-insecure-requests' => '1',
    'sec-fetch-dest' => 'document',
    'sec-fetch-mode' => 'navigate',
    'sec-fetch-site' => 'none'
  }.freeze

  def self.get(url, useragent)
    address = URI(url)
    request = Net::HTTP::Get.new(address, BROWSER_HEADERS.merge('user-agent' => useragent))

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
    # nothing behind falls back to the unfiltered set rather than an empty page.
    text.any? ? text : tidy(paragraphs).uniq
  end

  # A rule written for the domain wins, then the containers an article usually sits in.
  # Nothing falls back to every paragraph on the page: that puts advertising on screen
  # dressed as the story, and saying the page could not be read is worth more. The log line
  # names the site, so a rule can be written for it.
  def self.candidates(document, url)
    rule = ArticleRules.for(url)
    return ruled(document, rule) unless rule == ArticleRules::DEFAULT

    document.css(BOILERPLATE).each(&:remove)
    CONTAINERS.each do |container|
      found = document.css("#{container} #{ArticleRules::DEFAULT}").map(&:text)
      return found if tidy(found).any?
    end

    []
  end

  # A domain rule names where the story sits, so it reads from the document as fetched:
  # the furniture filters match class fragments, and on some sites a fragment sits on an
  # ancestor of the story itself — a layout wrapper called advert__skin, the whole article
  # in an <aside> — which would throw the story out with the adverts. The filters still
  # run inside what the rule selected, where they mean what they say.
  def self.ruled(document, rule)
    document.css(rule).map do |node|
      node.css(BOILERPLATE).each(&:remove)
      node.text
    end
  end

  def self.readable(paragraphs)
    tidy(paragraphs).reject { |text| text.length < MIN_PARAGRAPH_LENGTH }.uniq
  end

  # Newspaper markup is full of line breaks and indentation that arrive as whitespace.
  def self.tidy(paragraphs)
    paragraphs.to_a.map { |text| text.to_s.gsub(/\s+/, ' ').strip }.reject(&:blank?)
  end
end
