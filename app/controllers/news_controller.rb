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

  # The page a headline links to: everything on it comes in with the request, so a
  # prefetch of it costs nothing anywhere. See the routes file.
  def preview
    @article_url = params[:article]
    @section = params[:section]
    @title = params[:title]

    render :preview
  end

  # The preview's one button lands here and is sent on to the article GET, which does
  # the work.
  def open
    redirect_to news_article_path(article: params[:article], section: params[:section],
                                  title: params[:title])
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
  # subscription, or rate limit us. Matched against the entry as the feed prints it, and
  # the only place the outlet appears there is its display name — every link is a
  # Google-encoded URL, so a publisher's own domain never matches unless the feed happens
  # to use it as the name. Each name has to be distinctive enough not to catch a headline
  # by accident — "People.com" rather than "People" — and a name that headlines do quote
  # is pinned with the "</font>" that closes the source's own tag.
  #
  # Grouped by the status the publisher returns. Blocking one costs a headline; leaving it
  # in costs a reader the trip to a page that will not open.
  BLOCKED_SOURCES = [
    'Financial Times', 'Bloomberg', 'bloomberg.com', 'Times of Israel', 'Times of India',
    'Reuters', 'Daily Record', 'Live updates', 'Wall Street Journal', 'Fox News',
    'USA TODAY', 'Axios', 'SFGATE', 'Ynetnews', 'KABC-TV',
    # 403, refuse the request outright
    'The New York Times', 'POLITICO', 'Sky News', 'The Telegraph', 'The Hill',
    'Fast Company', 'PhoneArena', 'MedPage Today', 'GamesHub', 'KGW', 'Vogue Adria',
    'Medical Xpress', 'Institute for the Study of War', 'GameSpot', 'Benzinga',
    'Firstpost', 'Investing.com', 'MMORPG.com', 'SpaceDaily', 'Space War',
    'Belfast Telegraph', 'F4W/WON', 'KTLA', 'Phys.org', 'This Is Anfield',
    'TweakTown', 'economist.com', 'merseyside.police.uk', 'Dezeen', 'Estate Agent Today',
    'Greater Manchester Police', 'Olive Press News Spain', 'PCMag</font>', 'Pulse Today',
    'ScreenHub Australia', 'Sunday World', 'TheBusinessDesk.com', 'en.softonic.com',
    'extremetech.com', 'grandepremio.com', 'qz.com',
    # 401 or 402, want a subscription
    'Barron\'s', 'MarketWatch', 'People.com', 'WSJ</font>', 'ew.com', 'instyle.com',
    'The Times</font>', 'autonews.com', 'marketscreener.com', 'Finimize',
    # 429, rate limiting us
    'RACER', 'The Tribune-Democrat',
    # Answer 200 with a JavaScript challenge, a teaser, or an empty client-rendered
    # shell, so there is nothing in the page to read. The Reach titles (Belfast Live
    # through Wales Online) all sit behind the same AWS WAF challenge.
    'Belfast Live', 'Liverpool Echo', 'Manchester Evening News', 'Football London',
    'Daily Express', 'Daily Star', 'Daily Mirror', 'mirror.co.uk', 'Chronicle Live',
    'Derbyshire Live', 'Wales Online',
    'ESPN</font>', 'IGN</font>', 'IGN India', 'The Japan News', 'Euronews',
    'Manchester United Website', 'West Ham United</font>', 'Trending Now Infrastructure',
    'IMDb</font>', 'TradingView', 'XTB.com', '富途牛牛',
    # 400, not an article page at all
    'facebook.com'
  ].freeze

  # A lead source per story with short alternates, and a ceiling on the stories.
  #
  # Opera Mini gives up on a page that takes too long to fetch and the handset is told the
  # page could not be opened, so weight here is not a matter of scrolling: past a point the
  # section does not open at all. Google covers each story with eight or so outlets and each
  # link carries an encoded Google URL in its href, so the full feed runs to hundreds of
  # links and tens of kilobytes, against four for every other page in the app.
  #
  # A story leads with its first readable source in full and offers the next two by outlet
  # name alone. Eight full headlines per story is the page that would not open; one is no
  # choice at all; a lead and two short alternates is the choice without the weight, and the
  # ones that will not open are already dropped by BLOCKED_SOURCES above.
  SOURCES_PER_STORY = 3
  # Enough to be worth reading and few enough to arrive. Nine sections sit one keypress
  # apart at the top of the page, so a reader who wants different stories has somewhere else
  # to go rather than further down.
  STORIES = 12

  def prepare_articles
    @news_items = @articles.first(STORIES).filter_map do |item|
      # One link per outlet: Google lists an outlet's follow-up pieces as separate entries,
      # and a multi-source story offers its links as outlet names alone, so two entries
      # from one outlet would read as the same link twice. Outlets without a name stay
      # apart, keyed by their address instead.
      articles = readable_articles(item)
                 .uniq { |article| article[:article_source].presence || article[:article_url] }
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
      #
      # The entities go after the tags: the feed double-escapes, so a headline arrives
      # carrying literal "&nbsp;" as text, and CGI.unescapeHTML knows only the basic five
      # entities, so the non-breaking spaces are folded by name. The view escapes whatever
      # needs escaping on the way back out.
      # The headline is the first anchor's own text, taken structurally: flattening the
      # whole entry welds whatever else it carries onto the end — the outlet name, and on
      # live feeds a trailing "See more headlines on Google News" link. The outlet is the
      # font tag's text. Both unescaped once, the feed being double-escaped, and never
      # marked safe: none of this is ours.
      headline = article[%r{<a\b[^>]*>(.*?)</a>}m, 1]
      title = CGI.unescapeHTML(strip_tags(headline.presence || article).gsub(/&nbsp;/i, ' ')).squish
      source = CGI.unescapeHTML(article[%r{<font[^>]*>\s*([^<]+)</font>}, 1].to_s).squish
      { article_title: title.delete_suffix(source).strip, article_url: url,
        article_source: source }
    end
  end

  # The feed costs Google a visit and every reader on this host shares the allowance, so
  # a fetched list is kept for a few minutes: long enough that hopping between sections
  # and back, or a link-prefetching browser sweeping the section digits, costs one fetch
  # rather than one per look, and short enough that the news stays news. Only a feed that
  # actually arrived is kept — an outage must stay retryable.
  def cached_feed
    key = [:news_feed, gnews.get_ceid, @section, @search_query]
    cached = Rails.cache.read(key)
    return cached if cached

    articles, title = gnews.get_articles_from_api(@search_query)
    Rails.cache.write(key, [articles, title], expires_in: 10.minutes) unless articles.nil?
    [articles, title]
  end

  def scrape_article(url)
    # An article opened twice — by the same reader coming back from the list, or by
    # anyone else behind this host — should not spend Google's resolve allowance or the
    # publisher's patience twice. A day, because headlines churn faster than that and
    # the memory store evicts under pressure anyway. Only a successful scrape is kept:
    # a throttle or a timeout must stay retryable, not become the answer for a day.
    cached = Rails.cache.read([:news_article, url])
    if cached
      @article_url = cached[:url]
      return cached[:result]
    end

    resolved = resolve_article(url)
    return { error: I18n.t('news.article_unavailable') } unless resolved.is_a?(String)

    @article_url = resolved
    result = Scraper.scrape_article(@article_url, gnews.get_useragent)
    if result[:error].nil?
      Rails.cache.write([:news_article, url], { url: resolved, result: result },
                        expires_in: 1.day)
    end
    result
  end

  # The resolve is the fragile half — it is the endpoint Google walls off first — so a
  # link already resolved once is not resolved again even when the scrape after it
  # failed: retrying the publisher does not need to spend Google's patience too.
  def resolve_article(url)
    cached = Rails.cache.read([:news_resolve, url])
    return cached if cached

    # Twice before giving up: Google throttles this host's address in flurries, and a
    # resolve that fails cold often lands warm a moment later — the reader was pressing the
    # link again by hand to the same effect. Both attempts are inside tight timeouts, so
    # the worst case is still an answer in seconds, not a page that never opens. A
    # rate limit is the exception: asking again into a wall only builds the wall higher.
    resolved = nil
    2.times do
      resolved = gnews.get_article(url)
      break if resolved
    end
    Rails.cache.write([:news_resolve, url], resolved, expires_in: 1.day) if resolved.is_a?(String)
    resolved
  end

  def get_articles
    @articles, @title = cached_feed

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
