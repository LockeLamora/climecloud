# frozen_string_literal: true

require 'test_helper'

class DirectionsControllerTest < ActionDispatch::IntegrationTest
  COOKIES = 'metrics=hybrid;country_code=gb'

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
    assert_match 'place_id%3APLACE_ONE', @response.body
  end

  test 'returns to the search form when nothing matches at all' do
    stub_directions(not_found_body)
    stub_geocode('status' => 'ZERO_RESULTS', 'results' => [])

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

    plan_route(destination: 'place_id:PLACE_ONE')

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
    stub_request(:get, %r{maps\.googleapis\.com/maps/api/geocode/json})
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
      'status' => 'OK',
      'results' => [
        geocode_result('PLACE_ONE', 'High Street, Newport'),
        geocode_result('PLACE_TWO', 'High Street, Newark')
      ]
    }
  end

  def geocode_result(place_id, address)
    {
      'place_id' => place_id,
      'formatted_address' => address,
      'geometry' => { 'location' => { 'lat' => 52.3, 'lng' => 1.17 } },
      'address_components' => [{ 'types' => ['country'], 'short_name' => 'GB' }]
    }
  end
end
