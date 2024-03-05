require "test_helper"

class NewsControllerTest < ActionDispatch::IntegrationTest
  test 'should load the news index page successfully when cookie is set' do
    get news_url, headers: {"COOKIE" => "country_code=gb;"}
    assert_response :success
    assert_match 'News headlines', @response.body
  end
end
