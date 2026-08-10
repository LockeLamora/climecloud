# frozen_string_literal: true

require 'test_helper'

class ForecastControllerTest < ActionDispatch::IntegrationTest
  LOCATION_COOKIES = 'city=cityname;state=statename;country_code=gb;'\
                     'lat=52.3;lon=1.17;timezone_name=Europe%2FLondon'

  test 'should load the hourly weather forecast page successfully when cookie is set' do
    get '/forecast/hourly',
        headers: { 'COOKIE' => 'city=cityname;state=statename;country_code=gb;'\
        'lat=52.3;lon=1.17;timezone=Europe%2FLondon;metrics=hybrid' }
    assert_response :success
    assert_match 'Hourly forecast', @response.body
    assert_match 'cityname', @response.body
    assert_match 'statename', @response.body
  end

  test 'should load the daily weather forecast page successfully when cookie is set' do
    get '/forecast/daily',
        headers: { 'COOKIE' => 'city=cityname;state=statename;country_code=gb;'\
        'lat=52.3;lon=1.17;timezone=Europe%2FLondon;metrics=hybrid' }
    assert_response :success
    assert_match 'Daily forecast', @response.body
    assert_match 'cityname', @response.body
    assert_match 'statename', @response.body
  end

  test 'asks open-meteo for kmh when the metric setting is chosen' do
    stub_forecast

    get '/forecast/hourly', headers: { 'COOKIE' => "#{LOCATION_COOKIES};metrics=metric" }

    assert_response :success
    assert_match 'Hourly forecast', @response.body
    assert_requested :get, %r{api\.open-meteo\.com.*wind_speed_unit=kmh}
  end

  test 'falls back to an automatic timezone when none was saved' do
    stub_forecast

    get '/forecast/hourly', headers: { 'COOKIE' => 'lat=52.3;lon=1.17;metrics=metric' }

    assert_response :success
    assert_requested :get, %r{api\.open-meteo\.com.*timezone=auto}
  end

  test 'reports rather than crashes when the forecast cannot be fetched' do
    stub_request(:get, %r{api\.open-meteo\.com})
      .to_return(status: 400, body: '{"error":true,"reason":"invalid unit"}')

    get '/forecast/hourly', headers: { 'COOKIE' => "#{LOCATION_COOKIES};metrics=metric" }

    assert_response :success
    assert_match 'Could not fetch the forecast', @response.body
    assert_match 'Set your location again', @response.body
  end

  test 'sends a visitor with no saved location back to settings' do
    get '/forecast/hourly', headers: { 'COOKIE' => 'lat=' }

    assert_redirected_to '/settings'
  end

  private

  def stub_forecast
    body = {
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
      }
    }

    stub_request(:get, %r{api\.open-meteo\.com})
      .to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end
end
