# frozen_string_literal: true

require 'test_helper'

class DirectionsControllerTest < ActionDispatch::IntegrationTest
  COOKIES = 'metrics=hybrid;country_code=gb;lat=52.3;lon=1.17'

  # Step lengths are expressed in windows rather than metres, so retuning the window
  # size does not silently leave these tests asserting the wrong chunk counts.
  SHORT_STEP_METRES = Maps::SEGMENT_METRES * 0.8
  LONG_STEP_WINDOWS = 7
  LONG_STEP_METRES = Maps::SEGMENT_METRES * (LONG_STEP_WINDOWS - 0.5)

  # Every route view carries a map now, so every one of these fetches an image.
  setup do
    stub_request(:get, %r{maps\.googleapis\.com/maps/api/staticmap})
      .to_return(status: 200, body: 'PNG', headers: { 'Content-Type' => 'image/png' })
  end

  # Planning a route spends three Google calls against one key, so a crawler that has
  # never been through settings must not be able to start one.
  test 'sends anyone without a saved location to settings rather than to Google' do
    %w[/directions /directions_plan /directions_pick].each do |path|
      get path, params: { origin: 'a', destination: 'b' }, headers: { 'COOKIE' => 'metrics=hybrid' }

      assert_redirected_to '/settings', "#{path} served a reader with no saved location"
    end

    assert_not_requested :get, /maps\.googleapis\.com/
    assert_not_requested :get, /api\.geoapify\.com/
  end

  # An empty field is an INVALID_REQUEST at Google, so it is refused here instead: the
  # reader sees the same message and the call is not spent finding that out.
  test 'refuses a blank endpoint without asking google about it' do
    [{ origin: '', destination: 'Northgate' },
     { origin: 'Market Square', destination: '' },
     { origin: '   ', destination: "\t " },
     { origin: '', destination: '' }].each do |params|
      plan_route(params)

      assert_response :success
      assert_match 'Please fill in both From and To', @response.body, "accepted #{params.inspect}"
    end

    assert_not_requested :get, /maps\.googleapis\.com/
    assert_not_requested :get, /api\.geoapify\.com/
  end

  test 'the search form asks the browser for both endpoints before it submits' do
    get '/directions', headers: { 'COOKIE' => COOKIES }

    assert_response :success
    assert_match(/name="origin"[^>]*required|required[^>]*name="origin"/, @response.body)
    assert_match(/name="destination"[^>]*required|required[^>]*name="destination"/, @response.body)
  end

  test 'should load the drections search page successfully when cookie is set' do
    get '/directions', headers: { 'COOKIE' => COOKIES }
    assert_response :success
    assert_match 'Directions', @response.body
  end

  test 'shows the whole route with a link through to turn by turn' do
    stub_directions(directions_body)

    plan_route

    assert_response :success
    assert_match 'Switch to Turn-by-turn', @response.body
    assert_match 'Head north on Test Road', @response.body
  end

  # Zero is the menu on every page in this app, and this one had nothing but the browser's
  # own back button — which a keypad phone does not make obvious.
  test 'the whole route offers the way back to the menu, as every other page does' do
    stub_directions(directions_body)

    plan_route

    assert_response :success
    assert_match(%r{accesskey="0"[^>]*href="/"|href="/"[^>]*accesskey="0"}, @response.body,
                 'the whole route view has no numbered link back to the menu')
    assert_match 'Back to menu', @response.body
  end

  test 'shows one turn at a time with a link to the next' do
    stub_directions(directions_body)

    plan_route(view: 'turn', step: '0')

    assert_response :success
    assert_match 'Turn 1 of 2', @response.body
    assert_match 'Head north on Test Road', @response.body
    assert_match 'Next turn', @response.body
    assert_no_match(/Previous turn/, @response.body)
  end

  test 'offers arrival rather than a next turn on the last step' do
    stub_directions(directions_body)

    plan_route(view: 'turn', step: '1')

    assert_response :success
    assert_match 'Turn 2 of 2', @response.body
    assert_match 'Arrive:', @response.body
    assert_match 'End Road, Testville', @response.body
    assert_match 'Previous turn', @response.body
    assert_no_match(/Next turn/, @response.body)
  end

  test 'walks a long step in short chunks instead of jumping to the turn' do
    stub_directions(directions_body(long_step: true))

    plan_route(view: 'turn', step: '0')

    assert_response :success
    assert_match "part 1 of #{LONG_STEP_WINDOWS}", @response.body
    assert_match 'Further along', @response.body
    assert_no_match(/Next turn/, @response.body)
  end

  test 'reaches the next turn only after the last chunk of a long step' do
    stub_directions(directions_body(long_step: true))

    plan_route(view: 'turn', step: '0', segment: (LONG_STEP_WINDOWS - 1).to_s)

    assert_response :success
    assert_match "part #{LONG_STEP_WINDOWS} of #{LONG_STEP_WINDOWS}", @response.body
    assert_match 'Next turn', @response.body
    assert_match 'Back along', @response.body
  end

  test 'shows no chunking for a step short enough to fit one view' do
    stub_directions(directions_body)

    plan_route(view: 'turn', step: '0')

    assert_response :success
    assert_no_match(/part 1 of/, @response.body)
    assert_match 'Next turn', @response.body
  end

  test 'clamps a chunk number past the end of a step' do
    stub_directions(directions_body(long_step: true))

    plan_route(view: 'turn', step: '0', segment: '99')

    assert_response :success
    assert_match "part #{LONG_STEP_WINDOWS} of #{LONG_STEP_WINDOWS}", @response.body
  end

  test 'clamps a step number past the end of the route' do
    stub_directions(directions_body)

    plan_route(view: 'turn', step: '99')

    assert_response :success
    assert_match 'Turn 2 of 2', @response.body
  end

  test 'offers places to pick from when google cannot find an endpoint' do
    stub_directions(not_found_body)
    stub_geocode(geocode_body)

    plan_route

    assert_response :success
    assert_match 'did you mean', @response.body
    assert_match 'High Street, Testville', @response.body
    assert_match 'High Street, Otherton', @response.body
    # Coordinates, so the re-planned route cannot be read a second way.
    assert_match 'destination=52.0%2C1.0', @response.body
  end

  test 'returns to the search form when nothing matches at all' do
    stub_directions(not_found_body)
    stub_geocode('features' => [])

    plan_route

    assert_response :success
    assert_match 'Could not find that place', @response.body
  end

  test 'offers to re-pick either endpoint the user typed as text' do
    stub_directions(directions_body)

    plan_route

    assert_response :success
    assert_match 'directions_pick', @response.body
    assert_match 'From', @response.body
    assert_match 'To', @response.body
  end

  test 'does not offer to re-pick an endpoint already pinned to a place' do
    stub_directions(directions_body)

    plan_route(destination: '52.0,1.0')

    assert_response :success
    assert_match 'field=origin', @response.body
    assert_no_match(/field=destination/, @response.body)
  end

  test 'reports rather than crashes when no route exists between two places' do
    stub_directions('status' => 'ZERO_RESULTS', 'routes' => [], 'geocoded_waypoints' => [])

    plan_route

    assert_response :success
    assert_match 'No route found', @response.body
  end

  test 'reports rather than crashes when google is unreachable' do
    stub_request(:get, %r{maps\.googleapis\.com/maps/api/directions/json}).to_return(status: 500, body: '')

    plan_route

    assert_response :success
    assert_match 'Route planning is unavailable', @response.body
  end

  test 'offers one entry per street rather than a list of house numbers' do
    stub_directions(not_found_body)
    stub_geocode('features' => [
                   house_on('Test Road', 'Eastwick', 410),
                   house_on('Test Road', 'Eastwick', 255),
                   house_on('Test Road', 'Eastwick', 231),
                   house_on('Test Road', 'Westwick', 41)
                 ])

    plan_route

    assert_response :success
    assert_match 'Test Road, Eastwick', @response.body
    assert_match 'Test Road, Westwick', @response.body
    # Four results, two streets, and no door numbers left in the list.
    assert_equal 2, @response.body.scan('Test Road,').length
    assert_no_match(/\d+ Test Road/, @response.body)
  end

  test 'ranks candidates nearest the other end of the journey first' do
    stub_directions(not_found_body)
    stub_geocode(geocode_body)

    plan_route(origin: '51.48,-3.18')

    assert_response :success
    # Biased towards the origin, so the nearby Testville outranks the distant Otherton.
    assert_requested :get, %r{api\.geoapify\.com/v1/geocode/autocomplete} do |request|
      request.uri.query.include?('bias=proximity:-3.18,51.48')
    end
  end

  test 'places the other end first so a nearby street is searched for nearby' do
    stub_directions(not_found_body)
    stub_geocode('features' => [geocode_result('Northtown, Northshire', 52.0, 1.0)])

    plan_route

    assert_response :success
    # Northtown is geocoded first, then Test Road is searched around Northtown rather
    # than around the saved settings postcode hundreds of miles away.
    assert_requested :get, %r{api\.geoapify\.com/v1/geocode/autocomplete} do |request|
      request.uri.query.include?('bias=proximity:1.0,52.0')
    end
  end

  test 'offers the route page pick link biased to where google put the other end' do
    stub_directions(directions_body)

    plan_route

    assert_response :success
    # Origin resolved to 52.30,1.17, so re-picking the destination searches there.
    assert_match 'bias_lat=52.3', @response.body
    assert_match 'bias_lon=1.17', @response.body
  end

  test 'searches a tight radius around the other end before anywhere else' do
    stub_directions(directions_body)
    stub_geocode('features' => [geocode_result('Test Road, Northshire', 52.0, 1.01)])

    with_api_credentials do
      get '/directions_pick',
          params: { origin: 'northtown', destination: 'test road', mode: 'walking',
                    field: 'destination', bias_lat: '52.0', bias_lon: '1.0' },
          headers: { 'COOKIE' => COOKIES }
    end

    assert_response :success
    assert_match 'Test Road, Northshire', @response.body
    assert_requested :get, %r{api\.geoapify\.com/v1/geocode/autocomplete} do |request|
      request.uri.query.include?('filter=circle:1.0,52.0,30000')
    end
  end

  test 'widens beyond the tight radius when nothing is nearby' do
    stub_request(:get, %r{api\.geoapify\.com/v1/geocode/autocomplete.*filter=circle})
      .to_return(status: 200, body: { 'features' => [] }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, %r{api\.geoapify\.com/v1/geocode/autocomplete.*filter=countrycode})
      .to_return(status: 200,
                 body: { 'features' => [geocode_result('Test Road, Faraway', 50.0, 2.0)] }.to_json,
                 headers: { 'Content-Type' => 'application/json' })

    with_api_credentials do
      get '/directions_pick',
          params: { origin: 'northtown', destination: 'test road', mode: 'walking',
                    field: 'destination', bias_lat: '52.0', bias_lon: '1.0' },
          headers: { 'COOKIE' => COOKIES }
    end

    assert_response :success
    assert_match 'Test Road, Faraway', @response.body
  end

  test 'falls back to the saved location when the other end cannot be placed' do
    stub_directions(not_found_body)
    stub_geocode('features' => [])

    plan_route

    assert_response :success
    # Both the tight pass and the widened one carry the bias, hence at_least_times.
    assert_requested :get, %r{api\.geoapify\.com/v1/geocode/autocomplete}, at_least_times: 1 do |request|
      request.uri.query.include?('bias=proximity:1.17,52.3')
    end
  end

  test 'lists candidates when asked to pick a different endpoint' do
    stub_geocode(geocode_body)

    with_api_credentials do
      get '/directions_pick',
          params: { origin: 'start street', destination: 'end street', mode: 'walking', field: 'destination' },
          headers: { 'COOKIE' => COOKIES }
    end

    assert_response :success
    assert_match 'High Street, Testville', @response.body
  end

  private

  def plan_route(extra = {})
    with_api_credentials do
      get '/directions_plan',
          params: { origin: 'start street', destination: 'end street', mode: 'walking' }.merge(extra),
          headers: { 'COOKIE' => COOKIES }
    end
  end

  def stub_directions(body)
    stub_request(:get, %r{maps\.googleapis\.com/maps/api/directions/json})
      .to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def stub_geocode(body)
    stub_request(:get, %r{api\.geoapify\.com/v1/geocode/autocomplete})
      .to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def directions_body(partial_match: false, long_step: false)
    destination = { 'geocoder_status' => 'OK' }
    destination['partial_match'] = true if partial_match

    {
      'status' => 'OK',
      'geocoded_waypoints' => [{ 'geocoder_status' => 'OK' }, destination],
      'routes' => [{
        'overview_polyline' => { 'points' => 'overviewpoints' },
        'legs' => [{
          'start_address' => 'Start Road, Testville',
          'end_address' => 'End Road, Testville',
          'start_location' => { 'lat' => 52.3, 'lng' => 1.17 },
          'end_location' => { 'lat' => 52.31, 'lng' => 1.18 },
          'duration' => { 'text' => '12 mins' },
          'steps' => [
            route_step('Head north on Test Road', metres: long_step ? LONG_STEP_METRES : SHORT_STEP_METRES),
            route_step('Turn left onto End Road')
          ]
        }]
      }]
    }
  end

  # Short enough for a single window by default. An empty polyline makes the geometry
  # fall back to the two endpoints, which keeps the length exactly what is asked for.
  def route_step(instruction, metres: SHORT_STEP_METRES)
    {
      'html_instructions' => instruction,
      'distance' => { 'text' => '100 m' },
      'duration' => { 'text' => '2 mins' },
      'start_location' => { 'lat' => 52.3, 'lng' => 1.17 },
      'end_location' => { 'lat' => 52.3 + (metres / Maps::METRES_PER_DEGREE.to_f), 'lng' => 1.17 },
      'polyline' => { 'points' => '' }
    }
  end

  def not_found_body
    {
      'status' => 'NOT_FOUND',
      'geocoded_waypoints' => [{ 'geocoder_status' => 'OK' }, { 'geocoder_status' => 'ZERO_RESULTS' }],
      'routes' => []
    }
  end

  def geocode_body
    {
      'features' => [
        geocode_result('High Street, Testville', 52.0, 1.0),
        geocode_result('High Street, Otherton', 53.0, 0.5)
      ]
    }
  end

  def geocode_result(address, lat, lon)
    { 'properties' => { 'formatted' => address, 'lat' => lat, 'lon' => lon, 'country_code' => 'gb' } }
  end

  def house_on(street, city, number)
    {
      'properties' => {
        'formatted' => "#{number} #{street}, #{city}, United Kingdom",
        'housenumber' => number.to_s,
        'street' => street,
        'city' => city,
        'lat' => 53.4,
        'lon' => -2.6,
        'country_code' => 'gb'
      }
    }
  end
end
