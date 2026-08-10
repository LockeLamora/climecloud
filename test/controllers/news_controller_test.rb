# frozen_string_literal: true

require 'test_helper'

class NewsControllerTest < ActionDispatch::IntegrationTest
  test 'should load the news index page successfully when cookie is set' do
    stub_request(:get, /news.google.com/).to_return(body: file_fixture('news_response.xml').read)
    get news_url, headers: { 'COOKIE' => 'country_code=gb;' }
    assert_response :success
    assert_match 'Headlines - Latest', @response.body
  end

  test 'reports rather than crashes when the news feed cannot be fetched' do
    stub_request(:get, /news.google.com/).to_return(status: 500, body: '')
    get news_url, headers: { 'COOKIE' => 'country_code=gb;' }
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

  private

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
                 body: '<html><body><p>Jeremy Hunt cut national insurance again in the budget.</p>' \
                       '</body></html>',
                 headers: { 'Content-Type' => 'text/html' })
  end
end
