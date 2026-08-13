# frozen_string_literal: true

require 'test_helper'

class SettingsControllerTest < ActionDispatch::IntegrationTest
  test 'should load the settings page successfully' do
    get settings_url
    assert_response :success
    assert_match 'Change your settings', @response.body
  end

  test 'asks which country only when the postcode really belongs to more than one' do
    stub_geocode('features' => [geocode_result('Testville, UK'),
                                geocode_result('Testville, France', country: 'fr')])

    save_settings(country_code: nil)

    assert_response :success
    assert_match 'Which country is this postcode in?', @response.body
    # Named in the reader's own language, and only the countries that actually apply.
    assert_match 'United Kingdom', @response.body
    assert_match 'France', @response.body
    assert_carries 'country_code', 'gb'
    assert_carries 'country_code', 'fr'
    # Confirming a country writes the location, so each one is a button rather than a
    # link. The digit has to stay on the button itself or the keypress reaches nothing.
    assert_match(/<button accesskey="1"[^>]*>1 United Kingdom</, @response.body)
    assert_match(/<button accesskey="2"[^>]*>2 France</, @response.body)
    assert_match(/<form class="inline-action"/, @response.body)
  end

  test 'rejects a typo rather than asking which country it belongs to' do
    # What the live geocoder really returns for "abcdefg" once no country narrows it:
    # postcodes in Morocco and Spain that have nothing to do with the input.
    stub_geocode('features' => [geocode_result('Abdelghaya Souahel, Morocco', country: 'ma',
                                                                              postcode: '32354'),
                                geocode_result('Garrafe de Torio, Spain', country: 'es', postcode: '24891')])

    save_settings(country_code: nil, postcode: 'abcdefg')

    assert_response :success
    assert_match 'Could not determine location', @response.body
    assert_no_match(/Which country/, @response.body)
  end

  test 'keeps only the countries whose postcode matches exactly when any does' do
    stub_geocode('features' => [geocode_result('Banja Luka, Bosnia', country: 'ba', postcode: '78000'),
                                geocode_result('Versailles, France', country: 'fr', postcode: '78000'),
                                # A Japanese code beginning 780, which is not this postcode.
                                geocode_result('Kochi, Japan', country: 'jp', postcode: '780-0033')])

    save_settings(country_code: nil, postcode: '78000')

    assert_response :success
    assert_match 'Bosnia', @response.body
    assert_match 'France', @response.body
    assert_no_match(/Japan/, @response.body)
  end

  test 'falls back to postcodes that begin with a partly typed one' do
    stub_geocode('features' => [geocode_result('Testville, UK', postcode: 'zz1 1zz')])
    stub_geoapify

    save_settings(country_code: nil, postcode: 'zz1')

    assert_response :success
    assert_match 'Location saved as', @response.body
  end

  test 'saves without asking when the postcode exists in only one country' do
    stub_geocode(two_results)
    stub_geoapify

    save_settings(country_code: nil)

    assert_response :success
    assert_match 'Location saved as', @response.body
    # Asking would be a keypress spent on a question with one possible answer.
    assert_no_match(/Which country/, @response.body)
    assert_equal 'gb', cookies['country_code']
  end

  test 'carries the other settings through the country choice' do
    stub_geocode('features' => [geocode_result('Testville, UK'),
                                geocode_result('Testville, France', country: 'fr')])

    save_settings(country_code: nil, metrics: 'metric', news_default_section: 'Science')

    assert_response :success
    assert_carries 'metrics', 'metric'
    assert_carries 'news_default_section', 'Science'
    assert_carries 'postcode', 'zz1 1zz'
  end

  test 'stops asking once the country has been confirmed' do
    stub_geocode(one_result)
    stub_geoapify

    save_settings(country_code: 'gb')

    assert_response :success
    assert_match 'Location saved as', @response.body
    assert_no_match(/Which country/, @response.body)
  end

  test 'credits openstreetmap on the pages built from its data' do
    stub_geocode('features' => [geocode_result('Testville, UK'),
                                geocode_result('Testville, France', country: 'fr')])

    save_settings(country_code: nil)

    assert_response :success
    # Geoapify serves this string with every record, because the addresses underneath
    # are OpenStreetMap's.
    assert_match '© OpenStreetMap contributors', @response.body
    assert_match %r{<br />\s*<br />\s*<div class='credit'>}, @response.body
  end

  test 'the form asks the browser for a postcode before it submits' do
    get settings_url

    assert_response :success
    assert_match(/name="postcode"[^>]*required|required[^>]*name="postcode"/, @response.body)
  end

  test 'offers no country dropdown on the form' do
    get settings_url

    assert_response :success
    # A four way pad and a list of every country on earth, most of which could never
    # match the postcode being typed.
    assert_no_match(/<select[^>]+country/, @response.body)
    assert_match 'name="postcode"', @response.body
  end

  test 'assumes the first match and offers the rest when a postcode is ambiguous' do
    stub_geocode(two_results)
    stub_geoapify

    save_settings

    assert_response :success
    assert_match 'Location saved as', @response.body
    assert_match 'See 1 other match', @response.body
    assert_equal 'Testville', cookies['city']
    # The alternatives are a step away, not on this page.
    assert_no_match(/Testville Magna/, @response.body)
  end

  test 'lists only the places that were not assumed' do
    stub_geocode(two_results)

    with_api_credentials do
      get '/settings_pick', params: { postcode: 'zz1 1zz', country_code: 'GB', metrics: 'hybrid' }
    end

    assert_response :success
    assert_match 'Testville Magna, UK', @response.body
    assert_carries 'lat', '52.3'
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

  # Choosing a language stores it, so it cannot be a link either. This list is the one
  # way back to a language you can read, so its number keys have to keep working.
  test 'offers each language as a numbered button rather than a link' do
    stub_geocode(one_result)
    stub_geoapify

    save_settings

    assert_response :success
    assert_no_match(/href="[^"]*settings_language/, @response.body)
    assert_match %r{<form class="inline-action" method="post" action="/settings_language">}, @response.body
    assert_match(/<button accesskey="1"/, @response.body)
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
    assert_equal 'Testville', cookies['city']
    assert_equal 'Europe/London', cookies['timezone_name']
    assert_equal 'gb', cookies['country_code']
    assert_equal '52.3', cookies['lat']
  end

  test 'saves the picked place without geocoding again' do
    stub_geoapify

    save_settings(lat: '52.5', lon: '1.5', place: 'Testville, UK', place_country: 'gb')

    assert_response :success
    assert_match 'Location saved as', @response.body
    assert_equal '52.5', cookies['lat']
    assert_equal '1.5', cookies['lon']
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
    assert_equal 'Testville, UK', cookies['city']
  end

  test 'reports a postcode that matches nothing' do
    stub_geocode('status' => 'ZERO_RESULTS', 'results' => [])

    save_settings

    assert_response :success
    assert_match 'Could not determine location', @response.body
  end

  private

  # Storing a location is a POST, so the settings gathered so far ride through the country
  # and candidate lists as fields on each button's form rather than in a query string.
  def assert_carries(field, value)
    assert_match(
      /<input type="hidden" name="#{Regexp.escape(field)}" value="#{Regexp.escape(value)}"/,
      @response.body,
      "the form does not carry #{field}=#{value} through to the next step"
    )
  end

  # Pass country_code: nil to submit the form as it now stands, with no country on it.
  def save_settings(extra = {})
    query = {
      postcode: 'zz1 1zz',
      country_code: 'GB',
      metrics: 'hybrid',
      mapimages: '1',
      news_default_section: 'Headlines'
    }.merge(extra).compact

    with_api_credentials { post '/settings_save', params: query }
  end

  def stub_geocode(body)
    stub_request(:get, %r{api\.geoapify\.com/v1/geocode/autocomplete})
      .to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def stub_geoapify
    properties = {
      'city' => 'Testville',
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
    { 'features' => [geocode_result('Testville, UK')] }
  end

  def two_results
    { 'features' => [geocode_result('Testville, UK'), geocode_result('Testville Magna, UK')] }
  end

  # The postcode defaults to the one the other tests type, so a result matches unless a
  # test is deliberately about a postcode that does not.
  def geocode_result(address, country: 'gb', postcode: 'zz1 1zz')
    {
      'properties' => {
        'formatted' => address,
        'lat' => 52.3,
        'lon' => 1.17,
        'country_code' => country,
        'postcode' => postcode
      }
    }
  end
end
