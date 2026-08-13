# frozen_string_literal: true

require 'test_helper'

# Every one of these round trips would have passed before this file existed, because
# config/environments/test.rb turns forgery protection off and the whole suite runs
# without it. That was harmless for as long as every mutation was a GET, since a GET is
# never verified. The moment saving became a POST, production started rejecting every
# save with an invalid token and nothing here noticed.
#
# What went wrong is worth stating, because the stylesheet-level equivalent is easy to
# repeat: Rails binds the token to the form's action and method, so a form written as
# `form_with url: "settings_save"` produced a token for "settings_save" while the request
# coming back was for "/settings_save". Path helpers avoid it. A bare string does not.
#
# So these tests turn protection back on and submit each form the way a browser does:
# fetch the page, take the token out of the markup, send it back.
class ForgeryProtectionTest < ActionDispatch::IntegrationTest
  LOCATION = 'lat=51.5;lon=-0.1;city=Testville'
  SAVED = [{ 'id' => 's-one', 'name' => 'Northgate' }].to_json

  setup do
    @protection_was = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
  end

  teardown { ActionController::Base.allow_forgery_protection = @protection_was }

  test 'the settings form saves a location rather than being rejected' do
    stub_geocode
    stub_reverse_lookup

    get '/settings'

    assert_response :success
    assert_absolute_action '/settings_save'

    with_api_credentials do
      post '/settings_save', params: {
        authenticity_token: token_from(response.body),
        postcode: 'zz1 1zz', country_code: 'GB', metrics: 'hybrid',
        mapimages: '1', news_default_section: 'HEADLINES'
      }
    end

    assert_response :success
    assert_match 'Location saved as', response.body
    assert_equal '51.5', cookies['lat']
  end

  test 'the nearby stops form saves the stop that was chosen' do
    stub_stops

    get '/departures_add', headers: { 'HTTP_COOKIE' => LOCATION }

    assert_response :success
    assert_absolute_action '/departures_save'

    post '/departures_save', params: {
      authenticity_token: token_from(response.body), id: 's-test-northgate', name: 'Northgate'
    }

    assert_redirected_to departures_path
    assert_equal 'Northgate', JSON.parse(cookies['departures_saved']).first['name']
  end

  test 'the forget button clears the saved stops rather than being rejected' do
    get '/departures', headers: { 'HTTP_COOKIE' => "#{LOCATION};departures_saved=#{SAVED}" }

    assert_response :success
    assert_absolute_action '/departures_forget'

    delete '/departures_forget', params: { authenticity_token: token_from(response.body) }

    assert_redirected_to departures_path
    assert_empty JSON.parse(cookies['departures_saved'].presence || '[]')
  end

  test 'the forget button clears the saved places rather than being rejected' do
    get '/places', params: { lat: '53.4', lon: '-2.6', place: 'Othertown, UK' },
                   headers: { 'HTTP_COOKIE' => LOCATION }

    assert_response :success
    assert_absolute_action '/places_forget'

    delete '/places_forget', params: { authenticity_token: token_from(response.body) }

    assert_redirected_to places_path
    assert_empty JSON.parse(cookies['places_recent'].presence || '[]')
  end

  test 'the language buttons store a choice rather than being rejected' do
    stub_geocode
    stub_reverse_lookup

    get '/settings'
    with_api_credentials do
      post '/settings_save', params: {
        authenticity_token: token_from(response.body),
        postcode: 'zz1 1zz', country_code: 'GB', metrics: 'hybrid', news_default_section: 'HEADLINES'
      }
    end

    assert_response :success
    assert_absolute_action '/settings_language'

    post '/settings_language', params: { authenticity_token: token_from(response.body), locale: 'fr' }

    assert_redirected_to root_path
    assert_equal 'fr', cookies['locale']
  end

  private

  # A relative action is what broke this: the token is scoped to the action as written,
  # and the request that comes back carries a leading slash.
  def assert_absolute_action(path)
    assert_match(
      /<form[^>]*action="#{Regexp.escape(path)}"/,
      response.body,
      "the form action must be #{path}, not a relative string — the token is bound to it"
    )
  end

  def token_from(body)
    token = body[/name="authenticity_token"[^>]*value="([^"]+)"/, 1]

    assert token.present?, 'no authenticity token in the form, so nothing could ever verify'
    CGI.unescapeHTML(token)
  end

  def stub_stops
    body = { 'stops' => [{ 'stop_name' => 'Northgate', 'onestop_id' => 's-test-northgate',
                           'location_type' => 0,
                           'geometry' => { 'coordinates' => [-0.1, 51.5] } }] }

    stub_request(:get, %r{transit\.land/api/v2/rest/stops\?})
      .to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def stub_geocode
    result = {
      'properties' => {
        'lat' => 51.5, 'lon' => -0.1, 'country_code' => 'gb',
        'formatted' => 'Testville, UK', 'postcode' => 'zz1 1zz', 'result_type' => 'postcode'
      }
    }

    stub_request(:get, %r{api\.geoapify\.com/v1/geocode/autocomplete})
      .to_return(status: 200, body: { 'features' => [result] }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def stub_reverse_lookup
    properties = { 'city' => 'Testville', 'state' => 'Wales',
                   'timezone' => { 'name' => 'Europe/London' }, 'country_code' => 'gb' }

    stub_request(:get, %r{api\.geoapify\.com/v1/geocode/reverse})
      .to_return(status: 200, body: { 'features' => [{ 'properties' => properties }] }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end
end
