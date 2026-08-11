# frozen_string_literal: true

require 'departures'

class DeparturesController < ApplicationController
  MAX_SAVED_STOPS = 5

  # Straight off the main menu with the saved stops listed, so a commuter reaches
  # times in two keypresses rather than planning a route to get there.
  def index
    return unless departures_enabled?

    @stops = saved_stops
    render :index
  end

  def stop
    return unless departures_enabled?

    @stop = saved_stops.find { |saved| saved['id'] == params[:id] }
    if @stop.nil?
      redirect_to departures_path
      return
    end

    service = Departures.new({ stop_id: @stop['id'] })
    @departures = service.next_departures
    @error = service.error
    @untimetabled = service.untimetabled?

    render :stop
  end

  def add
    return unless departures_enabled?

    unless cookies[:lat].present? && cookies[:lon].present?
      redirect_to '/settings'
      return
    end

    service = Departures.new({ lat: cookies[:lat], lon: cookies[:lon], page: params[:page] })
    @nearby = service.nearby_stops
    @error = service.error
    @page = [params[:page].to_i, 0].max
    @more = service.more_stops?

    render :add
  end

  def save
    return unless departures_enabled?

    remember_stop if params[:id].present? && params[:name].present?
    redirect_to departures_path
  end

  def forget
    return unless departures_enabled?

    cookies.delete(:departures_saved)
    redirect_to departures_path
  end

  private

  # The key arrives with the Rails master key on the host, so on any deployment
  # without it every action here would die on a nil credential. Send people back to
  # the menu, where the entry reads "coming soon" rather than linking anywhere.
  def departures_enabled?
    return true if Rails.application.credentials.transitland&.api_key.present?

    redirect_to root_path
    false
  end

  # Kept client side like every other setting, so the dashboard still stores nothing.
  def saved_stops
    JSON.parse(cookies[:departures_saved].presence || '[]')
  rescue JSON::ParserError
    []
  end

  def remember_stop
    entry = { 'id' => params[:id], 'name' => params[:name] }
    others = saved_stops.reject { |saved| saved['id'] == entry['id'] }

    cookies.permanent[:departures_saved] = ([entry] + others).first(MAX_SAVED_STOPS).to_json
  end
end
