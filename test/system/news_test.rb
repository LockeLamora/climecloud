# frozen_string_literal: true

require 'application_system_test_case'

class NewsTest < ApplicationSystemTestCase
  # News requires a saved location, so the cookies a reader would have are set first. The
  # first visit is only there to give the browser a domain to store them against.
  setup do
    visit root_url
    { 'lat' => '51.5', 'lon' => '-0.1', 'city' => 'Testville', 'country_code' => 'gb' }.each do |name, value|
      page.driver.browser.manage.add_cookie(name: name, value: value)
    end
  end

  test 'visiting the index and then an article' do
    stub_request(:get, /news.google.com/).to_return(body: file_fixture('news_response.xml').read)
    stub_article_lookup
    visit news_url
    assert_text 'Budget 2024 live: Jeremy Hunt'
    # The headline's href is the free redirect; the browser follows it to the article
    # in the same press.
    first('.news li a').click
    assert_text 'BBC programmes on iPlayer'
  end

  test 'visiting the index and clicking on a topic' do
    stub_request(:get, /news.google.com/).to_return(body: file_fixture('news_response.xml').read)
    visit news_url
    stub_request(:get, /news.google.com/).to_return(body: file_fixture('science-news.xml').read)
    # Scoped to the topic list: the headlines below it are published by Science@NASA and
    # Science News Magazine, so an unscoped link name matches three things.
    within('.news_topics') { click_link('Science') }
    assert_text "'Nightmarish' sea lizard that roamed the seas 66"
  end

  private

  # A Google News link resolves through three requests before the real article is
  # reached: fetch the stub page for its timestamp and signature, post those back for
  # the true URL, then load that. Pinned so the test does not ride on Google's
  # consent flow or on a 2024 article still reading the same.
  def stub_article_lookup
    stub_request(:get, %r{news\.google\.com/rss/articles/})
      .to_return(status: 200,
                 body: '<html data-n-a-ts="1709600000" data-n-a-sg="test-signature"></html>',
                 headers: { 'Content-Type' => 'text/html' })

    stub_request(:post, %r{news\.google\.com/_/DotsSplashUi})
      .to_return(status: 200, body: '["https://www.bbc.com/news/live/uk-politics-68465603"]')

    stub_request(:get, /bbc\.com/)
      .to_return(status: 200,
                 body: '<html><body><article>' \
                       '<p>BBC programmes on iPlayer</p>' \
                       '</article></body></html>',
                 headers: { 'Content-Type' => 'text/html' })
  end
end
