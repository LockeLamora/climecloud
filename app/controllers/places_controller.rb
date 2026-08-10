# frozen_string_literal: true

require 'places'
require 'geocode'

class PlacesController < ApplicationController
  def index
    return unless location_known?

    render :index
  end

  # Somewhere typed in by hand. Nothing is remembered between visits: the choice is
  # carried in the URL and forgotten as soon as the user leaves.
  def search
    @candidates = Geocode.new({
                                address: params[:query],
                                country_code: cookies['country_code']
                              }).get_candidates

    if @candidates.empty?
      location_known?
      @error = 'Could not find that place, please try again'
      render :index
      return
    end

    if @candidates.length == 1
      redirect_to places_path(place_params(@candidates.first))
      return
    end

    render :pick
  end

  def list
    return unless location_known?

    @kind = Places::CATEGORIES[params[:kind]]
    if @kind.nil?
      redirect_to places_path
      return
    end

    places = Places.new({ lat: @lat, lon: @lon, kind: params[:kind] })
    @places = places.get_places
    @error = places.error

    render :list
  end

  private

  # Either the postcode saved in settings, or somewhere passed along in the URL.
  # There is no GPS, so one of the two has to say where "nearby" means.
  def location_known?
    @lat = params[:lat].presence || cookies[:lat]
    @lon = params[:lon].presence || cookies[:lon]
    @place = params[:place].presence || cookies[:city]

    return true if @lat.present? && @lon.present?

    redirect_to '/settings'
    false
  end

  def place_params(candidate)
    { lat: candidate[:lat], lon: candidate[:lon], place: candidate[:address] }
  end

  def carried_location
    { lat: params[:lat], lon: params[:lon], place: params[:place] }
  end
  helper_method :carried_location
end
