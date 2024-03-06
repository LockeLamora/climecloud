# frozen_string_literal: true

require 'application_system_test_case'

class ForecastsTest < ApplicationSystemTestCase
  def setup
    visit '/'
    set_cookies
  end

  test 'visiting the hourly forecast' do
    stub_request(:get, /api.open-meteo.com/).to_return(body: file_fixture('hourly_forecast.json').read)
    visit '/forecast/hourly'
    assert_text 'feels like'
    assert_text '18:00'
    assert_text '6°C (3)'
  end

  test 'visiting the hourly forecast and clicking on daily' do
    stub_request(:get, /api.open-meteo.com/).to_return(body: file_fixture('daily_forecast.json').read)
    visit 'forecast/daily'
    assert_text 'Temp'
    assert_text '2024-03-06'
    assert_text '2mph - 11mph'
  end
end
