# frozen_string_literal: true

require 'test_helper'

class IndexControllerTest < ActionDispatch::IntegrationTest
  test 'should load the index page successfully when the cookie is set' do
    get root_url, headers: { 'COOKIE' => 'lat=57;' }
    assert_response :success
    assert_match 'Weather forecast', @response.body
    assert_match 'Map directions', @response.body
    assert_match 'News', @response.body
    assert_match 'Change settings', @response.body
  end

  test 'should redirect to settings when the cookie is not set' do
    get root_url
    assert_response :redirect
    assert_redirected_to settings_url
  end
end
