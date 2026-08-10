# frozen_string_literal: true

require 'net/http'
require 'uri'

class Departures
  BASE = 'https://transit.land/api/v2/rest'
  NEARBY_RADIUS_METRES = 1000
  MAX_STOPS = 10
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

    (body['stops'] || []).filter_map { |stop| stop_from(stop) }.first(MAX_STOPS)
  end

  def next_departures
    return [] if @stop_id.blank?

    body = fetch(departures_uri)
    return [] if body.nil?

    stop = (body['stops'] || []).first
    return [] if stop.nil?

    (stop['departures'] || []).filter_map { |departure| departure_from(departure) }.first(MAX_DEPARTURES)
  end

  private

  def stops_uri
    build_uri("#{BASE}/stops", lat: @lat, lon: @lon, radius: NEARBY_RADIUS_METRES, limit: MAX_STOPS)
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
      @error = 'Could not reach the departures service, please try again later'
      return nil
    end

    JSON.parse(res.body)
  rescue JSON::ParserError
    @error = 'Could not read the departures service response'
    nil
  end

  def stop_from(stop)
    name = stop['stop_name'].presence
    return nil if name.blank? || stop['onestop_id'].blank?

    { id: stop['onestop_id'], name: name }
  end

  def departure_from(departure)
    time = departure_time(departure)
    return nil if time.blank?

    {
      time: time.to_s[0, 5],
      live: LIVE_STATUSES.include?(departure['schedule_relationship'].to_s.upcase),
      route: route_name(departure),
      towards: headsign(departure)
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

  def headsign(departure)
    trip = departure['trip'] || {}

    departure['stop_headsign'].presence || trip['trip_headsign'].presence
  end
end
