# frozen_string_literal: true

require 'wombat'
require 'uri'
require 'open-uri'
require 'action_view'
require 'net/http'
require 'domainatrix'

class NewsController < ApplicationController
  include ActionView::Helpers::SanitizeHelper
  def news
    change_section
    get_articles
    prepare_articles

    render :list
  end

  def article
    @article_url = params[:article]
    @article = scrape_article(@article_url).html_safe
    render :article
  end

  def change_section
    @section = params[:section] || cookies['news_default_section']
  end

  def search
    @search_query = params[:search_query]
    get_articles
    prepare_articles
    render :list
  end

  private

  def prepare_articles
    @news_items = []
    @articles.each_with_index do |item, i|
      @news_items[i] = { item_title: item['title'].rpartition('-')[0] }
      @item_articles = []
      item['description'].gsub('<ol>', '').gsub('</ol>', '').gsub('</li>',
                                                                  '</li>splitme').split('splitme').each do |article|
        next if get_blacklist.any? { |news_site| article.include? news_site }

        @item_articles << { article_title: strip_links(article).html_safe,
                            article_url: URI.extract(article, /http(s)?/)[0] }
      end
      @news_items[i][:articles] = @item_articles
    end
  end

  def get_blacklist
    ['Financial Times',
     'Bloomberg',
     'Times of Israel',
     'Times of India',
     'Reuters',
     'Daily Record',
     'Live updates',
     'Wall Street Journal',
     'Fox News',
     'USA TODAY',
     'Axios',
     'SFGATE',
     'Ynetnews',
     'KABC-TV']
  end

  def resolve_article_rules(url)
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
      'pbs.org' => '.body-text p'
    }
    rules.key?(domain) ? rules[domain] : 'p'
  end

  def scrape_article(url)
    url.gsub!('https://news.google.com/rss/articles/', '')
    url.gsub!('?oc=5', '')
    url = Base64.decode64(url)
    url = URI.extract(url, /http(s)?/)[0]
    url.gsub!('$', '')
    @article_url = url
    @useragent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko)'\
     'Chrome/122.0.0.0 Safari/537.36'
    res = Net::HTTP.get_response(URI(url), { 'user-agent' => @useragent })
    unless res.code.start_with?('2', '3')
      Rails.logger.warn("Cannot load page - response #{res.code} - url #{@article_url}")
      return 'Cannot load page'
    end

    rule = resolve_article_rules(url)

    begin
      Wombat.set_user_agent(@useragent)
      out = Wombat.crawl do
        base_url url
        path '/'

        text({ css: rule }, :list)
      end
    rescue StandardError
      Rails.logger.warn("Cannot parse page - url #{url}")
      return 'Cannot parse page'
    end

    out['text'].join('<br /><br />')
  end

  def get_articles
    resolve_location
    uri = build_news_uri
    get_news_from_api(uri)
  end

  def build_news_uri
    URI('https://news.google.com/rss')
    lang = resolve_lang
    ceid = resolve_ceid(lang)
    params = {
      hl: lang,
      gl: @loc.upcase,
      ceid:
    }
    uri = nil

    if @search_query
      uri = URI('https://news.google.com/rss/search')
      params[:q] = @search_query
    elsif !@section.nil? && @section.upcase != 'HEADLINES'
      uri = URI("https://news.google.com/rss/headlines/section/topic/#{@section.upcase}")
    else
      uri = URI('https://news.google.com/rss')
    end
    uri.query = URI.encode_www_form(params)
    uri
  end

  def get_news_from_api(uri)
    @res = Net::HTTP.get_response(uri)
    @res = Net::HTTP.get_response(URI.parse(@res['location'])) if @res.code.start_with?('3')
    body = @res.body if @res.is_a?(Net::HTTPSuccess)
    body = JSON.parse(Hash.from_xml(body).to_json)
    @articles = body['rss']['channel']['item']
    @title = if !@section.nil? && @section.upcase != 'HEADLINES'
               body['rss']['channel']['title']
             else
               'Headlines - Latest - Google News'
             end
  end

  def resolve_location
    supported = %w[gb us in fr au ru]
    @loc = if supported.include? cookies['country_code']
             cookies['country_code']
           else
             'us'
           end
  end

  def resolve_lang
    locs = {
      'fr' => 'fr',
      'in' => 'hi',
      'us' => 'en-US',
      'gb' => 'en-GB',
      'au' => 'en-AU',
      'ru' => 'ru'
    }

    locs[@loc]
  end

  def resolve_ceid(lang)
    c = @loc.upcase
    ceids = {
      'FR' => "#{c}:#{lang}",
      'IN' => "#{c}:#{lang}",
      'US' => "#{c}:en",
      'GB' => "#{c}:en",
      'AU' => "#{c}:en",
      'RU' => "#{c}:#{lang}"
    }

    ceids[c]
  end
end
