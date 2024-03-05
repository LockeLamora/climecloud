require "test_helper"

class ForecastControllerTest < ActionDispatch::IntegrationTest
  test 'should load the hourly weather forecast page successfully when cookie is set' do
    get '/forecast/hourly', headers: {"COOKIE" => "city=cityname;state=statename;country_code=gb;lat=52.3;lon=1.17;timezone=Europe%2FLondon;metrics=hybrid"}
    assert_response :success
    assert_match 'Hourly forecast', @response.body
    assert_match 'cityname', @response.body
    assert_match 'statename', @response.body
  end

  test 'should load the daily weather forecast page successfully when cookie is set' do
    get '/forecast/daily', headers: {"COOKIE" => "city=cityname;state=statename;country_code=gb;lat=52.3;lon=1.17;timezone=Europe%2FLondon;metrics=hybrid"}
    assert_response :success
    assert_match 'Daily forecast', @response.body
    assert_match 'cityname', @response.body
    assert_match 'statename', @response.body
  end
end
