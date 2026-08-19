# frozen_string_literal: true

require 'test_helper'

class NewsControllerTest < ActionDispatch::IntegrationTest
  COOKIES = 'lat=51.5;lon=-0.1;city=Testville;country_code=gb'

  # Every action reaches Google, so all of them require a saved location.
  setup do
    cookies[:lat] = '51.5'
    cookies[:lon] = '-0.1'
  end

  # Google's rate limit is shared by everyone on this host's outbound address, so a
  # crawler that has never been through settings must not be able to spend it. The
  # settings page is where a reader without a location is sent instead.
  #
  # The redirect has to come before the request, not after it: a crawler following a link
  # to an article costs the allowance whether or not it is shown the article. That is why
  # the check is a before_action rather than a guard inside each one.
  test 'sends anyone without a saved location to settings rather than to Google' do
    %w[/news /news_search /news_article].each do |path|
      get path, headers: { 'COOKIE' => 'country_code=gb' },
                params: { article: 'https://news.google.com/rss/articles/CBMinQFodHRwcw?oc=5' }

      assert_redirected_to '/settings', "#{path} served a reader with no saved location"
    end

    assert_not_requested :get, /news\.google\.com/
    # Resolving an article link is a POST to Google's batchexecute endpoint, so the GET
    # above does not cover it on its own.
    assert_not_requested :post, /news\.google\.com/
    assert_not_requested :get, /r\.jina\.ai/
  end

  # Anchors as direct children of a <ul> are invalid, and left every headline in one
  # unbroken run: a style that draws a box around a link then drew one box per wrapped line.
  # Opera Mini times itself out on a large page over a slow connection and the handset is
  # told the page could not be opened, so a page big enough is a page that does not exist.
  # This one was ninety-seven kilobytes across two hundred and eighty-seven links, Google
  # covering each story with eight outlets and every one of them carrying an encoded Google
  # URL in its href. Nothing else in the app comes near a tenth of that.
  test 'the news list is small enough to arrive on the handset' do
    stub_request(:get, /news.google.com/).to_return(body: file_fixture('news_response.xml').read)

    get news_url, headers: { 'COOKIE' => COOKIES }

    assert_response :success
    assert_operator @response.body.bytesize, :<, 25_000,
                    'this is heavy enough that the handset may be told it cannot be opened'
    assert_operator @response.body.scan(/<a /).size, :<=,
                    Gnews::SECTIONS.length + (NewsController::STORIES * NewsController::SOURCES_PER_STORY) + 4,
                    'more links than the sections, the stories and the furniture around them'
  end

  # The feed double-escapes its entities, so a headline arrives carrying literal "&nbsp;"
  # as text — which then travels into hrefs and, on the phosphor styles, into the glyph
  # images, shouted as "&NBSP;". Unescaped once after the tags are stripped.
  test 'a headline carries no leftover entities as text' do
    stub_request(:get, /news.google.com/).to_return(body: file_fixture('news_response.xml').read)

    get news_url, headers: { 'COOKIE' => COOKIES }

    assert_response :success
    assert_no_match(/&amp;nbsp;|nbsp/i, @response.body)
  end

  # The phosphor list drew every headline twice — once as the story heading, once inside
  # the link — and the doubled request count is a page Opera's proxy sometimes gives up
  # assembling. The heading glyph is dropped there; the link already carries the headline.
  test 'the phosphor news list stays under the glyph budget' do
    stub_request(:get, /news.google.com/).to_return(body: file_fixture('news_response.xml').read)

    get news_url, headers: { 'COOKIE' => "#{COOKIES};theme=crt-amber" }

    assert_response :success
    srcs = @response.body.scan(/<img src="([^"]+)"/).flatten

    # The proxy fetches by URL, and the sources are outlet names repeated story after
    # story — the same URLs — so unique images are what a page costs to assemble: at most
    # one heading per story, one lead or outlet set beneath it, and the shared furniture.
    assert_operator srcs.uniq.length, :<=, 9 + (NewsController::STORIES * 2) + 14 + 4,
                    'repeating each headline per source is a page the handset gives up on'
  end

  # Anything inside a button is a second cursor stop on the handset — the wide box and
  # then the narrow one — so on the drawn styles a choice is an image input: the glyph
  # is the control itself, a real image the handset's proxy paints, holding nothing.
  test 'glyph-theme headlines are image inputs with nothing inside for the cursor' do
    stub_request(:get, /news.google.com/).to_return(body: file_fixture('news_response.xml').read)

    get news_url, headers: { 'COOKIE' => "#{COOKIES};theme=teletext" }

    assert_response :success
    assert_match(%r{<input[^>]*type="image"[^>]*src="/glyph}, @response.body)
    assert_no_match(/<button/, @response.body,
                    'a button around the glyph is the second cursor stop again')
  end

  # Article bodies carry no glyphs on any style: prose is where reading comfort beats
  # theming, and a long story as images is the page that would not open. The chrome around
  # it — title, nav links — keeps the treatment.
  test 'an article body is plain text on a phosphor style' do
    stub_article_lookup
    stub_request(:get, /theguardian\.com/).to_return(
      status: 200,
      body: '<html><body><article>' \
            "#{(1..30).map do |n|
              "<p>Paragraph #{n}: #{'deployments typically last about six months. ' * 11}</p>"
            end.join}" \
            '</article></body></html>'
    )

    get news_article_url,
        params: { article: 'https://news.google.com/rss/articles/CBMinQFo?oc=5' },
        headers: { 'COOKIE' => "#{COOKIES};theme=crt-amber" }

    assert_response :success
    assert_no_match(%r{<img src="/glyph\?c=1}, @response.body,
                    'article prose drawn as images is the page that would not open')
    assert_match(/Paragraph 1:/, @response.body)
    assert_match(/Paragraph 30:/, @response.body, 'the story arrives whole, as text')
    # The chrome keeps the treatment: the nav links are still glyphs.
    assert_match(%r{<img src="/glyph\?l=1&amp;s=crt-amber&amp;t=0\+Back\+to\+menu}, @response.body)
  end

  # ITV's edge refuses a request that carries a browser's user-agent without the rest of a
  # browser's headers — it kills the connection rather than answering — so the scraper
  # sends the full set. The page itself embeds an empty structured articleBody, putting
  # the markup rule in charge, and writes its newsletter and podcast plugs into the body
  # as all-<strong> paragraphs, which the itv.com rule drops.
  test 'an ITV article arrives with its story and without its plugs' do
    stub_request(:get, %r{news\.google\.com/rss/articles/})
      .to_return(status: 200,
                 body: '<html data-n-a-ts="1709600000" data-n-a-sg="test-signature"></html>')
    stub_request(:post, %r{news\.google\.com/_/DotsSplashUi/data/batchexecute})
      .to_return(status: 200,
                 body: '[["wrb.fr",null,"[\"https://www.itv.com/news/2026-08-16/rain-and-cooler\"]"]]')
    stub_request(:get, %r{itv\.com/news/2026-08-16})
      .to_return(status: 200, body: file_fixture('itv_article.html').read,
                 headers: { 'Content-Type' => 'text/html' })

    get news_article_url,
        params: { article: 'https://news.google.com/rss/articles/CBMitv?oc=5' },
        headers: { 'COOKIE' => COOKIES }

    assert_response :success
    assert_requested :get, %r{itv\.com/news/2026-08-16},
                     headers: Scraper::BROWSER_HEADERS.slice('accept-language', 'sec-fetch-mode')
    assert_match 'The UK can expect fresher conditions', @response.body
    assert_match 'unprecedented demand', @response.body, 'the story has to arrive whole'
    assert_no_match(/Subscribe for free/, @response.body, 'the newsletter plug is not the story')
    assert_no_match(/Listen to our latest podcasts/, @response.body, 'nor is the podcast plug')
    assert_no_match(/ITV Consumer Limited/, @response.body, 'nor the footer')
  end

  # The heading is the grouping: a story with several sources keeps it, with the sources
  # indented beneath as outlet names alone — repeating the headline per source is the page
  # that would not open, and a bare outlet name with no heading above it reads as a
  # headline that lost its text. A story with one source drops the heading and lets its
  # lead carry the headline, or the same sentence stacks twice.
  test 'a multi-source story groups outlet links under its heading' do
    stub_request(:get, /news.google.com/).to_return(body: file_fixture('news_response.xml').read)

    get news_url, headers: { 'COOKIE' => COOKIES }

    budget = @response.body[%r{<b>Budget 2024.*?</ul>}m]

    assert budget, 'a story with several sources lost its heading'
    assert_operator budget.scan('<li>').size, :>, 1, 'the alternate sources are gone again'
    assert_operator budget.scan('<li>').size, :<=, NewsController::SOURCES_PER_STORY
    assert_match %r{<li><form[^>]*>.*?<button[^>]*>BBC\.com</button></form></li>}m, budget
    assert_match %r{<li><form[^>]*>.*?<button[^>]*>GOV\.UK</button></form></li>}m, budget
    assert_no_match(/<button[^>]*>[^<]*Jeremy Hunt announces/, budget,
                    'a source under a heading repeats the whole headline')
  end

  # Google lists an outlet's follow-up pieces as separate entries under the same story, and
  # the links under a heading are outlet names alone, so both entries would render as the
  # same link twice.
  test 'an outlet covering a story twice gets one link, not two identical ones' do
    stub_request(:get, /news.google.com/).to_return(body: <<~XML)
      <?xml version="1.0"?>
      <rss version="2.0"><channel><title>Headlines - Latest - Google News</title>
        <item>
          <title>A story one outlet keeps returning to - Wireline</title>
          <description>&lt;ol&gt;&lt;li&gt;&lt;a href="https://news.google.com/rss/articles/first"&gt;
            The story as it broke&lt;/a&gt;&amp;nbsp;&amp;nbsp;&lt;font color="#6f6f6f"&gt;Wireline&lt;/font&gt;&lt;/li&gt;
            &lt;li&gt;&lt;a href="https://news.google.com/rss/articles/second"&gt;
            The follow-up a day later&lt;/a&gt;&amp;nbsp;&amp;nbsp;&lt;font color="#6f6f6f"&gt;Wireline&lt;/font&gt;&lt;/li&gt;
            &lt;li&gt;&lt;a href="https://news.google.com/rss/articles/third"&gt;
            Another angle&lt;/a&gt;&amp;nbsp;&amp;nbsp;&lt;font color="#6f6f6f"&gt;Testwire&lt;/font&gt;&lt;/li&gt;&lt;/ol&gt;</description>
        </item>
      </channel></rss>
    XML

    get news_url, headers: { 'COOKIE' => COOKIES }

    assert_response :success
    assert_equal 1, @response.body.scan(%r{<button[^>]*>Wireline</button>}).size,
                 'the same outlet name twice reads as the same link twice'
    assert_match %r{<button[^>]*>Testwire</button>}, @response.body,
                 'the other outlet has to survive the dedupe'
  end

  test 'a single-source story is its lead alone, headline and outlet in one line' do
    stub_request(:get, /news.google.com/).to_return(body: file_fixture('news_response.xml').read)

    get news_url, headers: { 'COOKIE' => COOKIES }

    assert_no_match(/<b>[^<]*Jealous/, @response.body,
                    'a lone source under a matching heading stacks the same sentence twice')
    assert_match %r{<button[^>]*>[^<]*fiancé stabbed waitress[^<]*\(Daily Mail\)</button>},
                 @response.body
  end

  # Buttons rather than links, so a browser that fetches links ahead of the cursor
  # cannot open articles nobody chose — each open costs Google and a publisher a visit.
  # Text-only buttons: anything inside a button is a second cursor stop on the handset.
  # And no tokens: the action only bounces to the article GET, and forty tokens would
  # weigh the list down past what the handset accepts.
  test 'each article is a text-only button, never a prefetchable link' do
    stub_request(:get, /news.google.com/).to_return(body: file_fixture('news_response.xml').read)

    get news_url, headers: { 'COOKIE' => COOKIES }

    assert_response :success
    assert_match(%r{<li><form[^>]*action="/news_open"}, @response.body)
    assert_no_match(/<button[^>]*>\s*</, @response.body,
                    'an element inside a button is a second cursor stop')
    assert_no_match(/authenticity_token/, @response.body)
    assert_no_match(/<a[^>]*news_article/, @response.body)
    assert_no_match(/<ul>\s*<a/, @response.body)
  end

  test 'should load the news index page successfully when cookie is set' do
    stub_request(:get, /news.google.com/).to_return(body: file_fixture('news_response.xml').read)
    get news_url, headers: { 'COOKIE' => COOKIES }
    assert_response :success
    assert_match 'Headlines - Latest', @response.body
  end

  test 'reports rather than crashes when the news feed cannot be fetched' do
    stub_request(:get, /news.google.com/).to_return(status: 500, body: '')
    get news_url, headers: { 'COOKIE' => COOKIES }
    assert_response :success
    assert_match 'Could not fetch the news feed', @response.body
  end

  # Google counts its allowance against this host's outbound address, so a 429 is nothing
  # the reader did and the feed is worth one more try from somewhere else.
  test 'falls back to a relay when google refuses the feed on a rate limit' do
    stub_request(:get, /news\.google\.com/).to_return(status: 429, body: '')
    stub_request(:get, /r\.jina\.ai/).to_return(body: file_fixture('news_response.xml').read)

    get news_url, headers: { 'COOKIE' => COOKIES }

    assert_response :success
    assert_match 'Headlines - Latest', @response.body
    assert_no_match(/Could not fetch the news feed/, @response.body)
    assert_requested :get, %r{r\.jina\.ai/https://news\.google\.com},
                     headers: { 'x-return-format' => 'text' }
  end

  # A relay answers for itself, not for Google. The first of them rewrites what it fetches
  # into prose for a language model, which comes back 200 and is not a feed at all.
  test 'moves to the next relay when one returns something that is not the feed' do
    stub_request(:get, /news\.google\.com/).to_return(status: 429, body: '')
    stub_request(:get, /r\.jina\.ai/).to_return(body: 'Here is a summary of the top stories.')
    stub_request(:get, /allorigins\.win/).to_return(body: file_fixture('news_response.xml').read)

    get news_url, headers: { 'COOKIE' => COOKIES }

    assert_response :success
    assert_match 'Headlines - Latest', @response.body
  end

  test 'does not relay a refusal that is not a rate limit' do
    stub_request(:get, /news\.google\.com/).to_return(status: 500, body: '')

    get news_url, headers: { 'COOKIE' => COOKIES }

    assert_response :success
    assert_match 'Could not fetch the news feed', @response.body
    assert_not_requested :get, /r\.jina\.ai/
    assert_not_requested :get, /allorigins\.win/
    assert_not_requested :get, /codetabs\.com/
  end

  test 'says the feed is unavailable when every relay fails too' do
    stub_request(:get, /news\.google\.com/).to_return(status: 429, body: '')
    stub_request(:get, /r\.jina\.ai/).to_return(status: 503, body: '')
    stub_request(:get, /allorigins\.win/).to_return(status: 503, body: '')
    stub_request(:get, /codetabs\.com/).to_return(status: 503, body: '')

    get news_url, headers: { 'COOKIE' => COOKIES }

    assert_response :success
    assert_match 'Could not fetch the news feed', @response.body
  end

  # A search reaches the same feed by a different path, so it gets the same second chance.
  test 'relays a search that google refuses on a rate limit' do
    stub_request(:get, /news\.google\.com/).to_return(status: 429, body: '')
    stub_request(:get, /r\.jina\.ai/).to_return(body: file_fixture('news_response.xml').read)

    get news_search_url, params: { search_query: 'budget' }, headers: { 'COOKIE' => COOKIES }

    assert_response :success
    assert_requested :get, %r{r\.jina\.ai/https://news\.google\.com/rss/search}
  end

  test 'should render a news article successfully' do
    stub_article_lookup
    get news_article_url, params: { article: 'https://news.google.com/rss/articles/'\
    'CBMinQFodHRwczovL3d3dy50aGVndWFyZGlhbi5jb20vYnVzaW5lc3MvbGl2ZS8yMDI0L21hci8wNS9qZXJlbXk'\
    'taHVudC1mcmVlemUtZnVlbC1kdXR5LWJ1ZGdldC11ay1jYXItc2FsZXMtZmVicnVhcnktc2VydmljZXMtcmVjZXN'\
    'zaW9uLWJpdGNvaW4tZ29sZC1idXNpbmVzcy1saXZl0gGdAWh0dHBzOi8vYW1wLnRoZWd1YXJkaWFuLmNvbS9idXNp'\
    'bmVzcy9saXZlLzIwMjQvbWFyLzA1L2plcmVteS1odW50LWZyZWV6ZS1mdWVsLWR1dHktYnVkZ2V0LXVrLWNhci1zYWx'\
    'lcy1mZWJydWFyeS1zZXJ2aWNlcy1yZWNlc3Npb24tYml0Y29pbi1nb2xkLWJ1c2luZXNzLWxpdmU?oc=5' }
    assert_response :success
    assert_match 'national insurance', @response.body
  end

  # The scrape is cached for a day, keyed on the Google link, so the same story opened
  # twice costs Google's resolver and the publisher one visit rather than two. The suite
  # runs on a null store, so this test brings a real one.
  test 'a scraped article is served from cache the second time' do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    stub_article_lookup

    2.times do
      get news_article_url, params: { article: 'https://news.google.com/rss/articles/'\
      'CBMinQFodHRwczovL3d3dy50aGVndWFyZGlhbi5jb20vYnVzaW5lc3MvbGl2ZS8yMDI0L21hci8wNS9qZXJlbXk'\
      'taHVudC1mcmVlemUtZnVlbC1kdXR5LWJ1ZGdldC11ay1jYXItc2FsZXMtZmVicnVhcnktc2VydmljZXMtcmVjZXN'\
      'zaW9uLWJpdGNvaW4tZ29sZC1idXNpbmVzcy1saXZl0gGdAWh0dHBzOi8vYW1wLnRoZWd1YXJkaWFuLmNvbS9idXNp'\
      'bmVzcy9saXZlLzIwMjQvbWFyLzA1L2plcmVteS1odW50LWZyZWV6ZS1mdWVsLWR1dHktYnVkZ2V0LXVrLWNhci1zYWx'\
      'lcy1mZWJydWFyeS1zZXJ2aWNlcy1yZWNlc3Npb24tYml0Y29pbi1nb2xkLWJ1c2luZXNzLWxpdmU?oc=5' }
    end

    assert_response :success
    assert_match 'national insurance', @response.body
    assert_requested :get, /theguardian\.com/, times: 1
    assert_requested :post, %r{news\.google\.com/_/DotsSplashUi}, times: 1
  ensure
    Rails.cache = original_cache
  end

  # Some publishers spell their punctuation out in spans meant only for a screen reader, so
  # hidden text is stripped before the story is read. Quotation marks themselves are
  # untouched: all three forms below come through as typed.
  test 'leaves out text written only for a screen reader, and leaves quotes alone' do
    stub_article_lookup
    stub_page(<<~HTML)
      <html><body><article>
        <p>A plain typed quote: he said "the budget is fine" and left the building today.</p>
        <p>An entity quote: she said &quot;nothing of the sort&quot; before walking out of it.</p>
        <p>A curly quote: they said &#8220;we will see about that&#8221; and then said no more.</p>
        <p><span class="visually-hidden">double quotation mark</span>Spelled out for a reader
          that cannot see it, which is not something to print on a screen.</p>
        <p><span class="sr-only">double quotation mark</span>The other spelling of the same
          class name, which publishers use just as often as the first one does.</p>
      </article></body></html>
    HTML

    get_article

    assert_response :success
    assert_no_match(/double quotation mark/, @response.body)
    assert_match '"the budget is fine"', @response.body
    assert_match 'nothing of the sort', @response.body
    assert_match '“we will see about that”', @response.body
    # The sentences the hidden spans sat inside are still part of the story.
    assert_match 'Spelled out for a reader', @response.body
  end

  test 'prefers the structured article body the publisher embeds' do
    stub_article_lookup
    stub_page(<<~HTML)
      <html><head>
        <script type="application/ld+json">
          {"@type":"NewsArticle","articleBody":"The chancellor cut national insurance for the second time this year."}
        </script>
      </head><body>
        <nav><p>Sign in to read more of our award winning journalism today</p></nav>
        <p>Accept all cookies to continue reading this article on our website</p>
      </body></html>
    HTML

    get_article

    assert_response :success
    # schema.org articleBody is the story without the furniture around it.
    assert_match 'chancellor cut national insurance', @response.body
    assert_no_match(/Accept all cookies/, @response.body)
    assert_no_match(/Sign in to read more/, @response.body)
  end

  test 'reads a structured body nested under a graph' do
    stub_article_lookup
    stub_page(<<~HTML)
      <html><head>
        <script type="application/ld+json">
          {"@graph":[{"@type":"WebPage"},{"@type":"NewsArticle","articleBody":"Publishers nest this differently and both shapes are common in the wild."}]}
        </script>
      </head><body><p>Something else entirely that should not be shown here</p></body></html>
    HTML

    get_article

    assert_response :success
    assert_match 'Publishers nest this differently', @response.body
  end

  test 'ignores structured data that is not valid json' do
    stub_article_lookup
    stub_page(<<~HTML)
      <html><head><script type="application/ld+json">{ this is not json at all </script></head>
      <body><article><p>The article itself is still perfectly readable underneath it.</p></article></body></html>
    HTML

    get_article

    assert_response :success
    assert_match 'still perfectly readable', @response.body
  end

  test 'leaves the furniture off the page' do
    stub_article_lookup
    stub_page(<<~HTML)
      <html><body>
        <nav><p>Home News Sport Business Culture Travel and everything else besides</p></nav>
        <header><p>Subscribe today for unlimited access to everything we publish here</p></header>
        <article><p>Ministers said the scheme would begin in the spring of next year.</p></article>
        <aside><p>Related: five other stories you might like to read after this one</p></aside>
        <footer><p>Copyright, terms of service, privacy policy and contact details here</p></footer>
      </body></html>
    HTML

    get_article

    assert_response :success
    assert_match 'Ministers said the scheme', @response.body
    ['Home News Sport', 'Subscribe today', 'Related:', 'Copyright, terms'].each do |furniture|
      assert_no_match(/#{Regexp.escape(furniture)}/, @response.body, "#{furniture} is still on the page")
    end
  end

  test 'looks where an article usually is before taking every paragraph on the page' do
    stub_article_lookup
    stub_page(<<~HTML)
      <html><body>
        <div class="promo"><p>Try our newspaper app free for a whole month starting today</p></div>
        <main><p>The inquiry will report before the end of the parliamentary session.</p></main>
        <div class="more"><p>Sign up to our newsletter for the best of our writing weekly</p></div>
      </body></html>
    HTML

    get_article

    assert_response :success
    assert_match 'The inquiry will report', @response.body
    assert_no_match(/newspaper app free/, @response.body)
    assert_no_match(/Sign up to our newsletter/, @response.body)
  end

  test 'drops bylines and captions that are too short to be prose' do
    stub_article_lookup
    stub_page(<<~HTML)
      <html><body><article>
        <p>By Our Correspondent</p>
        <p>Share this</p>
        <p>3 min read</p>
        <p>The council voted to approve the plan after a debate lasting three hours.</p>
      </article></body></html>
    HTML

    get_article

    assert_response :success
    assert_match 'The council voted to approve', @response.body
    ['By Our Correspondent', 'Share this', '3 min read'].each do |scrap|
      assert_no_match(/#{Regexp.escape(scrap)}/, @response.body)
    end
  end

  test 'says it cannot read the page rather than showing what is around the story' do
    stub_article_lookup
    stub_page(<<~HTML)
      <html><body>
        <div class="wrapper">
          <p>Find what's worth watching with Radio Times magazine and app. Less scrolling, more great TV.</p>
          <p>With a lifetime mortgage, the most popular type of equity release, you continue to own your home.</p>
          <p>If your listening experience needs an upgrade, browse radios and music centres from Roberts.</p>
        </div>
      </body></html>
    HTML

    get_article

    assert_response :success
    # Taking every paragraph on the page put paid placements on screen dressed as the
    # story. They are written in full sentences, so no length filter catches them.
    assert_match 'Cannot parse page', @response.body
    assert_no_match(/equity release/, @response.body)
    assert_no_match(/Radio Times/, @response.body)
  end

  test 'leaves paid placements out of an article it can read' do
    stub_article_lookup
    stub_page(<<~HTML)
      <html><body><article>
        <p>The committee will publish its findings before the end of the month.</p>
        <div class="advert-inline"><p>With a lifetime mortgage you continue to own 100% of your home.</p></div>
        <div class="promo-block"><p>Less scrolling, more great TV with Radio Times magazine and app.</p></div>
      </article></body></html>
    HTML

    get_article

    assert_response :success
    assert_match 'The committee will publish', @response.body
    assert_no_match(/lifetime mortgage/, @response.body)
    assert_no_match(/Radio Times/, @response.body)
  end

  test 'puts the links after the story rather than above it' do
    stub_article_lookup
    stub_page('<html><body><article>' \
              '<p>The story itself runs on for quite some distance here.</p>' \
              '</article></body></html>')

    get_article

    assert_response :success
    # Links after the story, so finishing it leaves them to hand rather than a scroll back.
    assert_operator @response.body.index('The story itself runs on'), :<,
                    @response.body.index('Back to headlines')
    assert_operator @response.body.index('The story itself runs on'), :<,
                    @response.body.index('Back to menu')
  end

  test 'shows a short article rather than nothing at all' do
    stub_article_lookup
    stub_page('<html><body><article><p>Play was abandoned.</p><p>No result.</p></article></body></html>')

    get_article

    assert_response :success
    # Filtering that leaves nothing behind falls back to the unfiltered set.
    assert_match 'Play was abandoned', @response.body
    assert_no_match(/Cannot parse page/, @response.body)
  end

  test 'leaves out sources whose pages cannot be shown' do
    stub_request(:get, /news.google.com/).to_return(body: file_fixture('news_response.xml').read)

    get news_url, headers: { 'COOKIE' => COOKIES }

    assert_response :success
    NewsController::BLOCKED_SOURCES.each do |source|
      assert_no_match(/#{Regexp.escape(source)}/, @response.body, "#{source} is still offered")
    end
  end

  test 'drops a story whose every source is blocked rather than leaving an empty heading' do
    stub_request(:get, /news.google.com/).to_return(body: blocked_story_feed)

    get news_url, headers: { 'COOKIE' => COOKIES }

    assert_response :success
    # The readable story survives as its lead link; single-sourced, it carries no heading.
    assert_match 'Open story', @response.body
    # No heading is left standing with nothing under it, which would read as a fault.
    assert_no_match(/A story only the blocked cover/, @response.body)
  end

  # A resolve with no ceiling sits for minutes when Google throttles this host or walks it
  # through a consent chain, and a page that takes minutes is one the reader is told could
  # not be opened — on any browser. Every failure mode below has to answer fast with the
  # titled unavailable page instead.
  test 'a redirect chain is walked a few steps and then given up on, not followed forever' do
    stub_request(:get, %r{news\.google\.com/rss/articles/})
      .to_return(status: 302, headers: { 'Location' => 'https://news.google.com/rss/articles/CBMi?oc=5' })

    get news_article_url, params: { article: 'https://news.google.com/rss/articles/CBMi?oc=5' },
                          headers: { 'COOKIE' => COOKIES }

    assert_response :success
    assert_match 'article', @response.body
    # The cap, the original request, and one retry of the whole resolve.
    assert_requested :get, %r{news\.google\.com/rss/articles/}, times: (Gnews::MAX_REDIRECTS + 1) * 2
  end

  test 'a resolve that times out answers as unavailable rather than hanging' do
    stub_request(:get, %r{news\.google\.com/rss/articles/}).to_raise(Net::OpenTimeout)

    get news_article_url, params: { article: 'https://news.google.com/rss/articles/CBMi?oc=5',
                                    title: 'Cambridge vigil' },
                          headers: { 'COOKIE' => COOKIES }

    assert_response :success
    # The page still says what the story was, and the source link still works.
    assert_match 'Cambridge vigil', @response.body
  end

  # Google throttles in flurries: a resolve that fails cold often lands warm a moment
  # later, and the reader was pressing the link again by hand to the same effect.
  test 'a resolve that fails once is tried once more before giving up' do
    stub_request(:get, %r{news\.google\.com/rss/articles/})
      .to_return({ status: 500, body: '' },
                 { status: 200, body: '<html data-n-a-ts="1709600000" data-n-a-sg="sig"></html>' })
    stub_request(:post, %r{news\.google\.com/_/DotsSplashUi})
      .to_return(status: 200, body: '[["wrb.fr",null,"[\"https://www.theguardian.com/x\"]"]]')
    stub_request(:get, /theguardian\.com/)
      .to_return(status: 200, body: '<html><body><article><p>Second try read it.</p></article></body></html>')

    get news_article_url, params: { article: 'https://news.google.com/rss/articles/CBMi?oc=5' },
                          headers: { 'COOKIE' => COOKIES }

    assert_response :success
    assert_match 'Second try read it.', @response.body
  end

  # Asking again into a rate-limit wall only builds it higher: a 429 is not retried, and
  # the wall's own page — a page of links — must never be fished for a "resolved" URL and
  # scraped as if it were the article. Both happened in production on 2026-08-19.
  test 'a rate-limited resolve is not retried and its captcha page is not the article' do
    stub_request(:get, %r{news\.google\.com/rss/articles/})
      .to_return(status: 200, body: '<html data-n-a-ts="1709600000" data-n-a-sg="sig"></html>')
    walled = stub_request(:post, %r{news\.google\.com/_/DotsSplashUi})
             .to_return(status: 429,
                        body: 'To continue, visit https://www.google.com/sorry/index?continue=x')
    sorry = stub_request(:get, %r{www\.google\.com/sorry})

    get news_article_url, params: { article: 'https://news.google.com/rss/articles/CBMi?oc=5' },
                          headers: { 'COOKIE' => COOKIES }

    assert_response :success
    assert_match 'Could not open this article', @response.body
    assert_requested walled, times: 1
    assert_not_requested sorry
  end

  # With a proxy provisioned, a walled resolve gets one more try through it — a
  # dedicated egress address, spent only after the shared one is refused, so the
  # proxy's monthly allowance goes on the mornings that need it and nothing else.
  test 'a rate-limited resolve gets one retry through the proxy when one is provisioned' do
    ENV['FIXIE_URL'] = 'http://fixie:secret@proxy.usefixie.test:80'
    stub_request(:get, %r{news\.google\.com/rss/articles/})
      .to_return(status: 200, body: '<html data-n-a-ts="1709600000" data-n-a-sg="sig"></html>')
    walled = stub_request(:post, %r{news\.google\.com/_/DotsSplashUi})
             .to_return({ status: 429, body: 'visit https://www.google.com/sorry/index' },
                        { status: 200, body: '[["wrb.fr",null,"[\"https://www.theguardian.com/x\"]"]]' })
    stub_request(:get, /theguardian\.com/)
      .to_return(status: 200,
                 body: '<html><body><article><p>The proxy carried it through the wall.</p></article></body></html>')

    get news_article_url, params: { article: 'https://news.google.com/rss/articles/CBMi?oc=5' },
                          headers: { 'COOKIE' => COOKIES }

    assert_response :success
    assert_match 'The proxy carried it through the wall.', @response.body
    assert_requested walled, times: 2
  ensure
    ENV.delete('FIXIE_URL')
  end

  # A walled feed tries the dedicated proxy address before the public relays: the
  # relays are flaky strangers, the proxy is ours. Driven through the FIXIE_URL
  # fallback because the suite blanks credentials — CI has no master key to decrypt
  # them, and the dev machine is made to match.
  test 'a rate-limited feed tries the proxy before the public relays' do
    ENV['FIXIE_URL'] = 'http://fixie:secret@proxy.usefixie.test:80'
    stub_request(:get, /news.google.com/)
      .to_return({ status: 429, body: '' },
                 { status: 200, body: file_fixture('news_response.xml').read })
    relays = stub_request(:get, /r\.jina\.ai|allorigins|codetabs/)

    get news_url, headers: { 'COOKIE' => COOKIES }

    assert_response :success
    assert_match 'Budget 2024', @response.body
    assert_not_requested relays
  ensure
    ENV.delete('FIXIE_URL')
  end

  # The feed is shared by everyone on this host, so looking at the same section twice
  # inside a few minutes costs Google one visit. The suite runs on a null cache store,
  # so this test brings a real one.
  test 'a section feed is served from cache the second time' do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    feed = stub_request(:get, /news.google.com/)
           .to_return(body: file_fixture('news_response.xml').read)

    2.times { get news_url, headers: { 'COOKIE' => COOKIES } }

    assert_response :success
    assert_requested feed, times: 1
  ensure
    Rails.cache = original_cache
  end

  # The headline buttons post here; the article page itself stays a plain GET.
  test 'opening a headline bounces to the article page' do
    post news_open_url, params: { article: 'https://news.google.com/rss/articles/x?oc=5',
                                  section: 'HEADLINES', title: 'A headline' },
                        headers: { 'COOKIE' => COOKIES }

    assert_redirected_to news_article_path(article: 'https://news.google.com/rss/articles/x?oc=5',
                                           section: 'HEADLINES', title: 'A headline')
    assert_not_requested :get, /news\.google\.com/
  end

  test 'still says what the story was when the publisher refuses the page' do
    stub_article_lookup
    stub_request(:get, /theguardian\.com/).to_return(status: 403, body: '')

    get news_article_url, params: { article: 'https://news.google.com/rss/articles/test',
                                    title: 'Budget: national insurance cut again' }

    assert_response :success
    # Roughly a third of opens end this way. "Cannot load page" on its own wasted the trip.
    assert_match 'Budget: national insurance cut again', @response.body
    assert_match 'Cannot load page', @response.body
    # The source still works even when we cannot render it here.
    assert_match 'theguardian.com', @response.body
    assert_match 'Back to headlines', @response.body
  end

  test 'survives a publisher that never answers' do
    stub_article_lookup
    stub_request(:get, /theguardian\.com/).to_timeout

    get news_article_url, params: { article: 'https://news.google.com/rss/articles/test',
                                    title: 'A story nobody can reach' }

    # One unanswered request held a worker for forty two seconds, and once for two
    # minutes before raising and returning a 500.
    assert_response :success
    assert_match 'A story nobody can reach', @response.body
  end

  test 'survives a connection dropped mid response' do
    stub_article_lookup
    stub_request(:get, /theguardian\.com/).to_raise(EOFError)

    get news_article_url, params: { article: 'https://news.google.com/rss/articles/test' }

    # EOFError reached the browser as a 500 rather than a page.
    assert_response :success
    assert_match 'Cannot load page', @response.body
  end

  test 'judges the page it was finally served, not the one first asked for' do
    stub_article_lookup
    stub_request(:get, /theguardian\.com/)
      .to_return(status: 302, headers: { 'Location' => 'https://elsewhere.example/story' })
    stub_request(:get, %r{elsewhere\.example/story}).to_return(status: 403, body: '')

    get news_article_url, params: { article: 'https://news.google.com/rss/articles/test',
                                    title: 'Redirected somewhere that refuses us' }

    assert_response :success
    # The status that decides is the one from the page finally served, so a publisher that
    # parser then failed on it instead.
    assert_match 'Cannot load page', @response.body
    assert_match 'Redirected somewhere that refuses us', @response.body
  end

  test 'reads the article at the end of a redirect' do
    stub_article_lookup
    stub_request(:get, /theguardian\.com/)
      .to_return(status: 301, headers: { 'Location' => 'https://www.theguardian.com/amp/budget' })
    stub_request(:get, %r{theguardian\.com/amp/budget})
      .to_return(status: 200, body: '<html><body><article><p>Moved but readable.</p></article></body></html>')

    get news_article_url, params: { article: 'https://news.google.com/rss/articles/test' }

    assert_response :success
    assert_match 'Moved but readable', @response.body
  end

  test 'fetches the article once rather than twice' do
    stub_article_lookup

    get news_article_url, params: { article: 'https://news.google.com/rss/articles/test' }

    assert_response :success
    # One fetch serves both the status check and the read, rather than doubling the
    # traffic sent to publishers already rate limiting us.
    assert_requested :get, /theguardian\.com/, times: 1
  end

  test 'keeps the whole url when google hands one back' do
    stub_request(:get, %r{news\.google\.com/rss/articles/})
      .to_return(status: 200, body: '<html data-n-a-ts="1709600000" data-n-a-sg="test-signature"></html>')
    # The real response wraps the URL in a JSON string behind anti-hijacking padding.
    stub_request(:post, %r{news\.google\.com/_/DotsSplashUi/data/batchexecute})
      .to_return(status: 200,
                 body: ")]}'\n\n" \
                       '[["wrb.fr",null,"[\"https://abcnews.example/Politics/story?id=12345\\u0026x=1\"]"]]')
    stub_request(:get, /abcnews\.example/).to_return(status: 200, body: '<html><body><p>Read.</p></body></html>')

    get news_article_url, params: { article: 'https://news.google.com/rss/articles/test' }

    assert_response :success
    # URI.extract stopped at the query string and asked for ".../story?id", which 404ed
    # through no fault of the publisher.
    assert_requested :get, %r{abcnews\.example/Politics/story\?id=12345}
  end

  test 'offers every section with a digit of its own' do
    stub_request(:get, /news.google.com/).to_return(body: file_fixture('news_response.xml').read)

    get news_url, headers: { 'COOKIE' => COOKIES }

    assert_response :success
    Gnews::SECTIONS.each_with_index do |section, index|
      label = I18n.t("news.section.#{section.downcase}")
      assert_match "#{index + 1} #{label}", @response.body, "#{section} has no number"
      assert_match "accesskey=\"#{index + 1}\"", @response.body
    end
    # Zero stays with the menu, as on every other page.
    assert_no_match(/accesskey="0"[^>]*section/, @response.body)
  end

  test 'names the sections in the language the reader chose' do
    stub_request(:get, /news.google.com/).to_return(body: file_fixture('news_response.xml').read)

    get news_url, headers: { 'COOKIE' => 'lat=51.5;lon=-0.1;country_code=fr;locale=fr' }

    assert_response :success
    # Nine untranslated words in an app that speaks seventeen languages.
    assert_match 'Divertissement', @response.body
    assert_match 'Économie', @response.body
    assert_no_match(/Entertainment/, @response.body)
  end

  test 'offers a way back to the headlines from an article' do
    stub_article_lookup

    get news_article_url, params: { article: 'https://news.google.com/rss/articles/test', section: 'SPORTS' }

    assert_response :success
    # The browser back key is the only alternative, and a keypad barely has one.
    assert_match 'Back to headlines', @response.body
    assert_match 'accesskey="9"', @response.body
    # Back to the section being read, not to whichever one is the default.
    assert_match 'section=SPORTS', @response.body
  end

  test 'still offers the headlines when the article was opened without a section' do
    stub_article_lookup

    get news_article_url, params: { article: 'https://news.google.com/rss/articles/test' }

    assert_response :success
    assert_match 'Back to headlines', @response.body
    assert_match 'href="/news"', @response.body
  end

  test 'carries the section into the article links so the way back is known' do
    stub_request(:get, /news.google.com/).to_return(body: file_fixture('news_response.xml').read)

    get news_url, params: { section: 'BUSINESS' }, headers: { 'COOKIE' => COOKIES }

    assert_response :success
    assert_match 'section=BUSINESS', @response.body
  end

  private

  # The publisher's page, once the Google link has been resolved to it.
  def stub_page(html)
    stub_request(:get, /theguardian\.com/)
      .to_return(status: 200, body: html, headers: { 'Content-Type' => 'text/html' })
  end

  def get_article
    get news_article_url, params: { article: 'https://news.google.com/rss/articles/test' }
  end

  # Two stories, one covered only by a blocked source, the other readable.
  def blocked_story_feed
    <<~XML
      <?xml version="1.0"?>
      <rss version="2.0"><channel><title>Headlines - Latest - Google News</title>
        <item>
          <title>A story only the blocked cover - POLITICO</title>
          <description>&lt;ol&gt;&lt;li&gt;&lt;a href="https://news.google.com/rss/articles/blocked"&gt;
            Blocked story&lt;/a&gt;&amp;nbsp;&amp;nbsp;POLITICO&lt;/li&gt;&lt;/ol&gt;</description>
        </item>
        <item>
          <title>A story anyone can read - Testwire</title>
          <description>&lt;ol&gt;&lt;li&gt;&lt;a href="https://news.google.com/rss/articles/open"&gt;
            Open story&lt;/a&gt;&amp;nbsp;&amp;nbsp;Testwire&lt;/li&gt;&lt;/ol&gt;</description>
        </item>
      </channel></rss>
    XML
  end

  # Resolving a Google News link is a three step dance: fetch the article stub for
  # its timestamp and signature, post those back to get the real URL, then scrape it.
  # Left live it depends on Google's consent wall and on a 2024 article still reading
  # the same, so all three are pinned here.
  def stub_article_lookup
    stub_request(:get, %r{news\.google\.com/rss/articles/})
      .to_return(status: 200,
                 body: '<html data-n-a-ts="1709600000" data-n-a-sg="test-signature"></html>',
                 headers: { 'Content-Type' => 'text/html' })

    stub_request(:post, %r{news\.google\.com/_/DotsSplashUi/data/batchexecute})
      .to_return(status: 200,
                 body: '[["wrb.fr",null,"[\"https://www.theguardian.com/business/live/2024/mar/05/budget\"]"]]')

    stub_request(:get, /theguardian\.com/)
      .to_return(status: 200,
                 body: '<html><body><article>' \
                       '<p>Jeremy Hunt cut national insurance again in the budget.</p>' \
                       '</article></body></html>',
                 headers: { 'Content-Type' => 'text/html' })
  end
end
