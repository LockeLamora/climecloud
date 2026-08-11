# frozen_string_literal: true

require 'test_helper'

class DeparturesControllerTest < ActionDispatch::IntegrationTest
  COOKIES = 'lat=51.5;lon=-0.1;city=Testville'
  SAVED = [{ 'id' => 's-test-northgate', 'name' => 'Northgate' }].to_json

  test 'lists nearby boarding points and leaves out the station they sit inside' do
    stub_stops('stops' => [
                 station('Testville Bus Station', 's-test-station'),
                 platform('Testville Bus Station stand A', 's-test-a'),
                 platform('Testville Bus Station stand B', 's-test-b')
               ])

    get '/departures_add', headers: { 'HTTP_COOKIE' => COOKIES }

    assert_response :success
    assert_match 'stand A', @response.body
    assert_match 'stand B', @response.body
    # The station itself never carries departures, so offering it only ever led to a
    # page claiming nothing was due.
    assert_no_match(/Testville Bus Station</, @response.body)
  end

  test 'tells stands sharing a name apart by their stand number' do
    stub_stops('stops' => [
                 platform('Market Square', 's-test-one', platform_code: '1'),
                 platform('Market Square', 's-test-two', platform_code: '2')
               ])

    get '/departures_add', headers: { 'HTTP_COOKIE' => COOKIES }

    assert_response :success
    assert_match 'Market Square (1)', @response.body
    assert_match 'Market Square (2)', @response.body
  end

  test 'offers one entry per name when the feed gives nothing to tell them apart' do
    stub_stops('stops' => [
                 platform('Market Square', 's-test-one'),
                 platform('Market Square', 's-test-two')
               ])

    get '/departures_add', headers: { 'HTTP_COOKIE' => COOKIES }

    assert_response :success
    assert_equal 1, @response.body.scan('Market Square').length
  end

  test 'shows where each service is going rather than where it already is' do
    stub_departures('stops' => [{
                      'stop_name' => 'Northgate',
                      'departures' => [
                        departure('14:09:00', route: '22', trip_headsign: 'Eastport Centre'),
                        departure('14:18:00', route: '24', trip_headsign: 'Westhaven Station')
                      ]
                    }])

    get '/departures_stop?id=s-test-northgate', headers: { 'HTTP_COOKIE' => "#{COOKIES};departures_saved=#{SAVED}" }

    assert_response :success
    assert_match 'Eastport Centre', @response.body
    assert_match 'Westhaven Station', @response.body
    assert_match '14:09', @response.body
  end

  test 'ignores a headsign that only repeats the stop it is departing from' do
    stub_departures('stops' => [{
                      'stop_name' => 'Northgate stand C',
                      'departures' => [
                        departure('14:09:00', route: '22', stop_headsign: 'stand C',
                                              route_long_name: 'Northgate - Eastport')
                      ]
                    }])

    get '/departures_stop?id=s-test-northgate', headers: { 'HTTP_COOKIE' => "#{COOKIES};departures_saved=#{SAVED}" }

    assert_response :success
    # The route's own name says which way the line runs, which the stand name does not.
    assert_match 'Northgate - Eastport', @response.body
    assert_no_match(/stand C/, @response.body)
  end

  test 'keeps a destination that happens to contain the name of the stop' do
    stub_departures('stops' => [{
                      'stop_name' => 'Eastport',
                      'departures' => [departure('14:09:00', route: '22', trip_headsign: 'Eastport Interchange')]
                    }])

    get '/departures_stop?id=s-test-northgate', headers: { 'HTTP_COOKIE' => "#{COOKIES};departures_saved=#{SAVED}" }

    assert_response :success
    assert_match 'Eastport Interchange', @response.body
  end

  test 'merges the departures of every stop entry the feed returns for one stop' do
    stub_departures('stops' => [
                      { 'stop_name' => 'Northgate',
                        'departures' => [departure('14:20:00', route: '22', trip_headsign: 'Eastport Centre')] },
                      { 'stop_name' => 'Northgate',
                        'departures' => [departure('14:05:00', route: '50', trip_headsign: 'Westhaven Station')] }
                    ])

    get '/departures_stop?id=s-test-northgate', headers: { 'HTTP_COOKIE' => "#{COOKIES};departures_saved=#{SAVED}" }

    assert_response :success
    # Reading only the first entry lost every departure held by the rest.
    assert_match 'Eastport Centre', @response.body
    assert_match 'Westhaven Station', @response.body
    # And the merged list still reads earliest first.
    assert_operator @response.body.index('14:05'), :<, @response.body.index('14:20')
  end

  test 'marks a real time departure as live and says the rest are timetabled' do
    stub_departures('stops' => [{
                      'stop_name' => 'Northgate',
                      'departures' => [
                        departure('14:09:00', route: '22', trip_headsign: 'Eastport Centre',
                                              schedule_relationship: 'SCHEDULED'),
                        departure('14:18:00', route: '24', trip_headsign: 'Westhaven Station')
                      ]
                    }])

    get '/departures_stop?id=s-test-northgate', headers: { 'HTTP_COOKIE' => "#{COOKIES};departures_saved=#{SAVED}" }

    assert_response :success
    assert_match '(live)', @response.body
    assert_match 'Times are from the timetable unless marked live', @response.body
    assert_equal 1, @response.body.scan('(live)').length
  end

  test 'says so rather than crashing when a departure has no destination at all' do
    stub_departures('stops' => [{ 'stop_name' => 'Northgate', 'departures' => [departure('14:09:00', route: '22')] }])

    get '/departures_stop?id=s-test-northgate', headers: { 'HTTP_COOKIE' => "#{COOKIES};departures_saved=#{SAVED}" }

    assert_response :success
    assert_match 'Destination not given', @response.body
  end

  test 'reports rather than crashes when transitland is unreachable' do
    stub_request(:get, %r{transit\.land/api/v2/rest/stops/.+/departures}).to_return(status: 500, body: '')

    get '/departures_stop?id=s-test-northgate', headers: { 'HTTP_COOKIE' => "#{COOKIES};departures_saved=#{SAVED}" }

    assert_response :success
    assert_match 'Could not reach the departures service', @response.body
  end

  private

  def stub_stops(body)
    stub_request(:get, %r{transit\.land/api/v2/rest/stops\?}).to_return(
      status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' }
    )
  end

  def stub_departures(body)
    stub_request(:get, %r{transit\.land/api/v2/rest/stops/.+/departures}).to_return(
      status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' }
    )
  end

  def station(name, id)
    { 'stop_name' => name, 'onestop_id' => id, 'location_type' => 1 }
  end

  def platform(name, id, platform_code: nil)
    { 'stop_name' => name, 'onestop_id' => id, 'location_type' => 0, 'platform_code' => platform_code }
  end

  def departure(time, fields)
    {
      'departure_time' => time,
      'departure' => { 'scheduled' => time, 'estimated' => nil },
      'schedule_relationship' => fields[:schedule_relationship] || 'STATIC',
      'stop_headsign' => fields[:stop_headsign],
      'trip' => {
        'trip_headsign' => fields[:trip_headsign],
        'route' => {
          'route_short_name' => fields[:route],
          'route_long_name' => fields[:route_long_name]
        }
      }
    }
  end
end
