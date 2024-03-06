# frozen_string_literal: true

require 'application_system_test_case'

class NewsTest < ApplicationSystemTestCase
  def setup
    stub_request(:get, /news.google.com/).to_return(body: file_fixture('news_response.xml').read)
  end

  test 'visiting the index and then an article' do
    visit news_url
    assert_text 'Budget 2024 live: Jeremy Hunt'
    first('.news > ul > a').click
    assert_text "We've already taken you through"
  end
end
