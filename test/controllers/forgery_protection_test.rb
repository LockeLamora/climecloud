# frozen_string_literal: true

require 'test_helper'

# config/environments/test.rb turns forgery protection off for the rest of the suite, so
# these tests turn it back on and submit each form the way a browser does: fetch the page,
# take the token out of the markup, send it back. Nothing else here verifies a token.
#
# Rails binds the token to the form's action and method as written, so a form given a bare
# string mints a token for "settings_save" while the request that arrives is for
# "/settings_save". Every form uses a path helper for that reason.
class ForgeryProtectionTest < ActionDispatch::IntegrationTest
  LOCATION = 'lat=51.5;lon=-0.1;city=Testville'
  SAVED = [{ 'id' => 's-one', 'name' => 'Northgate' }].to_json

  setup do
    @protection_was = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    # Every departures action is gated on the Transitland key, and credentials are blank in
    # tests by design — see test_helper.rb.
    stub_api_credentials
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @protection_was
    unstub_api_credentials
  end

  test 'the settings form saves a location rather than being rejected' do
    stub_geocode
    stub_reverse_lookup

    get '/settings'

    assert_response :success
    assert_absolute_action '/settings_save'

    post '/settings_save', params: {
      authenticity_token: token_from(response.body),
      postcode: 'zz1 1zz', country_code: 'GB', metrics: 'hybrid',
      news_default_section: 'HEADLINES'
    }

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

  test 'the which-did-you-mean buttons save the place rather than being rejected' do
    stub_place_candidates

    get '/places_search', params: { query: 'Othertown' }, headers: { 'HTTP_COOKIE' => LOCATION }

    assert_response :success
    assert_absolute_action '/places_save'

    # No cookie header here: it would replace the session cookie the token verifies
    # against, and the save takes its location from the params in any case.
    post '/places_save', params: {
      authenticity_token: token_from(response.body),
      place: 'Othertown, UK', lat: '53.4', lon: '-2.6'
    }

    assert_response :redirect
    assert_equal 'Othertown, UK', JSON.parse(cookies['places_recent']).first['place']
  end

  test 'the page-turn buttons move the bookmark rather than being rejected' do
    get '/games/treasure-hunt/1'

    assert_response :success
    assert_absolute_action '/games/turn'

    post '/games/turn', params: {
      authenticity_token: token_from(response.body), book: 'treasure-hunt', section: '5'
    }

    assert_redirected_to '/games/treasure-hunt/5'
    assert_equal '5', JSON.parse(cookies['CYOA'])['treasure-hunt']
  end

  test 'the forget button clears the saved places rather than being rejected' do
    saved = [{ 'place' => 'Othertown, UK', 'lat' => '53.4', 'lon' => '-2.6' }].to_json
    get '/places', headers: { 'HTTP_COOKIE' => "#{LOCATION};places_recent=#{saved}" }

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
    post '/settings_save', params: {
      authenticity_token: token_from(response.body),
      postcode: 'zz1 1zz', country_code: 'GB', metrics: 'hybrid', news_default_section: 'HEADLINES'
    }

    assert_response :success
    assert_absolute_action '/settings_language'

    post '/settings_language', params: { authenticity_token: token_from(response.body), locale: 'fr' }

    assert_redirected_to root_path
    assert_equal 'fr', cookies['locale']
  end

  private

  # The token is scoped to the action as written, and the request that comes back carries a
  # leading slash, so the action has to be absolute.
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

  # Two candidates, so the search lands on the "which did you mean?" page whose
  # buttons are under test rather than redirecting to the single match.
  def stub_place_candidates
    features = [
      { 'properties' => { 'lat' => 53.4, 'lon' => -2.6, 'formatted' => 'Othertown, UK' } },
      { 'properties' => { 'lat' => 51.2, 'lon' => 0.5, 'formatted' => 'Othertown Green, UK' } }
    ]

    stub_request(:get, %r{api\.geoapify\.com/v1/geocode/autocomplete})
      .to_return(status: 200, body: { 'features' => features }.to_json,
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
