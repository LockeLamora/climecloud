# frozen_string_literal: true
require 'maps'

class DirectionsController < ApplicationController
  def search
    render :search
  end

  def plan
    session["maps"] = Maps.new({
      origin: params[:origin],
      destination: params[:destination],
      mode: params[:mode],
      units: resolve_unit
    })

    plan = session["maps"].get_routes
    pp plan.inspect
    @steps = plan[:steps]
    @overall_time = plan[:overall_time]
    @start = plan[:start]
    @end = plan[:end]
    @overview_polyline = plan[:overview_polyline]
    
    unless @error.nil?
      render :search
      return
    end
    if cookies['show_map'] == '1'
      @image = session["maps"].get_static_map_image_api(@overview_polyline)
    end
    render :route
  end

  private

  def resolve_unit
    metrics = {
      'imperial' => 'imperial',
      'metrics' => 'metric',
      'hybrid' => 'imperial'
    }

    metrics[cookies['metrics']]
  end
end
