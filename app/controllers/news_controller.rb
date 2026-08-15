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

  # Every action here reaches Google, whose rate limit is shared by everyone on this
  # host's outbound address. A saved location is the cheapest evidence of a reader who
  # set the app up, so anything arriving without one is sent to do that first rather
  # than spending the allowance.
  before_action :require_saved_location

  def news
    @gnews = gnews
    change_section
    get_articles
    prepare_articles

    render :list
  end

  def article
    @article_url = params[:article]
    # Both carried from the list: the section so the way back returns to the list being
    # read, and the headline so a page that cannot be opened still says what it was about.
    @section = params[:section]
    @title = params[:title]

    result = scrape_article(@article_url)
    @article = result[:text]&.html_safe
    @error = result[:error]

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

  # Sources whose pages cannot be shown here: they refuse the request, want a
  # subscription, or rate limit us. Matched against the source name as Google prints it in
  # the feed, so each name has to be distinctive enough not to catch a headline by
  # accident — "People.com" rather than "People" for that reason.
  #
  # Grouped by the status the publisher returns. Blocking one costs a headline; leaving it
  # in costs a reader the trip to a page that will not open.
  BLOCKED_SOURCES = [
    'Financial Times', 'Bloomberg', 'Times of Israel', 'Times of India', 'Reuters',
    'Daily Record', 'Live updates', 'Wall Street Journal', 'Fox News', 'USA TODAY',
    'Axios', 'SFGATE', 'Ynetnews', 'KABC-TV',
    # 403, refuse the request outright
    'The New York Times', 'POLITICO', 'Sky News', 'The Telegraph', 'The Hill',
    'Fast Company', 'PhoneArena', 'MedPage Today', 'GamesHub', 'KGW', 'Vogue Adria',
    'Medical Xpress', 'Institute for the Study of War', 'GameSpot', 'Benzinga',
    'Firstpost', 'Investing.com', 'MMORPG.com', 'SpaceDaily', 'Space War',
    'Belfast Telegraph',
    # 401 or 402, want a subscription
    'Barron\'s', 'MarketWatch', 'People.com',
    # 429, rate limiting us
    'RACER', 'The Tribune-Democrat',
    # 400, not an article page at all
    'Facebook'
  ].freeze

  # One source per story, and a ceiling on the stories.
  #
  # Opera Mini gives up on a page that takes too long to fetch and the handset is told the
  # page could not be opened, so weight here is not a matter of scrolling: past a point the
  # section does not open at all. Google covers each story with eight or so outlets and each
  # link carries an encoded Google URL in its href, so the full feed runs to hundreds of
  # links and tens of kilobytes, against four for every other page in the app.
  #
  # The first readable source rather than a choice between them: eight versions of one story
  # is not a choice worth scrolling past on a 240px screen, and the ones that will not open
  # are already dropped by BLOCKED_SOURCES above.
  SOURCES_PER_STORY = 1
  # Enough to be worth reading and few enough to arrive. Nine sections sit one keypress
  # apart at the top of the page, so a reader who wants different stories has somewhere else
  # to go rather than further down.
  STORIES = 15

  def prepare_articles
    @news_items = @articles.first(STORIES).filter_map do |item|
      articles = readable_articles(item)
      # A story covered only by blocked sources is dropped whole. Leaving its heading with
      # an empty list underneath reads as a fault, and with nearly forty sources blocked it
      # happens often enough to matter.
      next if articles.empty?

      { item_title: item['title'].rpartition('-')[0],
        articles: articles.first(SOURCES_PER_STORY) }
    end
  end

  def readable_articles(item)
    entries = item['description'].to_s.gsub('<ol>', '').gsub('</ol>', '')
                                 .gsub('</li>', '</li>splitme').split('splitme')

    entries.filter_map do |article|
      next if BLOCKED_SOURCES.any? { |source| article.include?(source) }

      url = URI.extract(article, /http(s)?/).first
      next if url.blank?

      # Every tag, and text rather than html_safe.
      #
      # An entry arrives from the feed as a list item wrapped around a link and a <font> tag
      # naming the outlet. Stripping the anchor alone leaves the rest: the <li> nests inside
      # the one the view draws, and it goes into the href too, since the headline travels
      # with the link so a page that will not open can still say what it was about. The
      # <font> sets a colour, and a colour from a news feed lands on top of whichever screen
      # style the reader chose.
      #
      # Nothing here is ours, so none of it is marked safe to render as markup either.
      { article_title: strip_tags(article).squish, article_url: url }
    end
  end

  def scrape_article(url)
    resolved = gnews.get_article(url)
    return { error: I18n.t('news.article_unavailable') } if resolved.nil?

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
