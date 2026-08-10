# frozen_string_literal: true

require 'net/http'
require 'uri'

class Maps
  STATUS_MESSAGES = {
    'NOT_FOUND' => 'Could not find that place, please pick one below',
    'ZERO_RESULTS' => 'No route found, try another way of travelling',
    'OVER_QUERY_LIMIT' => 'Too many searches just now, please try again shortly',
    'REQUEST_DENIED' => 'Route planning is unavailable, please try again later',
    'INVALID_REQUEST' => 'Please fill in both From and To',
    'MAX_ROUTE_LENGTH_EXCEEDED' => 'That route is too long to plan'
  }.freeze

  UNAVAILABLE = 'Route planning is unavailable, please try again later'

  IMAGE_SIZE = 220
  WORLD_PIXELS = 256
  # Hybrid imagery runs out above this in most places, leaving a blank tile.
  MAX_STEP_ZOOM = 19
  # Below this a 220px tile covers so much ground that street names are unreadable.
  MIN_STEP_ZOOM = 16

  # unresolved lists the endpoints Google could not pin down, or matched only
  # loosely, so the user can be offered a list of places to pick from.
  attr_reader :error, :unresolved

  def initialize(params)
    @key = Rails.application.credentials.google.api_key
    @origin = params[:origin]
    @destination = params[:destination]
    @mode = params[:mode]
    @units = params[:units]
    @unresolved = []
  end

  def get_routes
    uri = build_google_maps_uri
    get_routes_from_google_maps_uri(uri)
  end

  def get_static_map_image_api(overview_polyline)
    url = build_google_map_static_image_api(overview_polyline)
    get_static_map_image(url)
  end

  def get_static_map_step_image_api(step)
    url = build_google_map_static_step_image_api(step)
    get_static_map_image(url)
  end

  private

  def build_google_map_static_step_image_api(step)
    uri = URI('https://maps.googleapis.com/maps/api/staticmap')
    centre, zoom = frame_for(step)

    params = {
      key: @key,
      size: "#{IMAGE_SIZE}x#{IMAGE_SIZE}",
      maptype: 'hybrid',
      center: centre,
      zoom: zoom,
      markers: [
        "size:mid|color:green|label:A|#{step['start_location']['lat']},#{step['start_location']['lng']}",
        "size:mid|color:red|label:B|#{step['end_location']['lat']},#{step['end_location']['lng']}"
      ],
      path: "enc:#{step['polyline']['points']}"
    }

    uri.query = URI.encode_www_form(params)
    uri
  end

  # Left to itself Google fits the step with enough padding that a single turn is
  # a speck in the middle of a 220px tile. Frame it ourselves instead.
  def frame_for(step)
    points = step_points(step)
    lats = points.map(&:first)
    lngs = points.map(&:last)
    zoom = zoom_for(lats.min, lats.max, lngs.min, lngs.max)

    # Fitting a long step whole leaves it too zoomed out to read a street name on a
    # two inch screen. Past that point stop zooming out and centre on where the
    # user is standing, since what they need is the road they are on right now.
    if zoom < MIN_STEP_ZOOM
      return [centre_of(step['start_location']['lat'], step['start_location']['lng']), MIN_STEP_ZOOM]
    end

    [centre_of((lats.min + lats.max) / 2, (lngs.min + lngs.max) / 2), zoom]
  end

  def centre_of(lat, lng)
    format('%<lat>.6f,%<lng>.6f', lat: lat, lng: lng)
  end

  def step_points(step)
    points = decode_polyline(step['polyline']['points'])
    points << [step['start_location']['lat'], step['start_location']['lng']]
    points << [step['end_location']['lat'], step['end_location']['lng']]
    points
  end

  def zoom_for(min_lat, max_lat, min_lng, max_lng)
    lat_fraction = (mercator(max_lat) - mercator(min_lat)) / Math::PI
    lng_diff = max_lng - min_lng
    lng_fraction = (lng_diff.negative? ? lng_diff + 360 : lng_diff) / 360

    [zoom_for_fraction(lat_fraction), zoom_for_fraction(lng_fraction)].min
  end

  def zoom_for_fraction(fraction)
    return MAX_STEP_ZOOM if fraction <= 0

    zoom = (Math.log(IMAGE_SIZE / WORLD_PIXELS.to_f / fraction) / Math.log(2)).floor
    zoom.clamp(1, MAX_STEP_ZOOM)
  end

  def mercator(lat)
    sin = Math.sin(lat * Math::PI / 180)
    radians = Math.log((1 + sin) / (1 - sin)) / 2
    radians.clamp(-Math::PI, Math::PI) / 2
  end

  # Google hands back the step geometry encoded, and the true bounds matter: a
  # bend in the road can sit well outside a straight line from A to B.
  def decode_polyline(encoded)
    points = []
    index = 0
    lat = 0
    lng = 0

    while index < encoded.to_s.length
      lat_delta, index = decode_chunk(encoded, index)
      lng_delta, index = decode_chunk(encoded, index)
      lat += lat_delta
      lng += lng_delta
      points << [lat / 1e5, lng / 1e5]
    end

    points
  end

  def decode_chunk(encoded, index)
    result = 0
    shift = 0

    loop do
      byte = encoded[index].ord - 63
      index += 1
      result |= (byte & 0x1f) << shift
      shift += 5
      break if byte < 0x20
    end

    [result.odd? ? ~(result >> 1) : result >> 1, index]
  end

  def build_google_map_static_image_api(overview_polyline)
    uri = URI('https://maps.googleapis.com/maps/api/staticmap')
    params = {
      key: Rails.application.credentials.google.api_key,
      size: '220x220',
      maptype: 'hybrid',
      path: "enc:#{overview_polyline}"
    }

    uri.query = URI.encode_www_form(params)
    uri
  end

  def get_static_map_image(uri)
    image = Net::HTTP.get_response(uri).body
    Base64.strict_encode64(image)
  end

  def build_google_maps_uri
    uri = URI('https://maps.googleapis.com/maps/api/directions/json')
    params = {
      key: @key,
      origin: @origin,
      destination: @destination,
      mode: @mode,
      units: @units
    }

    uri.query = URI.encode_www_form(params)
    uri
  end

  def get_routes_from_google_maps_uri(uri)
    res = Net::HTTP.get_response(uri)
    unless res.is_a?(Net::HTTPSuccess)
      @error = UNAVAILABLE
      return
    end

    body = JSON.parse(res.body)
    unless body['status'] == 'OK'
      @error = STATUS_MESSAGES.fetch(body['status'], 'Could not plan route, please try again')
      @unresolved = unresolved_waypoints(body) if body['status'] == 'NOT_FOUND'
      return
    end

    @unresolved = partial_match_waypoints(body)
    overview_polyline = extract_journey_overlay(body)
    start, endpart = extract_addresses(body)
    start_location, end_location = extract_locations(body)
    steps, overall_time = extract_steps(body)

    {
      overview_polyline: overview_polyline,
      start: start,
      end: endpart,
      start_location: start_location,
      end_location: end_location,
      steps: steps,
      overall_time: overall_time
    }
  end

  # Where Google actually placed each end. Worth keeping: re-picking one endpoint
  # should search around the other, and this saves geocoding it a second time.
  def extract_locations(body)
    leg = body['routes'][0]['legs'][0]
    [leg['start_location'], leg['end_location']]
  end

  def extract_steps(body)
    steps = body['routes'][0]['legs'][0]['steps']
    overall_time = body['routes'][0]['legs'][0]['duration']['text']
    [steps, overall_time]
  end

  def extract_addresses(body)
    start = body['routes'][0]['legs'][0]['start_address']
    endpart = body['routes'][0]['legs'][0]['end_address']
    [start, endpart]
  end

  def extract_journey_overlay(body)
    body['routes'][0]['overview_polyline']['points']
  end

  # Google reports a failed lookup per endpoint. If it tells us nothing, assume
  # either could be at fault and let the user check both.
  def unresolved_waypoints(body)
    fields = waypoint_fields(body) { |waypoint| waypoint['geocoder_status'] != 'OK' }
    fields.empty? ? %w[origin destination] : fields
  end

  # A partial match means Google guessed, so the route may be to the wrong place.
  def partial_match_waypoints(body)
    waypoint_fields(body) { |waypoint| waypoint['partial_match'] }
  end

  def waypoint_fields(body)
    waypoints = body['geocoded_waypoints'] || []
    fields = []
    fields << 'origin' if waypoints[0] && yield(waypoints[0])
    fields << 'destination' if waypoints[1] && yield(waypoints[1])
    fields
  end
end
