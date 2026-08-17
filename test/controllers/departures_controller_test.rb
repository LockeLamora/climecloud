# frozen_string_literal: true

require 'test_helper'

class DeparturesControllerTest < ActionDispatch::IntegrationTest
  COOKIES = 'lat=51.5;lon=-0.1;city=Testville'
  SAVED = [{ 'id' => 's-test-northgate', 'name' => 'Northgate' }].to_json

  # Every action here is gated on the Transitland key, which does not decrypt under
  # test. Without a stand-in every request redirects to the menu and every assertion
  # below is really only testing that redirect.
  setup { stub_api_credentials }
  teardown { unstub_api_credentials }

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
    # Counted as buttons rather than as occurrences of the name: each stop is a posted
    # form, so its name appears both on the button and in the field the form carries.
    assert_equal 1, @response.body.scan(/<button[^>]*>Market Square</).length
  end

  test 'lists the nearest stops first however the feed happens to order them' do
    stub_stops('stops' => [
                 platform('Half A Mile Off', 's-test-far', lat: 51.507, lon: -0.1),
                 platform('Just Round The Corner', 's-test-near', lat: 51.5005, lon: -0.1),
                 platform('Down The Road', 's-test-mid', lat: 51.502, lon: -0.1)
               ])

    get '/departures_add', headers: { 'HTTP_COOKIE' => COOKIES }

    assert_response :success
    # The search comes back unordered, so without sorting the ten kept are arbitrary.
    assert_operator @response.body.index('Just Round The Corner'), :<, @response.body.index('Down The Road')
    assert_operator @response.body.index('Down The Road'), :<, @response.body.index('Half A Mile Off')
  end

  test 'reaches the stops past the first page rather than discarding them' do
    stub_stops('stops' => (1..14).map { |n| platform("Stop #{n}", "s-test-#{n}", lat: 51.5 + (n / 10_000.0)) })

    get '/departures_add', headers: { 'HTTP_COOKIE' => COOKIES }

    assert_response :success
    assert_match 'Stop 10', @response.body
    assert_no_match(/Stop 11/, @response.body)
    assert_match 'More stops', @response.body
    assert_no_match(/Previous stops/, @response.body)

    get '/departures_add?page=1', headers: { 'HTTP_COOKIE' => COOKIES }

    assert_response :success
    assert_match 'Stop 11', @response.body
    assert_match 'Stop 14', @response.body
    assert_match 'Previous stops', @response.body
    # Nothing beyond the last page, so no link to a page that would come back empty.
    assert_no_match(/More stops/, @response.body)
  end

  test 'treats a page number that makes no sense as the first page' do
    stub_stops('stops' => (1..3).map { |n| platform("Stop #{n}", "s-test-#{n}", lat: 51.5 + (n / 10_000.0)) })

    get '/departures_add?page=-4', headers: { 'HTTP_COOKIE' => COOKIES }

    assert_response :success
    assert_match 'Stop 1', @response.body
  end

  # On the phosphor styles the timetable travels as glyph images, each departure one
  # monospace line, and the attribution goes as the quiet glyph — the dim tone at the small
  # size — so nothing on the page sits unlit beside the glowing rows.
  test 'a phosphor timetable is drawn as glyph rows with a quiet credit' do
    stub_departures('stops' => [{
                      'stop_name' => 'Northgate',
                      'departures' => [departure('14:09:00', route: '22', pattern: 41,
                                                             route_id: 'r-test-22', trip_id: 900,
                                                             trip_headsign: 'City Centre')]
                    }])

    get '/departures_stop?id=s-test-northgate',
        headers: { 'HTTP_COOKIE' => "#{COOKIES};theme=crt-amber;departures_saved=#{SAVED}" }

    assert_response :success
    rows = CGI.unescape(@response.body[%r{/glyph\?[^"]*14%3A09[^"]*}].to_s.gsub('&amp;', '&'))

    assert_match(/14:09.*22.*City Centre/m, rows, 'the departure is not in a glyph row')
    assert_match(%r{/glyph\?q=1[^"]*t=[^"]*[Tt]ransitland}, @response.body,
                 'the credit is not the quiet glyph')
  end

  test 'names the destination from the end of the trip when the feed gives no headsign' do
    stub_departures('stops' => [{
                      'stop_name' => 'Northgate',
                      'departures' => [
                        departure('14:09:00', route: '22', pattern: 41, route_id: 'r-test-22', trip_id: 900),
                        departure('14:39:00', route: '22', pattern: 41, route_id: 'r-test-22', trip_id: 901)
                      ]
                    }])
    stub_trip('r-test-22', 900, ['Northgate', 'Midwich', 'Eastport Centre'])

    get '/departures_stop?id=s-test-northgate', headers: { 'HTTP_COOKIE' => "#{COOKIES};departures_saved=#{SAVED}" }

    assert_response :success
    assert_equal 2, @response.body.scan('Eastport Centre').length
    # Both trips run the same stop pattern, so one lookup names them both.
    assert_requested :get, %r{transit\.land/api/v2/rest/routes/r-test-22/trips/900}, times: 1
  end

  test 'leaves the times alone when the destination lookup fails' do
    stub_departures('stops' => [{
                      'stop_name' => 'Northgate',
                      'departures' => [departure('14:09:00', route: '22', pattern: 41, route_id: 'r-test-22',
                                                             trip_id: 900)]
                    }])
    stub_request(:get, %r{transit\.land/api/v2/rest/routes/.+/trips/}).to_return(status: 500, body: '')

    get '/departures_stop?id=s-test-northgate', headers: { 'HTTP_COOKIE' => "#{COOKIES};departures_saved=#{SAVED}" }

    assert_response :success
    assert_match '14:09', @response.body
    assert_match 'Destination not given', @response.body
    # A missing nicety is no reason to put an error across a page that has the times.
    assert_no_match(/Could not reach/, @response.body)
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

  test 'shows one row per journey when two feeds both describe it' do
    stub_departures('stops' => [
                      { 'stop_name' => 'Railway Station',
                        'departures' => [departure('14:21:00', route: '78', trip_headsign: 'Market Square')] },
                      # The same bus, from a second feed covering the same stop, seconds apart.
                      { 'stop_name' => 'Railway Station',
                        'departures' => [departure('14:21:02', route: '78', trip_headsign: 'Market Square')] }
                    ])

    get '/departures_stop?id=s-test-northgate', headers: { 'HTTP_COOKIE' => "#{COOKIES};departures_saved=#{SAVED}" }

    assert_response :success
    assert_equal 1, @response.body.scan('Market Square').length
  end

  test 'keeps two services of one route leaving the same minute for different places' do
    stub_departures('stops' => [{
                      'stop_name' => 'Railway Station',
                      'departures' => [
                        departure('14:21:00', route: '78', trip_headsign: 'Market Square'),
                        departure('14:21:00', route: '78', trip_headsign: 'Westhaven Station')
                      ]
                    }])

    get '/departures_stop?id=s-test-northgate', headers: { 'HTTP_COOKIE' => "#{COOKIES};departures_saved=#{SAVED}" }

    assert_response :success
    assert_match 'Market Square', @response.body
    assert_match 'Westhaven Station', @response.body
  end

  test 'says what kind of vehicle is coming, since a stop name can suggest another' do
    stub_departures('stops' => [{
                      'stop_name' => 'Railway Station',
                      'departures' => [
                        departure('14:21:00', route: '78', trip_headsign: 'Market Square', route_type: 3),
                        departure('14:44:00', route: 'NR', trip_headsign: 'Westhaven', route_type: 2)
                      ]
                    }])

    get '/departures_stop?id=s-test-northgate', headers: { 'HTTP_COOKIE' => "#{COOKIES};departures_saved=#{SAVED}" }

    assert_response :success
    # The stop is named after a station but the 78 is a bus outside it.
    assert_match '(bus)', @response.body
    assert_match '(rail)', @response.body
  end

  test 'reads the extended route types agencies publish instead of the original ones' do
    stub_departures('stops' => [{
                      'stop_name' => 'Railway Station',
                      'departures' => [departure('14:21:00', route: '78', trip_headsign: 'Market Square',
                                                             route_type: 702)]
                    }])

    get '/departures_stop?id=s-test-northgate', headers: { 'HTTP_COOKIE' => "#{COOKIES};departures_saved=#{SAVED}" }

    assert_response :success
    assert_match '(bus)', @response.body
  end

  test 'says nothing about the vehicle rather than guessing when the feed omits it' do
    stub_departures('stops' => [{
                      'stop_name' => 'Railway Station',
                      'departures' => [departure('14:21:00', route: '78', trip_headsign: 'Market Square')]
                    }])

    get '/departures_stop?id=s-test-northgate', headers: { 'HTTP_COOKIE' => "#{COOKIES};departures_saved=#{SAVED}" }

    assert_response :success
    # A missing type must not read as a tram, which is what route type zero means.
    assert_no_match(/\(tram\)/, @response.body)
    assert_match 'Market Square', @response.body
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

  test 'says there is no timetable for a stop that has no service at any hour' do
    # Served by routes, but with no schedule behind them: the network structure is
    # published and the times are not, which is a stop that can never show a departure.
    stub_departures_within_window('stops' => [{ 'stop_name' => 'Metro Station', 'departures' => [] }])
    stub_departures_any_time('stops' => [{ 'stop_name' => 'Metro Station', 'departures' => [] }])

    get '/departures_stop?id=s-test-northgate', headers: { 'HTTP_COOKIE' => "#{COOKIES};departures_saved=#{SAVED}" }

    assert_response :success
    assert_match 'No timetable for this stop', @response.body
    assert_no_match(/Nothing due/, @response.body)
  end

  test 'says nothing is due soon when the stop does have a timetable' do
    stub_departures_within_window('stops' => [{ 'stop_name' => 'Northgate', 'departures' => [] }])
    stub_departures_any_time('stops' => [{
                               'stop_name' => 'Northgate',
                               'departures' => [departure('06:12:00', route: '22', trip_headsign: 'Eastport')]
                             }])

    get '/departures_stop?id=s-test-northgate', headers: { 'HTTP_COOKIE' => "#{COOKIES};departures_saved=#{SAVED}" }

    assert_response :success
    # Quiet for a couple of hours is not the same as never running.
    assert_match 'Nothing due', @response.body
    assert_no_match(/No timetable/, @response.body)
  end

  test 'does not claim a stop has no timetable when the check itself fails' do
    stub_departures_within_window('stops' => [{ 'stop_name' => 'Northgate', 'departures' => [] }])
    stub_request(:get, %r{transit\.land/api/v2/rest/stops/.+/departures\?(?!.*next=7200)})
      .to_return(status: 500, body: '')

    get '/departures_stop?id=s-test-northgate', headers: { 'HTTP_COOKIE' => "#{COOKIES};departures_saved=#{SAVED}" }

    assert_response :success
    assert_no_match(/No timetable/, @response.body)
  end

  test 'credits transitland wherever their data is shown, as their terms require' do
    stub_stops('stops' => [platform('Northgate', 's-test-northgate')])
    stub_departures('stops' => [{ 'stop_name' => 'Northgate',
                                  'departures' => [departure('14:09:00', route: '22', trip_headsign: 'Eastport')] }])

    ['/departures', '/departures_add', '/departures_stop?id=s-test-northgate'].each do |path|
      get path, headers: { 'HTTP_COOKIE' => "#{COOKIES};departures_saved=#{SAVED}" }

      assert_response :success
      assert_match 'Transport data by Transitland', @response.body, "#{path} carries no attribution"
      assert_match 'https://www.transit.land/terms', @response.body, "#{path} does not link the terms"
      assert_match "class='credit'", @response.body, "#{path} does not style the attribution"
      # Flush against the last link, it is easy to hit by accident on a touchscreen.
      assert_match %r{<br />\s*<br />\s*<div class='credit'>}, @response.body, "#{path} credit is not spaced"
    end
  end

  # Saving is a POST and forgetting a DELETE, so a browser that fetches links
  # speculatively cannot change what is stored by looking at the list.
  test 'will not save a stop from a GET, however the request arrives' do
    get '/departures_save?id=s-test-northgate&name=Northgate', headers: { 'HTTP_COOKIE' => COOKIES }

    assert_response :not_found
    assert_not_touched :departures_saved
  end

  test 'will not forget saved stops from a GET' do
    get '/departures_forget', headers: { 'HTTP_COOKIE' => "#{COOKIES};departures_saved=#{SAVED}" }

    assert_response :not_found
    assert_not_touched :departures_saved
  end

  # The stop list is what a link-fetching browser walked, so it must offer nothing that
  # a fetch of the href alone could act on.
  test 'offers stops to save as posted forms rather than followable links' do
    stub_stops('stops' => [platform('Northgate', 's-test-northgate'), platform('Southgate', 's-test-southgate')])

    get '/departures_add', headers: { 'HTTP_COOKIE' => COOKIES }

    assert_response :success
    assert_no_match(/href="[^"]*departures_save/, @response.body)
    assert_match %r{<form[^>]*method="post"[^>]*action="/departures_save"}, @response.body
  end

  # Every action in this app is a digit, and the digit has to reach the thing that acts.
  # On a one button form that means the button carries the accesskey: put it on the form
  # and the keypress lands on nothing. Styled to match, so a POST still reads as a link.
  test 'keeps the number key on the button that forgets the stops' do
    get '/departures', headers: { 'HTTP_COOKIE' => "#{COOKIES};departures_saved=#{SAVED}" }

    assert_response :success
    assert_match(/<button accesskey="9"[^>]*>9 Forget saved stops</, @response.body)
    assert_match(/<form class="inline-action"/, @response.body)
  end

  test 'saves the one stop that was chosen and nothing else' do
    post '/departures_save', params: { id: 's-test-northgate', name: 'Northgate' },
                             headers: { 'HTTP_COOKIE' => COOKIES }

    assert_redirected_to departures_path
    assert_equal [{ 'id' => 's-test-northgate', 'name' => 'Northgate' }], saved_stops
  end

  test 'puts the stop just saved at the top, where the keypad reaches it first' do
    post '/departures_save', params: { id: 's-test-southgate', name: 'Southgate' },
                             headers: { 'HTTP_COOKIE' => "#{COOKIES};departures_saved=#{SAVED}" }

    names = saved_stops.map { |stop| stop['name'] }

    assert_equal %w[Southgate Northgate], names
  end

  test 'saves a stop once however often it is chosen' do
    post '/departures_save', params: { id: 's-test-northgate', name: 'Northgate' },
                             headers: { 'HTTP_COOKIE' => "#{COOKIES};departures_saved=#{SAVED}" }

    assert_equal 1, saved_stops.length
  end

  test 'keeps only as many stops as the keypad has digits for' do
    existing = (1..5).map { |n| { 'id' => "s-test-#{n}", 'name' => "Stop #{n}" } }.to_json

    post '/departures_save', params: { id: 's-test-new', name: 'Newest' },
                             headers: { 'HTTP_COOKIE' => "#{COOKIES};departures_saved=#{existing}" }

    assert_equal DeparturesController::MAX_SAVED_STOPS, saved_stops.length
    assert_equal 'Newest', saved_stops.first['name']
    # The oldest falls off the end rather than the newest being refused.
    assert_no_match(/Stop 5/, saved_stops.to_s)
  end

  test 'ignores a save that names no stop' do
    post '/departures_save', params: { id: 's-test-northgate' }, headers: { 'HTTP_COOKIE' => COOKIES }

    assert_redirected_to departures_path
    assert_empty saved_stops
  end

  test 'forgets every saved stop when asked' do
    delete '/departures_forget', headers: { 'HTTP_COOKIE' => "#{COOKIES};departures_saved=#{SAVED}" }

    assert_redirected_to departures_path
    assert_empty saved_stops
  end

  test 'reports rather than crashes when transitland is unreachable' do
    stub_request(:get, %r{transit\.land/api/v2/rest/stops/.+/departures}).to_return(status: 500, body: '')

    get '/departures_stop?id=s-test-northgate', headers: { 'HTTP_COOKIE' => "#{COOKIES};departures_saved=#{SAVED}" }

    assert_response :success
    assert_match 'Could not reach the departures service', @response.body
  end

  private

  # What the browser is holding after the request, which is the only place a saved stop
  # ever lives.
  def saved_stops
    JSON.parse(cookies[:departures_saved].presence || '[]')
  end

  # A rejected request must not write the cookie in either direction. The jar only carries
  # what a response set, so it reads as empty whether the stops survived or were wiped —
  # hence asserting on Set-Cookie.
  def assert_not_touched(name)
    sent = Array(@response.headers['Set-Cookie']).join("\n")

    assert_not_includes sent, name.to_s, "#{name} was written by a request that should have been refused"
  end

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

  # The two hour window someone at a stop cares about.
  def stub_departures_within_window(body)
    request = stub_request(:get, %r{transit\.land/api/v2/rest/stops/.+/departures})

    request.with(query: hash_including('next' => '7200')).to_return(json(body))
  end

  # The same stop asked without a window, which is how a quiet couple of hours is told
  # apart from a stop that never runs anything.
  def stub_departures_any_time(body)
    request = stub_request(:get, %r{transit\.land/api/v2/rest/stops/.+/departures})

    request.with { |sent| !sent.uri.query.include?('next=') }.to_return(json(body))
  end

  def json(body)
    { status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  def station(name, id)
    { 'stop_name' => name, 'onestop_id' => id, 'location_type' => 1 }
  end

  def platform(name, id, platform_code: nil, lat: 51.5, lon: -0.1)
    {
      'stop_name' => name,
      'onestop_id' => id,
      'location_type' => 0,
      'platform_code' => platform_code,
      'geometry' => { 'coordinates' => [lon, lat] }
    }
  end

  def stub_trip(route_id, trip_id, stop_names)
    body = { 'trips' => [{ 'stop_times' => stop_names.map { |name| { 'stop' => { 'stop_name' => name } } } }] }

    stub_request(:get, %r{transit\.land/api/v2/rest/routes/#{route_id}/trips/#{trip_id}}).to_return(
      status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' }
    )
  end

  def departure(time, fields)
    {
      'departure_time' => time,
      'departure' => { 'scheduled' => time, 'estimated' => nil },
      'schedule_relationship' => fields[:schedule_relationship] || 'STATIC',
      'stop_headsign' => fields[:stop_headsign],
      'trip' => {
        'id' => fields[:trip_id],
        'stop_pattern_id' => fields[:pattern],
        'trip_headsign' => fields[:trip_headsign],
        'route' => {
          'onestop_id' => fields[:route_id],
          'route_short_name' => fields[:route],
          'route_long_name' => fields[:route_long_name],
          'route_type' => fields[:route_type]
        }
      }
    }
  end
end
