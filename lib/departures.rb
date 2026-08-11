# frozen_string_literal: true

require 'net/http'
require 'uri'

class Departures
  BASE = 'https://transit.land/api/v2/rest'
  NEARBY_RADIUS_METRES = 1000
  MAX_STOPS = 10
  # Stations and repeated names are dropped from the result, so ask for more than are
  # shown or a busy interchange fills the list before any other stop is reached.
  REQUEST_LIMIT = 40
  MAX_DEPARTURES = 8
  # Departures beyond the next couple of hours are no use to someone standing at a
  # stop, and asking for fewer keeps the response small over 4G.
  WINDOW_SECONDS = 7200

  # Transitland reports whether each departure is backed by real time data. STATIC
  # means the agency publishes no feed for it, so the time is the timetable and must
  # not be presented as anything more.
  LIVE_STATUSES = %w[SCHEDULED ADDED].freeze

  attr_reader :error

  def initialize(params)
    @key = Rails.application.credentials.transitland.api_key
    @lat = params[:lat]
    @lon = params[:lon]
    @stop_id = params[:stop_id]
  end

  def nearby_stops
    return [] if @lat.blank? || @lon.blank?

    body = fetch(stops_uri)
    return [] if body.nil?

    (body['stops'] || []).filter_map { |stop| stop_from(stop) }
                         .uniq { |stop| stop[:name] }
                         .first(MAX_STOPS)
  end

  def next_departures
    return [] if @stop_id.blank?

    body = fetch(departures_uri)
    return [] if body.nil?

    # One stop can come back as several entries when more than one feed covers it, and
    # reading only the first quietly dropped the departures held by the rest.
    (body['stops'] || []).flat_map { |stop| departures_at(stop) }
                         .sort_by { |departure| departure[:time] }
                         .first(MAX_DEPARTURES)
  end

  private

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

  def fetch(uri)
    res = Net::HTTP.get_response(uri)
    unless res.is_a?(Net::HTTPSuccess)
      @error = I18n.t('departures.unavailable')
      return nil
    end

    JSON.parse(res.body)
  rescue JSON::ParserError
    @error = I18n.t('departures.unreadable')
    nil
  end

  # A station is a building rather than a boarding point. Transitland hangs departures
  # off the platforms inside it, so offering the station itself only ever led to a page
  # claiming nothing was due at a stop with buses standing in it.
  def stop_from(stop)
    return nil unless stop['location_type'].to_i.zero?

    name = stop['stop_name'].presence
    return nil if name.blank? || stop['onestop_id'].blank?

    { id: stop['onestop_id'], name: stand_name(stop, name) }
  end

  # Stands at one interchange usually share a name, so the stand number is the only
  # thing that tells them apart in a list.
  def stand_name(stop, name)
    code = stop['platform_code'].presence
    return name if code.blank? || name.downcase.include?(code.downcase)

    "#{name} (#{code})"
  end

  def departures_at(stop)
    (stop['departures'] || []).filter_map { |departure| departure_from(departure, stop['stop_name']) }
  end

  def departure_from(departure, stop_name)
    time = departure_time(departure)
    return nil if time.blank?

    {
      time: time.to_s[0, 5],
      live: LIVE_STATUSES.include?(departure['schedule_relationship'].to_s.upcase),
      route: route_name(departure),
      towards: towards(departure, stop_name)
    }
  end

  # Prefer the estimate when the agency publishes one, otherwise the timetable.
  def departure_time(departure)
    estimated = departure['departure'].is_a?(Hash) ? departure['departure']['estimated'] : nil

    estimated.presence || departure['departure_time']
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
