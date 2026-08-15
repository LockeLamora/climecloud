# frozen_string_literal: true

require 'test_helper'

class PlacesControllerTest < ActionDispatch::IntegrationTest
  LOCATION_COOKIES = 'lat=52.3;lon=1.17;city=Testville;metrics=metric'

  test 'lists a screenful of categories with a digit each' do
    get '/places', headers: { 'COOKIE' => LOCATION_COOKIES }

    assert_response :success
    assert_match 'Testville', @response.body
    %w[Toilets Pharmacy Food Shops Pub Transport Parking].each do |label|
      assert_match label, @response.body
    end
    # Nine and zero are the navigation on every page, so a ninth category has no digit
    # left and lives a page away rather than losing its keypress.
    assert_match 'More', @response.body
  end

  test 'puts what is needed in a hurry within one keypress' do
    get '/places', headers: { 'COOKIE' => LOCATION_COOKIES }

    assert_response :success
    # A toilet or a doctor is needed now, so they take the first keys.
    assert_match(/1 Toilets/, @response.body)
    assert_match(/2 Hospital/, @response.body)
    # Petrol and a cash machine are things you set out to find, so they wait on page two.
    assert_no_match(/Petrol/, @response.body)
    assert_no_match(/Cash/, @response.body)
  end

  test 'reaches the categories past the first screenful' do
    get '/places', params: { page: '1' }, headers: { 'COOKIE' => LOCATION_COOKIES }

    assert_response :success
    assert_match 'Petrol', @response.body
    assert_match 'Cash', @response.body
    assert_match 'Back', @response.body
    assert_no_match(/Toilets/, @response.body)
  end

  test 'credits openstreetmap wherever its data is shown, as the licence requires' do
    stub_places

    with_api_credentials do
      get '/places', headers: { 'COOKIE' => LOCATION_COOKIES }
      assert_credited

      get '/places_list', params: { kind: 'toilets' }, headers: { 'COOKIE' => LOCATION_COOKIES }
      assert_credited
    end
  end

  test 'looks for anywhere a child could be taken, not only public conveniences' do
    stub_places

    with_api_credentials do
      get '/places_list', params: { kind: 'toilets' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    assert_requested :get, /api\.geoapify\.com/ do |request|
      query = request.uri.query
      # OpenStreetMap records a toilet at two pubs in twenty nine, so nothing can filter
      # on having one. Offer the places where asking works instead.
      # The same set a mainstream search returns for "toilets near me": stations,
      # supermarkets, cafes and the rest, rather than public conveniences alone.
      %w[amenity.toilet commercial.supermarket service.vehicle.fuel catering.fast_food
         catering.cafe commercial.shopping_mall
         public_transport.train].all? { |category| query.include?(category) }
    end
  end

  test 'explains why a supermarket is in a list of toilets' do
    stub_places([{ 'properties' => { 'name' => 'Big Shop', 'distance' => 150, 'lat' => 52.31, 'lon' => 1.18,
                                     'categories' => ['commercial.supermarket'] } }])

    with_api_credentials do
      get '/places_list', params: { kind: 'toilets' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    assert_match 'Places that usually have one', @response.body
    # Labelled for what it is, so the list is read as places to try rather than as toilets.
    assert_match 'Supermarket', @response.body
  end

  test 'leaves the other categories reading as themselves' do
    stub_places

    with_api_credentials do
      get '/places_list', params: { kind: 'petrol' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    assert_no_match(/Places that usually have one/, @response.body)
  end

  test 'says where a nappy can be changed, which is often why anyone is looking' do
    stub_places([
                  { 'properties' => { 'name' => 'Market Toilets', 'distance' => 200, 'lat' => 52.31, 'lon' => 1.18,
                                      'categories' => ['amenity.toilet'],
                                      'facilities' => { 'changing_table' => true } } },
                  { 'properties' => { 'name' => 'Park Toilets', 'distance' => 600, 'lat' => 52.32, 'lon' => 1.19,
                                      'categories' => ['amenity.toilet'], 'facilities' => {} } }
                ])

    with_api_credentials do
      get '/places_list', params: { kind: 'toilets' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    assert_match 'baby changing', @response.body
    assert_equal 1, @response.body.scan('baby changing').length
  end

  test 'remembers a place typed in by hand so it need not be typed again' do
    get '/places', params: { lat: '53.4', lon: '-2.6', place: 'Othertown, UK' },
                   headers: { 'COOKIE' => LOCATION_COOKIES }

    assert_response :success
    assert_match 'Saved places', @response.body
    assert_match 'Othertown, UK', @response.body

    get '/places', headers: { 'COOKIE' => "#{LOCATION_COOKIES};#{cookies_header}" }

    assert_response :success
    assert_match 'Othertown, UK', @response.body
    assert_match 'Forget saved places', @response.body
  end

  test 'forgets every saved place when asked' do
    get '/places', params: { lat: '53.4', lon: '-2.6', place: 'Othertown, UK' },
                   headers: { 'COOKIE' => LOCATION_COOKIES }
    delete '/places_forget', headers: { 'COOKIE' => "#{LOCATION_COOKIES};#{cookies_header}" }

    assert_redirected_to '/places'
    follow_redirect!
    assert_no_match(/Othertown, UK/, @response.body)
  end

  test 'sends a visitor with no saved location to settings' do
    get '/places'

    assert_redirected_to '/settings'
  end

  test 'lists nearby places closest first with a route to each' do
    stub_places

    with_api_credentials do
      get '/places_list', params: { kind: 'petrol' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    assert_match 'Far Garage', @response.body
    assert_match 'Near Garage', @response.body
    # Closest first, whatever order the API returned them in.
    assert_operator @response.body.index('Near Garage'), :<, @response.body.index('Far Garage')
    assert_match '400m', @response.body
    assert_match '1.2km', @response.body
    assert_match 'directions_plan', @response.body
  end

  test 'shows opening hours where the data has them' do
    stub_places([{ 'properties' => { 'name' => 'Corner Chemist', 'distance' => 300, 'lat' => 52.31, 'lon' => 1.18,
                                     'opening_hours' => 'Mo-Fr 09:00-18:00; Sa 09:00-13:00' } }])

    with_api_credentials do
      get '/places_list', params: { kind: 'pharmacy' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    assert_match 'Hours', @response.body
    # Unchanged to read, once the wrappers below are taken back out.
    assert_match 'Mo-Fr 09:00-18:00; Sa 09:00-13:00', @response.body.gsub(%r{</?span>}, '')
  end

  # A phone offers to dial anything on a page that reads as a number worth dialling, and
  # opening times were being offered as the shop's own number: pressing them started a call.
  # The times are wrapped so the run the detection reads is broken up, and the page asks not
  # to be scanned at all for the browsers that honour that.
  test 'opening times are not offered as a phone number to dial' do
    stub_places([{ 'properties' => { 'name' => 'Corner Chemist', 'distance' => 300, 'lat' => 52.31, 'lon' => 1.18,
                                     'opening_hours' => 'Mo-Fr 09:00-18:00; Sa 09:00-13:00' } }])

    with_api_credentials do
      get '/places_list', params: { kind: 'pharmacy' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_match '<meta name="format-detection" content="telephone=no">', @response.body
    assert_match '<span>09:00</span>-<span>18:00</span>', @response.body
    # Nothing left in the text is long enough to read as a number to call.
    runs = @response.body.scan(/>([^<>]+)</).flatten
    assert_empty runs.grep(/\d[\d\s:.-]{6,}/), 'a run of digits this long is a candidate for dialling'
  end

  test 'says how a car park is built and whether it charges' do
    stub_places([
                  { 'properties' => { 'name' => 'Market Multi', 'distance' => 200, 'lat' => 52.31, 'lon' => 1.18,
                                      'categories' => ['parking.cars'],
                                      'parking' => { 'type' => 'multi-storey', 'fee' => true } } },
                  { 'properties' => { 'name' => 'Riverside Free', 'distance' => 900, 'lat' => 52.32, 'lon' => 1.19,
                                      'categories' => ['parking.cars'],
                                      'parking' => { 'type' => 'surface', 'fee' => false,
                                                     'park_and_ride' => true } } }
                ])

    with_api_credentials do
      get '/places_list', params: { kind: 'parking' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    assert_match 'multi-storey, charges apply', @response.body
    assert_match 'open air, free', @response.body
    assert_match 'park and ride', @response.body
  end

  test 'says nothing about a charge the data does not mention' do
    stub_places([{ 'properties' => { 'name' => 'Unsigned Yard', 'distance' => 200, 'lat' => 52.31, 'lon' => 1.18,
                                     'categories' => ['parking.cars'],
                                     'parking' => { 'type' => 'surface' } } }])

    with_api_credentials do
      get '/places_list', params: { kind: 'parking' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    assert_match 'open air', @response.body
    # Only seven of twenty real car parks say anything about a charge, and an absent fee
    # is not a free one. Sending someone to read the sign beats telling them it is free.
    assert_no_match(/free/, @response.body)
    assert_no_match(/charges apply/, @response.body)
  end

  test 'leaves out car parks nobody may park in' do
    stub_places([
                  { 'properties' => { 'name' => 'Office Spaces', 'distance' => 100, 'lat' => 52.31, 'lon' => 1.18,
                                      'categories' => ['parking.cars'],
                                      'parking' => { 'type' => 'surface', 'access' => 'private' } } },
                  { 'properties' => { 'name' => 'Town Car Park', 'distance' => 500, 'lat' => 52.32, 'lon' => 1.19,
                                      'categories' => ['parking.cars'],
                                      'parking' => { 'type' => 'surface', 'access' => 'yes' } } }
                ])

    with_api_credentials do
      get '/places_list', params: { kind: 'parking' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    assert_match 'Town Car Park', @response.body
    # Somewhere to be towed from rather than somewhere to park, and most of the car parks
    # near a city centre are exactly this.
    assert_no_match(/Office Spaces/, @response.body)
  end

  test 'looks much further for a hospital than for a corner shop' do
    stub_places

    with_api_credentials do
      get '/places_list', params: { kind: 'hospital' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    # The nearest hospital can be the far side of a county, and five kilometres found none.
    assert_requested :get, /api\.geoapify\.com/ do |request|
      request.uri.query.include?("circle:1.17,52.3,#{Places::HOSPITAL_RADIUS_METRES}")
    end
  end

  test 'keeps the ordinary radius for everything else' do
    stub_places

    with_api_credentials do
      get '/places_list', params: { kind: 'food' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    assert_requested :get, /api\.geoapify\.com/ do |request|
      request.uri.query.include?("circle:1.17,52.3,#{Places::RADIUS_METRES}")
    end
  end

  test 'shows a hospital that nearer surgeries would otherwise push off the list' do
    surgeries = (1..12).map do |n|
      { 'properties' => { 'name' => "Surgery #{n}", 'distance' => n * 100, 'lat' => 52.31, 'lon' => 1.18,
                          'categories' => ['healthcare.clinic_or_praxis'] } }
    end
    far_hospital = { 'properties' => { 'name' => 'County Hospital', 'distance' => 22_000, 'lat' => 52.5,
                                       'lon' => 1.4, 'categories' => ['healthcare.hospital'] } }
    stub_places(surgeries + [far_hospital])

    with_api_credentials do
      get '/places_list', params: { kind: 'hospital' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    # Twelve nearer surgeries ranked it beyond the end of the list, which is why the
    # category appeared to find no hospital at all.
    assert_match 'County Hospital', @response.body
    # Still last, because it really is the furthest away.
    assert_operator @response.body.index('Surgery 1'), :<, @response.body.index('County Hospital')
  end

  test 'says how far it actually looked when nothing turned up' do
    stub_places([])

    with_api_credentials do
      get '/places_list', params: { kind: 'hospital' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    assert_match "#{Places::HOSPITAL_RADIUS_METRES / 1000}km", @response.body
  end

  test 'asks the api for hospitals and surgeries but not dentists' do
    stub_places

    with_api_credentials do
      get '/places_list', params: { kind: 'hospital' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    assert_requested :get, /api\.geoapify\.com/ do |request|
      request.uri.query.include?('healthcare.hospital') &&
        request.uri.query.include?('healthcare.clinic_or_praxis') &&
        # The bare healthcare category also returns opticians and dentists.
        !request.uri.query.include?('categories=healthcare&')
    end
  end

  test 'asks the api for the grouped categories of the chosen kind' do
    stub_places

    with_api_credentials do
      get '/places_list', params: { kind: 'food' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    assert_requested :get, /api\.geoapify\.com/ do |request|
      request.uri.query.include?('catering.restaurant') &&
        request.uri.query.include?('catering.cafe') &&
        # Geoapify wants longitude before latitude here.
        request.uri.query.include?('circle:1.17,52.3')
    end
  end

  test 'shows what each result actually is' do
    stub_places([{ 'properties' => { 'name' => 'Testville Central', 'distance' => 300,
                                     'categories' => %w[public_transport public_transport.train],
                                     'lat' => 52.31, 'lon' => 1.18 } }])

    with_api_credentials do
      get '/places_list', params: { kind: 'transport' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    assert_match 'Train station', @response.body
  end

  test 'keeps bus stations but drops the poles on every corner' do
    stub_places([
                  { 'properties' => { 'name' => 'Testville Bus Station', 'distance' => 500,
                                      'categories' => %w[public_transport public_transport.bus],
                                      'lat' => 52.32, 'lon' => 1.19 } },
                  { 'properties' => { 'name' => 'Test Rd.-Other La.', 'distance' => 31,
                                      'categories' => %w[public_transport public_transport.bus],
                                      'lat' => 52.301, 'lon' => 1.171 } }
                ])

    with_api_credentials do
      get '/places_list', params: { kind: 'transport' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    assert_match 'Testville Bus Station', @response.body
    assert_no_match(/Test Rd\.-Other La\./, @response.body)
  end

  test 'collapses a pair of stops sharing a name and keeps the nearer' do
    stub_places([
                  { 'properties' => { 'name' => 'Testville Interchange', 'distance' => 281,
                                      'categories' => %w[public_transport.bus],
                                      'lat' => 52.32, 'lon' => 1.19 } },
                  { 'properties' => { 'name' => 'Testville Interchange', 'distance' => 268,
                                      'categories' => %w[public_transport.bus],
                                      'lat' => 52.319, 'lon' => 1.189 } }
                ])

    with_api_credentials do
      get '/places_list', params: { kind: 'transport' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    assert_equal 1, @response.body.scan('Testville Interchange').length
    assert_match '268m', @response.body
    assert_no_match(/281m/, @response.body)
  end

  test 'falls back to an address when a place has no name' do
    stub_places([{ 'properties' => { 'address_line1' => 'Behind the market', 'distance' => 50,
                                     'lat' => 52.31, 'lon' => 1.18 } }])

    with_api_credentials do
      get '/places_list', params: { kind: 'toilets' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    assert_match 'Behind the market', @response.body
  end

  test 'says so plainly when nothing is nearby' do
    stub_places([])

    with_api_credentials do
      get '/places_list', params: { kind: 'pharmacy' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    assert_match 'Nothing found within 5km', @response.body
  end

  test 'reports rather than crashes when the places lookup fails' do
    stub_request(:get, %r{api\.geoapify\.com/v2/places}).to_return(status: 500, body: '')

    with_api_credentials do
      get '/places_list', params: { kind: 'shops' }, headers: { 'COOKIE' => LOCATION_COOKIES }
    end

    assert_response :success
    assert_match 'Could not look up places', @response.body
  end

  test 'sends an unknown category back to the menu' do
    get '/places_list', params: { kind: 'unicorns' }, headers: { 'COOKIE' => LOCATION_COOKIES }

    assert_redirected_to '/places'
  end

  test 'shows imperial distances when that is the saved preference' do
    stub_places

    with_api_credentials do
      get '/places_list', params: { kind: 'petrol' },
                          headers: { 'COOKIE' => 'lat=52.3;lon=1.17;city=Testville;metrics=imperial' }
    end

    assert_response :success
    assert_match '437yd', @response.body
    assert_no_match(/400m/, @response.body)
  end

  private

  # The data underneath is OpenStreetMap's, and Geoapify returns this very string with
  # every record. Spaced like the weather and transport credits so it is not sitting
  # against the last link, where it is easy to hit by accident.
  def assert_credited
    assert_response :success
    assert_match '© OpenStreetMap contributors', @response.body
    assert_match 'openstreetmap.org/copyright', @response.body
    assert_match %r{<br />\s*<br />\s*<div class='credit'>}, @response.body
  end

  # The saved list lives in a cookie, so it has to be handed back on the next request.
  def cookies_header
    "places_recent=#{cookies['places_recent']}"
  end

  def stub_places(features = nil)
    features ||= [
      { 'properties' => { 'name' => 'Far Garage', 'distance' => 1200, 'lat' => 52.4, 'lon' => 1.2 } },
      { 'properties' => { 'name' => 'Near Garage', 'distance' => 400, 'lat' => 52.31, 'lon' => 1.18 } }
    ]

    stub_request(:get, %r{api\.geoapify\.com/v2/places})
      .to_return(status: 200,
                 body: { 'features' => features }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end
end
