# frozen_string_literal: true

require 'test_helper'

class NewsControllerTest < ActionDispatch::IntegrationTest
  test 'should load the news index page successfully when cookie is set' do
    get news_url, headers: { 'COOKIE' => 'country_code=gb;' }
    assert_response :success
    assert_match 'News headlines', @response.body
  end

  test 'should render a news article successfully' do
    get news_article_url, params: { article: 'https://news.google.com/rss/articles/'\
    'CBMinQFodHRwczovL3d3dy50aGVndWFyZGlhbi5jb20vYnVzaW5lc3MvbGl2ZS8yMDI0L21hci8wNS9qZXJlbXk'\
    'taHVudC1mcmVlemUtZnVlbC1kdXR5LWJ1ZGdldC11ay1jYXItc2FsZXMtZmVicnVhcnktc2VydmljZXMtcmVjZXN'\
    'zaW9uLWJpdGNvaW4tZ29sZC1idXNpbmVzcy1saXZl0gGdAWh0dHBzOi8vYW1wLnRoZWd1YXJkaWFuLmNvbS9idXNp'\
    'bmVzcy9saXZlLzIwMjQvbWFyLzA1L2plcmVteS1odW50LWZyZWV6ZS1mdWVsLWR1dHktYnVkZ2V0LXVrLWNhci1zYWx'\
    'lcy1mZWJydWFyeS1zZXJ2aWNlcy1yZWNlc3Npb24tYml0Y29pbi1nb2xkLWJ1c2luZXNzLWxpdmU?oc=5' }
    assert_response :success
    assert_match 'Rolling coverage of the latest', @response.body
  end
end
