# frozen_string_literal: true

require 'uri'
require 'open-uri'
require 'action_view'
require 'net/http'
require 'gnews'
require 'scraper'

class NewsController < ApplicationController
  include ActionView::Helpers::SanitizeHelper
  include Scraper
  def news
    @gnews = gnews
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
    gnews.change_section(@section)
  end

  def search
    @search_query = params[:search_query]
    get_articles
    prepare_articles
    render :list
  end

  private

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

  def scrape_article(url)
    resolved = gnews.get_article(url)
    return I18n.t('news.article_unavailable') if resolved.nil?

    @article_url = resolved
    Scraper.scrape_article(@article_url, gnews.get_useragent)
  end

  def get_articles
    @articles, @title = gnews.get_articles_from_api(@search_query)

    if @articles.nil?
      @error = I18n.t('news.unavailable')
      @articles = []
    end

    # Google returns a lone article as a bare item rather than a list.
    @articles = [@articles] unless @articles.is_a?(Array)
  end

  def gnews
    @gnews ||= Gnews.new({
                           section: cookies['news_default_section'],
                           country_code: cookies['country_code']
                         })
  end
end
