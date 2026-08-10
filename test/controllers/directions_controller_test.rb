# frozen_string_literal: true

require 'test_helper'

class DirectionsControllerTest < ActionDispatch::IntegrationTest
  COOKIES = 'metrics=hybrid;country_code=gb;lat=52.3;lon=1.17'

  test 'should load the drections search page successfully when cookie is set' do
    get '/directions'
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
    assert_match 'High Street, Newport', @response.body
    assert_match 'High Street, Newark', @response.body
    # Coordinates, so the re-planned route cannot be read a second way.
    assert_match 'destination=51.58%2C-2.99', @response.body
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

    plan_route(destination: '51.58,-2.99')

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
                   house_on('Station Road', 'Clive', 410),
                   house_on('Station Road', 'Clive', 255),
                   house_on('Station Road', 'Clive', 231),
                   house_on('Station Road', 'Haydock', 41)
                 ])

    plan_route

    assert_response :success
    assert_match 'Station Road, Clive', @response.body
    assert_match 'Station Road, Haydock', @response.body
    # Four results, two streets, and no door numbers left in the list.
    assert_equal 2, @response.body.scan('Station Road,').length
    assert_no_match(/\d+ Station Road/, @response.body)
  end

  test 'ranks candidates nearest the other end of the journey first' do
    stub_directions(not_found_body)
    stub_geocode(geocode_body)

    plan_route(origin: '51.48,-3.18')

    assert_response :success
    # Biased towards the origin, so the nearby Newport outranks the distant Newark.
    assert_requested :get, %r{api\.geoapify\.com/v1/geocode/autocomplete} do |request|
      request.uri.query.include?('bias=proximity:-3.18,51.48')
    end
  end

  test 'places the other end first so a nearby street is searched for nearby' do
    stub_directions(not_found_body)
    stub_geocode('features' => [geocode_result('Wesham, Kirkham', 53.78, -2.88)])

    plan_route

    assert_response :success
    # Wesham is geocoded first, then Station Road is searched around Wesham rather
    # than around the saved settings postcode hundreds of miles away.
    assert_requested :get, %r{api\.geoapify\.com/v1/geocode/autocomplete} do |request|
      request.uri.query.include?('bias=proximity:-2.88,53.78')
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

  test 'falls back to the saved location when the other end cannot be placed' do
    stub_directions(not_found_body)
    stub_geocode('features' => [])

    plan_route

    assert_response :success
    assert_requested :get, %r{api\.geoapify\.com/v1/geocode/autocomplete} do |request|
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
    assert_match 'High Street, Newport', @response.body
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

  def directions_body(partial_match: false)
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
          'steps' => [route_step('Head north on Test Road'), route_step('Turn left onto End Road')]
        }]
      }]
    }
  end

  def route_step(instruction)
    {
      'html_instructions' => instruction,
      'distance' => { 'text' => '100 m' },
      'duration' => { 'text' => '2 mins' },
      'start_location' => { 'lat' => 52.3, 'lng' => 1.17 },
      'end_location' => { 'lat' => 52.31, 'lng' => 1.18 },
      'polyline' => { 'points' => 'steppoints' }
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
        geocode_result('High Street, Newport', 51.58, -2.99),
        geocode_result('High Street, Newark', 53.07, -0.81)
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
