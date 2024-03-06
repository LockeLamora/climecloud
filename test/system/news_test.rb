# frozen_string_literal: true

require 'application_system_test_case'

class NewsTest < ApplicationSystemTestCase
  def setup
    # WebMock.enable!
    stub_request(:get, /news.google.com/).to_return(body: file_fixture('news_response.xml').read)
  end

  test 'visiting the index' do
    visit news_url

    assert_selector 'h1', text: 'News'
  end
end
