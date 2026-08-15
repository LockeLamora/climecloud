# frozen_string_literal: true

require 'test_helper'

class ForecastControllerTest < ActionDispatch::IntegrationTest
  LOCATION_COOKIES = 'city=cityname;state=statename;country_code=gb;'\
                     'lat=52.3;lon=1.17;timezone_name=Europe%2FLondon'

  test 'should load the hourly weather forecast page successfully when cookie is set' do
    stub_forecast

    get '/forecast/hourly',
        headers: { 'COOKIE' => 'city=cityname;state=statename;country_code=gb;'\
        'lat=52.3;lon=1.17;timezone=Europe%2FLondon;metrics=hybrid' }
    assert_response :success
    assert_match 'Hourly forecast', @response.body
    assert_match 'cityname', @response.body
    assert_match 'statename', @response.body
  end

  test 'should load the daily weather forecast page successfully when cookie is set' do
    stub_forecast

    get '/forecast/daily',
        headers: { 'COOKIE' => 'city=cityname;state=statename;country_code=gb;'\
        'lat=52.3;lon=1.17;timezone=Europe%2FLondon;metrics=hybrid' }
    assert_response :success
    assert_match 'Daily forecast', @response.body
    assert_match 'cityname', @response.body
    assert_match 'statename', @response.body
  end

  test 'credits open-meteo on both forecast pages, as the licence requires' do
    stub_forecast

    ['/forecast/hourly', '/forecast/daily'].each do |path|
      get path, headers: { 'COOKIE' => "#{LOCATION_COOKIES};metrics=hybrid" }

      assert_response :success
      assert_match 'Weather data by Open-Meteo.com', @response.body, "#{path} carries no attribution"
      assert_match 'https://open-meteo.com', @response.body, "#{path} does not link the source"
      assert_match "class='credit'", @response.body, "#{path} does not style the attribution"
      # The same gap as the transport credit, and only one of them: the views supplied
      # their own breaks as well, which spaced the two credits differently.
      assert_match %r{<br />\s*<br />\s*<div class='credit'>}, @response.body, "#{path} credit is not spaced"
      assert_no_match(%r{<br />\s*<br />\s*<br />\s*<br />\s*<div class='credit'>}, @response.body)
    end
  end

  test 'asks open-meteo for kmh when the metric setting is chosen' do
    stub_forecast

    get '/forecast/hourly', headers: { 'COOKIE' => "#{LOCATION_COOKIES};metrics=metric" }

    assert_response :success
    assert_match 'Hourly forecast', @response.body
    assert_requested :get, /api\.open-meteo\.com.*wind_speed_unit=kmh/
  end

  test 'falls back to an automatic timezone when none was saved' do
    stub_forecast

    get '/forecast/hourly', headers: { 'COOKIE' => 'lat=52.3;lon=1.17;metrics=metric' }

    assert_response :success
    assert_requested :get, /api\.open-meteo\.com.*timezone=auto/
  end

  test 'reports rather than crashes when the forecast cannot be fetched' do
    stub_request(:get, /api\.open-meteo\.com/)
      .to_return(status: 400, body: '{"error":true,"reason":"invalid unit"}')

    get '/forecast/hourly', headers: { 'COOKIE' => "#{LOCATION_COOKIES};metrics=metric" }

    assert_response :success
    assert_match 'Could not fetch the forecast', @response.body
    assert_match 'Set your location again', @response.body
  end

  # On the phosphor styles the table travels as a few glyph images — each row one monospace
  # line — because a hundred cells is a page the handset gives up assembling, and a fixed
  # table at four columns wraps its own brackets onto lines of their own.
  test 'the phosphor styles draw the forecast as a terminal table' do
    stub_request(:get, /api\.open-meteo\.com/)
      .to_return(status: 200, body: file_fixture('hourly_forecast.json').read,
                 headers: { 'Content-Type' => 'application/json' })

    get '/forecast/hourly', headers: { 'COOKIE' => "#{LOCATION_COOKIES};theme=crt-amber" }

    assert_response :success
    assert_no_match(/<table>/, @response.body, 'the cell table has nothing lit about it')
    glyphs = @response.body.scan(%r{<img src="/phosphor}).length

    assert_operator glyphs, :>, 1, 'the forecast lost its screen entirely'
    assert_operator glyphs, :<=, 10, 'this many images is a page the handset gives up on'
  end

  test 'falls back to a relay when open-meteo refuses on the daily limit' do
    stub_request(:get, /api\.open-meteo\.com/)
      .to_return(status: 429, body: '{"error":true,"reason":"Daily API request limit exceeded."}')
    stub_request(:get, /r\.jina\.ai/)
      .to_return(status: 200, body: forecast_body.to_json, headers: { 'Content-Type' => 'application/json' })

    get '/forecast/hourly', headers: { 'COOKIE' => "#{LOCATION_COOKIES};metrics=metric" }

    assert_response :success
    assert_match 'Hourly forecast', @response.body
    assert_no_match(/weather service is busy/, @response.body)
    # That relay takes its target in the path rather than a query string, and needs the
    # header or it answers with the page rewritten for a language model.
    assert_requested :get, %r{r\.jina\.ai/https://api\.open-meteo\.com},
                     headers: { 'x-return-format' => 'text' }
  end

  test 'tries the next relay when the first one is no help either' do
    stub_request(:get, /api\.open-meteo\.com/).to_return(status: 429, body: '{"error":true}')
    stub_request(:get, /r\.jina\.ai/).to_return(status: 503, body: '')
    stub_request(:get, /allorigins\.win/)
      .to_return(status: 200, body: forecast_body.to_json, headers: { 'Content-Type' => 'application/json' })

    get '/forecast/hourly', headers: { 'COOKIE' => "#{LOCATION_COOKIES};metrics=metric" }

    assert_response :success
    assert_match 'Hourly forecast', @response.body
  end

  test 'does not relay anything other than a rate limit' do
    stub_request(:get, /api\.open-meteo\.com/)
      .to_return(status: 400, body: '{"error":true,"reason":"invalid unit"}')

    get '/forecast/hourly', headers: { 'COOKIE' => "#{LOCATION_COOKIES};metrics=metric" }

    assert_response :success
    assert_not_requested :get, /r\.jina\.ai/
    assert_not_requested :get, /allorigins\.win/
    assert_not_requested :get, /codetabs\.com/
  end

  test 'still says the service is busy when every relay fails too' do
    stub_request(:get, /api\.open-meteo\.com/)
      .to_return(status: 429, body: '{"error":true,"reason":"Daily API request limit exceeded."}')
    stub_request(:get, /r\.jina\.ai/).to_return(status: 503, body: '')
    stub_request(:get, /allorigins\.win/).to_return(status: 503, body: '')
    stub_request(:get, /codetabs\.com/).to_return(status: 503, body: '')

    get '/forecast/hourly', headers: { 'COOKIE' => "#{LOCATION_COOKIES};metrics=metric" }

    assert_response :success
    assert_match 'weather service is busy', @response.body
    # The location is fine, so it must not be what gets blamed.
    assert_match 'Your location is saved', @response.body
    assert_no_match(/Set your location again/, @response.body)
  end

  # The relays below the first take their target escaped in a query string. Sending it
  # raw put a bare ? and & into their URL and they answered about a truncated request.
  test 'hands the target to each relay the way that relay wants it' do
    stub_request(:get, /api\.open-meteo\.com/).to_return(status: 429, body: '{"error":true}')
    stub_request(:get, /r\.jina\.ai/).to_return(status: 503, body: '')
    stub_request(:get, /allorigins\.win/)
      .to_return(status: 200, body: forecast_body.to_json, headers: { 'Content-Type' => 'application/json' })

    get '/forecast/hourly', headers: { 'COOKIE' => "#{LOCATION_COOKIES};metrics=metric" }

    assert_response :success
    # The escaped ampersands are the point: unescaped, everything after the first one
    # would be read as a parameter of the relay rather than part of the target.
    assert_requested :get, %r{allorigins\.win/raw\?url=https://api\.open-meteo\.com.*%26longitude}
  end

  # A budget across all the relays together, so three hanging relays cannot each spend
  # their full timeout before the reader is told the service is busy.
  test 'stops trying relays once the time budget is spent' do
    stub_request(:get, /api\.open-meteo\.com/).to_return(status: 429, body: '{"error":true}')
    stub_request(:get, /r\.jina\.ai/).to_return { raise Net::ReadTimeout }
    stub_request(:get, /allorigins\.win/).to_return { raise Net::ReadTimeout }
    stub_request(:get, /codetabs\.com/).to_return { raise Net::ReadTimeout }

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    get '/forecast/hourly', headers: { 'COOKIE' => "#{LOCATION_COOKIES};metrics=metric" }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_response :success
    assert_match 'weather service is busy', @response.body
    assert_operator elapsed, :<, Relay::BUDGET_SECONDS + Relay::TIMEOUT_SECONDS
  end

  test 'sends a visitor with no saved location back to settings' do
    get '/forecast/hourly', headers: { 'COOKIE' => 'lat=' }

    assert_redirected_to '/settings'
  end

  # Crawlers carry no cookies, so they must never reach the API and spend quota.
  test 'does not call open-meteo at all when no location is saved' do
    get '/forecast/hourly'
    get '/forecast/daily'

    assert_not_requested :get, /api\.open-meteo\.com/
  end

  private

  def stub_forecast
    stub_request(:get, /api\.open-meteo\.com/)
      .to_return(status: 200, body: forecast_body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def forecast_body
    {
      'hourly' => {
        'time' => ['2026-08-10T09:00'],
        'temperature_2m' => [15.2],
        'apparent_temperature' => [14.1],
        'precipitation_probability' => [10],
        'rain' => [0.0],
        'wind_speed_10m' => [12.4],
        'snowfall' => [0.0]
      },
      'hourly_units' => {
        'rain' => 'mm',
        'temperature_2m' => '°C',
        'wind_speed_10m' => 'km/h',
        'snowfall' => 'cm'
      },
      # The daily page asks for different fields, so a body carrying only the hourly
      # ones sends it to the "could not fetch" page instead of rendering a forecast.
      'daily' => {
        'time' => ['2026-08-10'],
        'temperature_2m_max' => [18.4],
        'temperature_2m_min' => [11.2],
        'precipitation_probability_mean' => [20],
        'rain_sum' => [0.4],
        'snowfall_sum' => [0.0],
        'wind_speed_10m_max' => [19.1],
        'wind_speed_10m_min' => [6.3]
      },
      'daily_units' => {
        'rain_sum' => 'mm',
        'temperature_2m_max' => '°C',
        'wind_speed_10m_max' => 'km/h',
        'snowfall_sum' => 'cm'
      }
    }
  end
end
