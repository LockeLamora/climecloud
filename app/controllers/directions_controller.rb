# frozen_string_literal: true

require 'maps'
require 'geocode'

class DirectionsController < ApplicationController
  # Planning one route spends three Google calls — geocoding what was typed, the route
  # itself, then a static map image — all against the same key.
  before_action :require_saved_location

  def search
    render :search
  end

  def plan
    # Both ends are needed before anything is asked of Google. An empty field is an
    # INVALID_REQUEST there, which costs a call to be told what is already known here, and
    # the reader sees the same message either way.
    if endpoint_missing?
      @error = I18n.t('directions.fill_in_both')
      render :search
      return
    end

    session['maps'] = Maps.new({
                                 origin: params[:origin],
                                 destination: params[:destination],
                                 mode: params[:mode],
                                 units: resolve_unit
                               })

    plan = session['maps'].get_routes
    @route_params = params.permit(:origin, :destination, :mode).to_h

    if plan.nil?
      @error = session['maps'].error
      render_failed_lookup(session['maps'].unresolved.first)
      return
    end

    @steps = plan[:steps]
    @overall_time = plan[:overall_time]
    @start = plan[:start]
    @end = plan[:end]
    @overview_polyline = plan[:overview_polyline]
    @start_location = plan[:start_location]
    @end_location = plan[:end_location]
    @ambiguous = ambiguous_fields

    if params[:view] == 'turn' && @steps.present?
      render_turn
      return
    end

    @image = session['maps'].get_static_map_image_api(@overview_polyline) if cookies['show_map'] == '1'
    render :route
  end

  # Reached from the route page when Google matched loosely and picked the wrong place.
  def pick
    @route_params = params.permit(:origin, :destination, :mode).to_h
    render_candidates(params[:field] == 'origin' ? 'origin' : 'destination')
  end

  # Carried into the pick link so the alternatives are searched around where Google
  # placed the endpoint the user is not currently changing.
  def bias_params_for(field)
    other = field == 'origin' ? @end_location : @start_location
    return {} if other.blank?

    { 'bias_lat' => other['lat'].to_s, 'bias_lon' => other['lng'].to_s }
  end
  helper_method :bias_params_for

  private

  def endpoint_missing?
    params[:origin].to_s.strip.empty? || params[:destination].to_s.strip.empty?
  end

  # Google picks one reading of free text without saying so, and a street name common to
  # several towns can resolve to the wrong one. Anything typed as text is worth a second
  # look; anything already pinned to a place_id is not.
  def ambiguous_fields
    %w[origin destination].reject do |field|
      value = @route_params[field].to_s.strip
      # Coordinates come from the places list and are already exact.
      value.start_with?('place_id:') || value.match?(/\A-?\d+(\.\d+)?,-?\d+(\.\d+)?\z/)
    end
  end

  # Google could not place one of the endpoints, so offer what it does know
  # rather than dropping the user back on an empty form.
  def render_failed_lookup(field)
    if field.nil?
      render :search
      return
    end

    render_candidates(field)
  end

  # Search around the other end of the journey: a route from a town to a street name has
  # to look near that town rather than near the settings postcode, or a matching street
  # 200 metres away never appears.
  def bias_point(field)
    return [params[:bias_lat], params[:bias_lon]] if params[:bias_lat].present? && params[:bias_lon].present?

    other = field == 'origin' ? 'destination' : 'origin'
    coordinates = coordinates_in(@route_params[other])
    return coordinates if coordinates

    geocode_endpoint(@route_params[other]) || [cookies['lat'], cookies['lon']]
  end

  # Only reached when there is no resolved route to borrow coordinates from, so the
  # other end has to be placed before this one can be searched around it.
  def geocode_endpoint(value)
    return nil if value.blank?

    candidate = Geocode.new({
                              address: value,
                              country_code: cookies['country_code']
                            }).get_candidates.first

    candidate && [candidate[:lat], candidate[:lon]]
  end

  def coordinates_in(value)
    match = value.to_s.strip.match(/\A(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)\z/)
    match && [match[1], match[2]]
  end

  def render_candidates(field)
    @field = field
    bias_lat, bias_lon = bias_point(field)
    @candidates = Geocode.new({
                                address: @route_params[field],
                                country_code: cookies['country_code'],
                                bias_lat: bias_lat,
                                bias_lon: bias_lon
                              }).get_candidates

    if @candidates.empty?
      @error = I18n.t('directions.not_found')
      render :search
      return
    end

    render :pick
  end

  # No GPS on these handsets, so the user advances a turn at a time themselves.
  def render_turn
    @step_index = params[:step].to_i.clamp(0, @steps.length - 1)
    @step = @steps[@step_index]
    @segments = session['maps'].step_segment_count(@step)
    @segment = params[:segment].to_i.clamp(0, @segments - 1)
    @heading = session['maps'].step_heading(@step, @segment)

    @image = session['maps'].get_static_map_step_image_api(@step, @segment) if cookies['show_map'] == '1'
    render :turn
  end

  def resolve_unit
    metrics = {
      'imperial' => 'imperial',
      'metric' => 'metric',
      'hybrid' => 'imperial'
    }

    metrics[cookies['metrics']]
  end
end
