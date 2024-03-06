# frozen_string_literal: true

require 'application_system_test_case'

class NewsTest < ApplicationSystemTestCase
  def setup; end

  test 'visiting the index and then an article' do
    stub_request(:get, /news.google.com/).to_return(body: file_fixture('news_response.xml').read)
    visit news_url
    assert_text 'Budget 2024 live: Jeremy Hunt'
    first('.news > ul > a').click
    assert_text "We've already taken you through"
  end

  test 'visiting the index and clicking on a topic' do
    stub_request(:get, /news.google.com/).to_return(body: file_fixture('news_response.xml').read)
    visit news_url
    stub_request(:get, /news.google.com/).to_return(body: file_fixture('science-news.xml').read)
    click_link('Science')
    assert_text "'Nightmarish' sea lizard that roamed the seas 66"
  end
end
