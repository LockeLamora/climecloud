# frozen_string_literal: true

require 'net/http'
require 'uri'

class Departures
  BASE = 'https://transit.land/api/v2/rest'
  NEARBY_RADIUS_METRES = 1000
  # About what fits on a small screen without scrolling. The rest are not thrown away:
  # they are reached a page at a time, since the stop someone wants is not always among
  # the nearest handful.
  PAGE_SIZE = 10
  # Stations and repeated names are dropped from the result, so ask for far more than
  # any one page shows. This is also what caps how far the paging can go.
  REQUEST_LIMIT = 100
  MAX_DEPARTURES = 8
  METRES_PER_DEGREE = 111_320
  # Naming a destination costs a request, so only a few are worth making. Trips sharing
  # a stop pattern share a last stop, which keeps that number to one per pattern.
  MAX_TERMINUS_LOOKUPS = 4
  # Departures beyond the next couple of hours are no use to someone standing at a
  # stop, and asking for fewer keeps the response small over 4G.
  WINDOW_SECONDS = 7200

  # A stop named after a railway station is very often a bus stop outside one, so what
  # kind of vehicle is coming has to be said rather than guessed at from the stop name.
  MODE_KEYS = {
    0 => 'tram', 1 => 'metro', 2 => 'rail', 3 => 'bus', 4 => 'ferry',
    5 => 'tram', 11 => 'bus', 12 => 'metro'
  }.freeze
  # The extended route types agencies increasingly publish instead, narrowed to the
  # handful of words worth putting on a small screen. A coach is a bus to a passenger.
  EXTENDED_MODES = {
    (100..199) => 'rail', (200..299) => 'bus', (400..499) => 'rail',
    (700..799) => 'bus', (800..899) => 'bus', (900..999) => 'tram', (1000..1099) => 'ferry'
  }.freeze

  # Transitland reports whether each departure is backed by real time data. STATIC
  # means the agency publishes no feed for it, so the time is the timetable and must
  # not be presented as anything more.
  LIVE_STATUSES = %w[SCHEDULED ADDED].freeze

  attr_reader :error

  # Some stops exist only as locations, inherited from a feed that carries no services
  # for them: metro platforms named in a bus feed, for instance. They can never produce
  # a departure, and saying "nothing due" of one reads as a fault in the dashboard.
  def untimetabled?
    @untimetabled.present?
  end

  def initialize(params)
    @key = Rails.application.credentials.transitland.api_key
    @lat = params[:lat]
    @lon = params[:lon]
    @stop_id = params[:stop_id]
    @page = [params[:page].to_i, 0].max
  end

  def nearby_stops
    return [] if @lat.blank? || @lon.blank?

    body = fetch(stops_uri)
    return [] if body.nil?

    @nearby = nearest_first(body['stops'] || [])
    @nearby.drop(@page * PAGE_SIZE).first(PAGE_SIZE)
  end

  # Whether asking for another page would find anything, so a link to one that would
  # come back empty is never offered.
  def more_stops?
    @nearby.to_a.length > (@page + 1) * PAGE_SIZE
  end

  def next_departures
    return [] if @stop_id.blank?

    body = fetch(departures_uri)
    return [] if body.nil?

    departures = merged_departures(body)
    @untimetabled = departures.empty? && !any_timetable?

    name_missing_destinations(departures)
  end

  private

  # The search comes back in no useful order, so the ten kept were an arbitrary ten and
  # the stands of a nearby interchange lost their places to stops half a mile off.
  def nearest_first(stops)
    stops.filter_map { |stop| stop_from(stop) }
         .sort_by { |stop| stop[:metres] }
         .uniq { |stop| stop[:name] }
  end

  def stops_uri
    build_uri("#{BASE}/stops", lat: @lat, lon: @lon, radius: NEARBY_RADIUS_METRES, limit: REQUEST_LIMIT)
  end

  def departures_uri
    build_uri("#{BASE}/stops/#{@stop_id}/departures", next: WINDOW_SECONDS, limit: MAX_DEPARTURES)
  end

  def build_uri(base, params)
    uri = URI(base)
    uri.query = URI.encode_www_form(params.merge(apikey: @key))
    uri
  end

  # Quiet for the lookups that only add a nicety: failing to name a destination is no
  # reason to put an error across a page that has the times on it.
  def fetch(uri, quiet: false)
    res = Net::HTTP.get_response(uri)
    unless res.is_a?(Net::HTTPSuccess)
      @error = I18n.t('departures.unavailable') unless quiet
      return nil
    end

    JSON.parse(res.body)
  rescue JSON::ParserError
    @error = I18n.t('departures.unreadable') unless quiet
    nil
  end

  # A station is a building rather than a boarding point. Transitland hangs departures
  # off the platforms inside it, so offering the station itself only ever led to a page
  # claiming nothing was due at a stop with buses standing in it.
  def stop_from(stop)
    return nil unless stop['location_type'].to_i.zero?

    name = stop['stop_name'].presence
    return nil if name.blank? || stop['onestop_id'].blank?

    { id: stop['onestop_id'], name: stand_name(stop, name), metres: metres_away(stop) }
  end

  def metres_away(stop)
    coordinates = stop.dig('geometry', 'coordinates')
    return Float::INFINITY unless coordinates.is_a?(Array) && coordinates.length >= 2

    east = (coordinates[0].to_f - @lon.to_f) * METRES_PER_DEGREE * Math.cos(@lat.to_f * Math::PI / 180)
    north = (coordinates[1].to_f - @lat.to_f) * METRES_PER_DEGREE

    Math.sqrt((east * east) + (north * north))
  end

  # Stands at one interchange usually share a name, so the stand number is the only
  # thing that tells them apart in a list.
  def stand_name(stop, name)
    code = stop['platform_code'].presence
    return name if code.blank? || name.downcase.include?(code.downcase)

    "#{name} (#{code})"
  end

  # One stop can come back as several entries when more than one feed covers it, and
  # reading only the first quietly dropped the departures held by the rest. Two feeds
  # describing the same journey then arrive seconds apart, so identical rows collapse.
  def merged_departures(body)
    (body['stops'] || []).flat_map { |stop| departures_at(stop) }
                         .sort_by { |departure| departure[:time] }
                         .uniq { |departure| departure.values_at(:time, :route, :towards) }
                         .first(MAX_DEPARTURES)
  end

  # Asked without the two hour window, so a stop that simply has nothing due soon is
  # told apart from one that has no service at any hour. Only reached when the page
  # would otherwise be empty, so it costs nothing in the ordinary case.
  def any_timetable?
    body = fetch(build_uri("#{BASE}/stops/#{@stop_id}/departures", limit: 1), quiet: true)
    # Unreachable is not the same as unserved, so claim nothing.
    return true if body.nil?

    (body['stops'] || []).any? { |stop| (stop['departures'] || []).any? }
  end

  def departures_at(stop)
    (stop['departures'] || []).filter_map { |departure| departure_from(departure, stop['stop_name']) }
  end

  def departure_from(departure, stop_name)
    time = departure_time(departure)
    return nil if time.blank?

    trip = departure['trip'] || {}

    {
      time: time.to_s[0, 5],
      live: LIVE_STATUSES.include?(departure['schedule_relationship'].to_s.upcase),
      route: route_name(departure),
      towards: towards(departure, stop_name),
      mode: mode_key(trip.dig('route', 'route_type')),
      pattern: trip['stop_pattern_id'],
      route_id: trip.dig('route', 'onestop_id'),
      trip_id: trip['id']
    }
  end

  # Some agencies publish no headsign of any kind, which left every row saying nothing
  # but a route number. A trip's last stop is where it ends up, so it can be looked up
  # instead. Trips running the same stop pattern end at the same place, so a page of
  # eight departures usually needs one or two requests rather than eight.
  def name_missing_destinations(departures)
    patterns = departures.reject { |departure| departure[:towards].present? }
                         .group_by { |departure| departure[:pattern] }
                         .reject { |pattern, _| pattern.blank? }
                         .first(MAX_TERMINUS_LOOKUPS)
    return departures if patterns.empty?

    termini = look_up_termini(patterns)
    departures.each { |departure| departure[:towards] ||= termini[departure[:pattern]] }
  end

  # In parallel, because these run one after the other on a page someone is waiting on
  # at a bus stop, and the requests do not depend on each other.
  def look_up_termini(patterns)
    patterns.map { |pattern, group| Thread.new { [pattern, terminus_for(group.first)] } }
            .map(&:value)
            .to_h
  end

  def terminus_for(departure)
    route = departure[:route_id]
    trip = departure[:trip_id]
    return nil if route.blank? || trip.blank?

    body = fetch(build_uri("#{BASE}/routes/#{route}/trips/#{trip}", {}), quiet: true)
    return nil if body.nil?

    last_stop_of(body)
  end

  def last_stop_of(body)
    trip = (body['trips'] || []).first || {}
    stop_times = trip['stop_times'] || []

    stop_times.last&.dig('stop', 'stop_name').presence
  end

  # Prefer the estimate when the agency publishes one, otherwise the timetable.
  def departure_time(departure)
    estimated = departure['departure'].is_a?(Hash) ? departure['departure']['estimated'] : nil

    estimated.presence || departure['departure_time']
  end

  # Nil rather than a guess when the type is missing or is something no word here fits:
  # saying nothing is better than calling a funicular a tram.
  def mode_key(route_type)
    return nil if route_type.nil?

    type = route_type.to_i
    return MODE_KEYS[type] if MODE_KEYS.key?(type)

    EXTENDED_MODES.find { |types, _| types.cover?(type) }&.last
  end

  def route_name(departure)
    trip = departure['trip'] || {}
    route = trip['route'] || {}

    route['route_short_name'].presence || route['route_long_name'].presence
  end

  # Where the bus is actually going, which is the one thing someone waiting needs to
  # know. The trip's own headsign comes first because some feeds put the stand
  # description in stop_headsign, which reads as every row naming the stop you are
  # already standing at. The route's long name is a last resort: it lists both ends of
  # the line, so it at least says which way the service runs.
  def towards(departure, stop_name)
    trip = departure['trip'] || {}
    sign = trip['trip_headsign'].presence || departure['stop_headsign'].presence
    sign = nil if repeats_stop?(sign, stop_name)

    sign || (trip['route'] || {})['route_long_name'].presence
  end

  # Only when the headsign says no more than the heading above it already does. A
  # destination that merely contains the stop name, such as leaving Bolton for Bolton
  # Interchange, is still worth showing.
  def repeats_stop?(sign, stop_name)
    return false if sign.blank? || stop_name.blank?

    stripped = ->(text) { text.to_s.downcase.gsub(/[^a-z0-9]/, '') }

    stripped.call(stop_name).include?(stripped.call(sign))
  end
end
