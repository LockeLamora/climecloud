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
  test 'sends anyone without a saved location to settings rather than to Google' do
    %w[/news /news_search /news_article].each do |path|
      get path, headers: { 'COOKIE' => 'country_code=gb' }

      assert_redirected_to '/settings', "#{path} served a reader with no saved location"
    end

    assert_not_requested :get, /news\.google\.com/
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
    assert_match 'A story anyone can read', @response.body
    # No heading is left standing with nothing under it, which would read as a fault.
    assert_no_match(/A story only the blocked cover/, @response.body)
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
