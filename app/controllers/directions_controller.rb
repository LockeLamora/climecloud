# frozen_string_literal: true

require 'maps'
require 'geocode'

class DirectionsController < ApplicationController
  def search
    render :search
  end

  def plan
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

  private

  # Google picks one reading of free text without saying so, and a street name common
  # to several towns silently resolves to the wrong one. Anything the user typed is
  # worth a second look; anything already pinned to a place_id is not.
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

  def render_candidates(field)
    @field = field
    @candidates = Geocode.new({
                                address: @route_params[field],
                                country_code: cookies['country_code']
                              }).get_candidates

    if @candidates.empty?
      @error = 'Could not find that place, please try again'
      render :search
      return
    end

    render :pick
  end

  # No GPS on these handsets, so the user advances a turn at a time themselves.
  def render_turn
    @step_index = params[:step].to_i.clamp(0, @steps.length - 1)
    @step = @steps[@step_index]

    @image = session['maps'].get_static_map_step_image_api(@step) if cookies['show_map'] == '1'
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
