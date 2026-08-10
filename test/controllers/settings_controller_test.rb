# frozen_string_literal: true

require 'test_helper'

class SettingsControllerTest < ActionDispatch::IntegrationTest
  test 'should load the settings page successfully' do
    get settings_url
    assert_response :success
    assert_match 'Change your settings', @response.body
  end

  test 'assumes the first match and offers the rest when a postcode is ambiguous' do
    stub_geocode(two_results)
    stub_geoapify

    save_settings

    assert_response :success
    assert_match 'Location saved as', @response.body
    assert_match 'See 1 other match', @response.body
    assert_equal 'Newport', cookies['city']
    # The alternatives are a step away, not on this page.
    assert_no_match(/Newport Pagnell/, @response.body)
  end

  test 'lists only the places that were not assumed' do
    stub_geocode(two_results)

    with_api_credentials do
      get '/settings_pick', params: { postcode: 'zz1 1zz', country_code: 'GB', metrics: 'hybrid' }
    end

    assert_response :success
    assert_match 'Newport Pagnell, UK', @response.body
    assert_match 'lat=52.3', @response.body
    assert_match 'Search again', @response.body
  end

  test 'carries the rest of the settings through the choice' do
    stub_geocode(two_results)
    stub_geoapify

    save_settings(metrics: 'metric', news_default_section: 'Science')

    assert_response :success
    assert_match 'metrics=metric', @response.body
    assert_match 'news_default_section=Science', @response.body
  end

  test 'reports when there are no other matches to offer' do
    stub_geocode(one_result)

    with_api_credentials do
      get '/settings_pick', params: { postcode: 'zz1 1zz', country_code: 'GB' }
    end

    assert_response :success
    assert_match 'No other places matched', @response.body
  end

  test 'saves straight away when only one place matches' do
    stub_geocode(one_result)
    stub_geoapify

    save_settings

    assert_response :success
    assert_match 'Location saved as', @response.body
    assert_equal 'Newport', cookies['city']
    assert_equal 'Europe/London', cookies['timezone_name']
    assert_equal 'gb', cookies['country_code']
    assert_equal '52.3', cookies['lat']
  end

  test 'saves the picked place without geocoding again' do
    stub_geoapify

    save_settings(lat: '51.5', lon: '-3.0', place: 'Newport, UK', place_country: 'gb')

    assert_response :success
    assert_match 'Location saved as', @response.body
    assert_equal '51.5', cookies['lat']
    assert_equal '-3.0', cookies['lon']
    assert_not_requested :get, %r{api\.geoapify\.com/v1/geocode/autocomplete}
  end

  test 'still saves the location when the locale lookup fails' do
    stub_geocode(one_result)
    stub_request(:get, %r{api\.geoapify\.com/v1/geocode/reverse}).to_return(status: 500, body: '')

    save_settings

    assert_response :success
    assert_match 'Location saved as', @response.body
    assert_equal '52.3', cookies['lat']
    assert_equal 'auto', cookies['timezone_name']
    assert_equal 'gb', cookies['country_code']
    # Falls back to the geocoded address, which reads better than the raw postcode.
    assert_equal 'Newport, UK', cookies['city']
  end

  test 'reports a postcode that matches nothing' do
    stub_geocode('status' => 'ZERO_RESULTS', 'results' => [])

    save_settings

    assert_response :success
    assert_match 'Could not determine location', @response.body
  end

  private

  def save_settings(extra = {})
    with_api_credentials do
      get '/settings_save', params: {
        postcode: 'zz1 1zz',
        country_code: 'GB',
        metrics: 'hybrid',
        mapimages: '1',
        news_default_section: 'Headlines'
      }.merge(extra)
    end
  end

  def stub_geocode(body)
    stub_request(:get, %r{api\.geoapify\.com/v1/geocode/autocomplete})
      .to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def stub_geoapify
    properties = {
      'city' => 'Newport',
      'state' => 'Wales',
      'timezone' => { 'name' => 'Europe/London' },
      'country_code' => 'gb'
    }

    stub_request(:get, %r{api\.geoapify\.com/v1/geocode/reverse})
      .to_return(status: 200,
                 body: { 'features' => [{ 'properties' => properties }] }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def one_result
    { 'features' => [geocode_result('Newport, UK')] }
  end

  def two_results
    { 'features' => [geocode_result('Newport, UK'), geocode_result('Newport Pagnell, UK')] }
  end

  def geocode_result(address)
    { 'properties' => { 'formatted' => address, 'lat' => 52.3, 'lon' => 1.17, 'country_code' => 'gb' } }
  end
end
