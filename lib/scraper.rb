# frozen_string_literal: true

require 'wombat'
require 'domainatrix'
require 'net/http'

module Scraper
  def self.scrape_article(url, useragent)
    res = Net::HTTP.get_response(URI(url), { 'user-agent' => useragent })
    unless res.code.start_with?('2', '3')
      Rails.logger.warn("Cannot load page - response #{res.code} - url #{url}")
      return I18n.t('news.cannot_load')
    end

    rule = resolve_article_rules(url)

    # Wombat joins base_url and path, so passing the whole article URL as the base
    # with a path of "/" appended a trailing slash and asked for a page that does not
    # exist. Split the URL instead and hand it the two halves it expects.
    address = URI(url)
    host = "#{address.scheme}://#{address.host}"
    route = address.path.presence || '/'
    route = "#{route}?#{address.query}" if address.query.present?

    begin
      Wombat.set_user_agent(useragent)
      out = Wombat.crawl do
        base_url host
        path route
        text({ css: rule }, :list)
      end
    rescue StandardError => e
      Rails.logger.warn("Cannot parse page - #{e.class}: #{e.message} - url #{url}")
      return I18n.t('news.cannot_parse')
    end

    return I18n.t('news.cannot_parse') if out['text'].blank?

    out['text'].join('<br /><br />')
  end

  def self.resolve_article_rules(url)
    parsedurl = Domainatrix.parse(url)
    domain = "#{parsedurl.domain}.#{parsedurl.public_suffix}"

    rules = {
      'cnbc.com' => '.PageBuilder-article p',
      'independent.co.uk' => '#main p',
      'cnn.com' => '.article__content p',
      'politicshome.com' => '.newsview p',
      'gov.uk' => '.news-article p',
      'itv.com' => '#main-content p',
      'newscientist.com' => '.ArticleContent p',
      'dailymail.co.uk' => "[itemprop='articleBody'] p",
      'indiatimes.com' => '.clearfix *',
      'politico.eu' => '.article__content p',
      'dailyrecord.co.uk' => '.article-body p',
      'foxnews.com' => '.article-body p',
      'iflscience.com' => '.article-content p',
      'nytimes.com' => '.StoryBodyCompanionColumn p',
      'businessinsider.com' => '.content-lock-content p',
      'usatoday.com' => '.content-well p',
      'cbsnews.com' => '.content__body p',
      'nypost.com' => '.entry-content p',
      'ynetnews.com' => '.public-DraftEditor-content',
      'pbs.org' => '.body-text p',
      'telegraph.co.uk' => '.articleBodyText',
      'time.com' => '#article-body p'
    }
    rules.key?(domain) ? rules[domain] : 'p'
  end
end
