# frozen_string_literal: true

require 'test_helper'

class PlacesControllerTest < ActionDispatch::IntegrationTest
  LOCATION_COOKIES = 'lat=52.3;lon=1.17;city=Testville;metrics=metric'

  test 'lists every category on the menu' do
    get '/places', headers: { 'COOKIE' => LOCATION_COOKIES }

    assert_response :success
    assert_match 'Testville', @response.body
    %w[Petrol Food Shops Cash Toilets Pharmacy Pub Transport].each do |label|
      assert_match label, @response.body
    end
  end

  test 'sends a visitor with no saved location to settings' do
    get '/places'

    assert_redirected_to '/settings'
  end

  test 'lists nearby places closest first with a route to each' do
    stub_places

    with_api_credentials do
      get '/places_list', params: { kind: 'petrol' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    assert_match 'Far Garage', @response.body
    assert_match 'Near Garage', @response.body
    # Closest first, whatever order the API returned them in.
    assert_operator @response.body.index('Near Garage'), :<, @response.body.index('Far Garage')
    assert_match '400m', @response.body
    assert_match '1.2km', @response.body
    assert_match 'directions_plan', @response.body
  end

  test 'asks the api for the grouped categories of the chosen kind' do
    stub_places

    with_api_credentials do
      get '/places_list', params: { kind: 'food' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    assert_requested :get, /api\.geoapify\.com/ do |request|
      request.uri.query.include?('catering.restaurant') &&
        request.uri.query.include?('catering.cafe') &&
        # Geoapify wants longitude before latitude here.
        request.uri.query.include?('circle:1.17,52.3')
    end
  end

  test 'falls back to an address when a place has no name' do
    stub_places([{ 'properties' => { 'address_line1' => 'Behind the market', 'distance' => 50,
                                     'lat' => 52.31, 'lon' => 1.18 } }])

    with_api_credentials do
      get '/places_list', params: { kind: 'toilets' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    assert_match 'Behind the market', @response.body
  end

  test 'says so plainly when nothing is nearby' do
    stub_places([])

    with_api_credentials do
      get '/places_list', params: { kind: 'pharmacy' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    assert_match 'Nothing found within 5km', @response.body
  end

  test 'reports rather than crashes when the places lookup fails' do
    stub_request(:get, %r{api\.geoapify\.com/v2/places}).to_return(status: 500, body: '')

    with_api_credentials do
      get '/places_list', params: { kind: 'shops' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    assert_match 'Could not look up places', @response.body
  end

  test 'sends an unknown category back to the menu' do
    get '/places_list', params: { kind: 'unicorns' }, headers: { 'COOKIE' => LOCATION_COOKIES }

    assert_redirected_to '/places'
  end

  test 'shows imperial distances when that is the saved preference' do
    stub_places

    with_api_credentials do
      get '/places_list', params: { kind: 'petrol' },
                          headers: { 'COOKIE' => 'lat=52.3;lon=1.17;city=Testville;metrics=imperial' }
    end

    assert_response :success
    assert_match '437yd', @response.body
    assert_no_match(/400m/, @response.body)
  end

  private

  def stub_places(features = nil)
    features ||= [
      { 'properties' => { 'name' => 'Far Garage', 'distance' => 1200, 'lat' => 52.4, 'lon' => 1.2 } },
      { 'properties' => { 'name' => 'Near Garage', 'distance' => 400, 'lat' => 52.31, 'lon' => 1.18 } }
    ]

    stub_request(:get, %r{api\.geoapify\.com/v2/places})
      .to_return(status: 200,
                 body: { 'features' => features }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end
end
