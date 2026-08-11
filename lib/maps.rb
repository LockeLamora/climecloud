# frozen_string_literal: true

require 'net/http'
require 'uri'

class Maps
  # Keys rather than translated strings: a constant is evaluated once at boot, so
  # holding the text here would pin every user to whichever locale happened to be
  # active when the class first loaded.
  STATUS_KEYS = {
    'NOT_FOUND' => 'pick_one_below',
    'ZERO_RESULTS' => 'no_route',
    'OVER_QUERY_LIMIT' => 'too_many',
    'REQUEST_DENIED' => 'unavailable',
    'INVALID_REQUEST' => 'fill_in_both',
    'MAX_ROUTE_LENGTH_EXCEEDED' => 'too_long'
  }.freeze

  IMAGE_SIZE = 220
  WORLD_PIXELS = 256
  # Hybrid imagery runs out above this in most places, leaving a blank tile.
  MAX_STEP_ZOOM = 19
  # Below this a 220px tile covers so much ground that street names are unreadable.
  # At 17 it covers roughly 150m, which is close enough to read the street you are
  # standing on rather than the shape of the town.
  MIN_STEP_ZOOM = 17
  # Shorter than the frame at that zoom, which leaves room to put the walker near the
  # bottom edge rather than in the middle.
  SEGMENT_METRES = 100
  METRES_PER_DEGREE = 111_320
  EQUATOR_METRES_PER_PIXEL = 156_543.03392
  # How much of the frame sits behind the walker. The rest is the leg ahead of them,
  # so the picture reads as the journey in front rather than a stretch of road with
  # the starting point somewhere arbitrary in it.
  BEHIND_FRACTION = 0.15
  COMPASS_POINTS = %w[north north_east east south_east south south_west west north_west].freeze

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

  def get_static_map_step_image_api(step, segment = 0)
    url = build_google_map_static_step_image_api(step, segment)
    get_static_map_image(url)
  end

  # A long step framed whole is unreadable at two inches, and framed at its start it
  # shows the first stretch and then nothing until the turn a kilometre later. Split
  # it into windows the user can walk along instead.
  # The map cannot be rotated, so a leg drawn left to right gives no clue whether it
  # runs east or west. Naming the direction in words is legible where a 12 pixel pin
  # on satellite imagery is not.
  def step_heading(step, segment = 0)
    points = segment_points(step, segment)
    return nil if points.length < 2

    compass_point(bearing_between(points.first, points.last))
  end

  def step_segment_count(step)
    points = walkable_points(step)
    return 1 if points.length < 2

    [(polyline_length(points) / SEGMENT_METRES).ceil, 1].max
  end

  private

  def build_google_map_static_step_image_api(step, segment)
    uri = URI('https://maps.googleapis.com/maps/api/staticmap')
    points = segment_points(step, segment)
    centre, zoom = frame_for(points)

    params = {
      key: @key,
      size: "#{IMAGE_SIZE}x#{IMAGE_SIZE}",
      maptype: 'hybrid',
      center: centre,
      zoom: zoom,
      # Marked at the ends of this window, not of the whole step. Pinned to the step
      # they both sat outside the frame on every middle chunk, leaving a bare line
      # with nothing to say which way along it you were walking.
      markers: [
        "size:mid|color:green|label:A|#{points.first.first},#{points.first.last}",
        "size:mid|color:red|label:B|#{points.last.first},#{points.last.last}"
      ],
      path: "enc:#{step['polyline']['points']}"
    }

    uri.query = URI.encode_www_form(params)
    uri
  end

  # Frame the window being walked right now rather than the whole step. Google's own
  # fit leaves a single turn as a speck, and a long step fitted whole is unreadable.
  # Centring each window means every stretch gets its own view, not just the first.
  def frame_for(points)
    zoom = zoom_for_leg(points)

    [centre_ahead_of(points, zoom), zoom]
  end

  # Ask for a frame wider than the leg itself, since part of it is given over to the
  # ground already behind the walker.
  def zoom_for_leg(points)
    lats = points.map(&:first)
    lngs = points.map(&:last)
    padding = (1 - (2 * BEHIND_FRACTION))
    lat_span = (lats.max - lats.min) / padding / 2
    lng_span = (lngs.max - lngs.min) / padding / 2
    mid_lat = (lats.min + lats.max) / 2
    mid_lng = (lngs.min + lngs.max) / 2

    zoom = zoom_for(mid_lat - lat_span, mid_lat + lat_span, mid_lng - lng_span, mid_lng + lng_span)
    [zoom, MIN_STEP_ZOOM].max
  end

  # Push the centre forward along the leg so the walker's own position sits near the
  # bottom of the frame with the road ahead of them filling the rest. The map itself
  # cannot be rotated, so north stays up: this makes the position predictable, not
  # the direction.
  def centre_ahead_of(points, zoom)
    start = points.first
    forward = (0.5 - BEHIND_FRACTION) * frame_metres(start.first, zoom)
    bearing = bearing_between(start, points.last)
    latitude = start.first + ((forward * Math.cos(bearing)) / METRES_PER_DEGREE)
    longitude = start.last + ((forward * Math.sin(bearing)) /
                             (METRES_PER_DEGREE * Math.cos(start.first * Math::PI / 180)))

    centre_of(latitude, longitude)
  end

  def frame_metres(lat, zoom)
    EQUATOR_METRES_PER_PIXEL * Math.cos(lat * Math::PI / 180) / (2**zoom) * IMAGE_SIZE
  end

  def compass_point(bearing)
    degrees = ((bearing * 180 / Math::PI) + 360) % 360

    I18n.t("compass.#{COMPASS_POINTS[((degrees + 22.5) / 45).floor % COMPASS_POINTS.length]}")
  end

  # Radians clockwise from north.
  def bearing_between(from, to)
    delta_lat = to.first - from.first
    delta_lon = (to.last - from.last) * Math.cos(from.first * Math::PI / 180)

    Math.atan2(delta_lon, delta_lat)
  end

  def centre_of(lat, lng)
    format('%<lat>.6f,%<lng>.6f', lat: lat, lng: lng)
  end

  # The stretch this window covers. The ends are interpolated so that a straight road
  # recorded as just two points still yields a distinct view per window.
  def segment_points(step, segment)
    points = walkable_points(step)
    return points if points.length < 2

    from = segment * SEGMENT_METRES
    to = from + SEGMENT_METRES

    [point_at(points, from)] + points_between(points, from, to) + [point_at(points, to)]
  end

  def walkable_points(step)
    points = decode_polyline(step['polyline']['points'])
    return points if points.length >= 2

    [[step['start_location']['lat'], step['start_location']['lng']],
     [step['end_location']['lat'], step['end_location']['lng']]]
  end

  def points_between(points, from, to)
    travelled = 0.0
    selected = []

    points.each_with_index do |point, index|
      travelled += metres_between(points[index - 1], point) if index.positive?
      selected << point if travelled > from && travelled < to
    end

    selected
  end

  def point_at(points, distance)
    travelled = 0.0

    points.each_cons(2) do |from, to|
      leg = metres_between(from, to)
      if travelled + leg >= distance
        ratio = leg.zero? ? 0.0 : (distance - travelled) / leg
        return [from[0] + ((to[0] - from[0]) * ratio), from[1] + ((to[1] - from[1]) * ratio)]
      end

      travelled += leg
    end

    points.last
  end

  def polyline_length(points)
    points.each_cons(2).sum { |from, to| metres_between(from, to) }
  end

  def metres_between(from, to)
    delta_lat = (to[0] - from[0]) * METRES_PER_DEGREE
    delta_lon = (to[1] - from[1]) * METRES_PER_DEGREE * Math.cos(from[0] * Math::PI / 180)

    Math.sqrt((delta_lat * delta_lat) + (delta_lon * delta_lon))
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
      units: @units,
      # Turn instructions come back translated, which matters more than the chrome
      # around them: a German menu wrapped around "Turn left" helps nobody.
      language: I18n.locale
    }

    uri.query = URI.encode_www_form(params)
    uri
  end

  def get_routes_from_google_maps_uri(uri)
    res = Net::HTTP.get_response(uri)
    unless res.is_a?(Net::HTTPSuccess)
      @error = I18n.t('directions.unavailable')
      return
    end

    body = JSON.parse(res.body)
    unless body['status'] == 'OK'
      @error = I18n.t("directions.#{STATUS_KEYS.fetch(body['status'], 'could_not_plan')}")
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
