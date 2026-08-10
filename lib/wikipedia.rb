# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'cgi'

class Wikipedia
  ENDPOINT = 'https://en.wikipedia.org/w/api.php'
  # Wikimedia throttles callers it cannot identify to a tenth of the normal
  # allowance, and this app shares an outbound address with everything else on the
  # host. Naming ourselves with a contact URL is the difference between 10 and 200
  # requests a minute, so this header is not optional politeness.
  USER_AGENT = 'climecloud/1.0 (https://clime.cloud)'
  # One per number key, so every result can be opened with a single press.
  MAX_RESULTS = 9
  # The API caps an extract at 1200 characters, which is about right for a first
  # screenful anyway.
  SUMMARY_CHARS = 1200

  attr_reader :error

  def initialize(params = {})
    @query = params[:query]
    @title = params[:title]
    @full = params[:full]
  end

  def search
    return [] if @query.blank?

    body = fetch(search_uri)
    return [] if body.nil?

    results = body.dig('query', 'search') || []
    results.first(MAX_RESULTS).map { |result| result_from(result) }
  end

  def article
    return nil if @title.blank?

    body = fetch(article_uri)
    return nil if body.nil?

    page = (body.dig('query', 'pages') || {}).values.first
    return nil if page.nil? || page['extract'].blank?

    { title: page['title'], extract: page['extract'] }
  end

  private

  def search_uri
    build_uri(action: 'query', list: 'search', srsearch: @query,
              srlimit: MAX_RESULTS, format: 'json')
  end

  # The lead section is what answers "what is this", and asking for the whole article
  # by default would push a lot of text down a 4G connection unasked.
  def article_uri
    params = { action: 'query', prop: 'extracts', explaintext: 1,
               titles: @title, redirects: 1, format: 'json' }

    unless @full
      params[:exintro] = 1
      params[:exchars] = SUMMARY_CHARS
    end

    build_uri(params)
  end

  def build_uri(params)
    uri = URI(ENDPOINT)
    uri.query = URI.encode_www_form(params)
    uri
  end

  def fetch(uri)
    res = Net::HTTP.get_response(uri, { 'user-agent' => USER_AGENT })
    unless res.is_a?(Net::HTTPSuccess)
      @error = if res.code == '429'
                 'Wikipedia is busy just now, please try again shortly'
               else
                 'Could not reach Wikipedia, please try again later'
               end
      return nil
    end

    JSON.parse(res.body)
  rescue JSON::ParserError
    @error = 'Could not read the reply from Wikipedia'
    nil
  end

  def result_from(result)
    { title: result['title'], snippet: plain_text(result['snippet']) }
  end

  # Search snippets arrive with match highlighting markup in them, which is no use
  # on a screen this size.
  def plain_text(html)
    CGI.unescapeHTML(html.to_s.gsub(/<[^>]*>/, '')).squeeze(' ').strip
  end
end
