# frozen_string_literal: true

require 'test_helper'

class IndexControllerTest < ActionDispatch::IntegrationTest
  # The browsers this is built for run little or no JavaScript, so a page that needs any
  # is a page that does not work. Hotwire arrived with the Rails app template, was never
  # used by anything here, and fetched links on hover: on a list of nearby stops, where
  # saving one was a GET, that saved every stop the pointer crossed. Nothing replaced it,
  # so any script tag reappearing in the layout is a regression.
  test 'serves no JavaScript at all' do
    get root_url, headers: { 'COOKIE' => 'lat=57;' }

    assert_response :success
    assert_no_match(/<script/i, @response.body)
    assert_no_match(/importmap/i, @response.body)
    assert_no_match(/\son[a-z]+=/i, @response.body)
  end

  test 'should load the index page successfully when the cookie is set' do
    get root_url, headers: { 'COOKIE' => 'lat=57;' }
    assert_response :success
    assert_match 'Weather forecast', @response.body
    assert_match 'Map directions', @response.body
    assert_match 'News', @response.body
    assert_match 'Change settings', @response.body
  end

  test 'shows the saved location so it is clear the settings took effect' do
    get root_url, headers: { 'COOKIE' => 'lat=57;city=Testville;state=Testshire' }
    assert_response :success
    assert_match 'Testville, Testshire', @response.body
  end

  test 'leaves out the location line when nothing is saved' do
    get root_url, headers: { 'COOKIE' => 'lat=57;' }
    assert_response :success
    assert_match 'Dumbphone utilities dashboard', @response.body
  end

  test 'should redirect to settings when the cookie is not set' do
    get root_url
    assert_response :redirect
    assert_redirected_to settings_url
  end
end
