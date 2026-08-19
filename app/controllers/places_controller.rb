# frozen_string_literal: true

require 'places'
require 'geocode'

class PlacesController < ApplicationController
  MAX_SAVED_PLACES = 5

  # A pure read: a typed-in place is only remembered by #save, so a browser that
  # fetches links ahead of the cursor cannot fill the saved list with places the
  # reader scrolled past.
  def index
    return unless location_known?

    @saved = saved_places
    # Digits nine and zero are the navigation on every page in this app, so a ninth
    # category cannot have a key of its own and the list is paged instead.
    @page = [params[:page].to_i, 0].max
    @kinds = Places::CATEGORIES.keys.drop(@page * Places::PAGE_SIZE).first(Places::PAGE_SIZE)
    @more_kinds = Places::CATEGORIES.length > (@page + 1) * Places::PAGE_SIZE
    render :index
  end

  def forget
    cookies.delete(:places_recent)
    redirect_to places_path
  end

  # Chosen from the "which did you mean?" list. Remembers the place and sends the
  # reader on to the categories page as a plain GET, which stores nothing. The pressed
  # button's value carries the whole choice — two coordinates that never hold a space,
  # then the address, which may — so the first two spaces are the seams.
  def save
    params[:lat], params[:lon], params[:place] = params[:choice].split(' ', 3) if params[:choice].present?
    return unless location_known?

    remember_place(params[:place], @lat, @lon) if params[:place].present?
    redirect_to places_path(place: params[:place], lat: params[:lat], lon: params[:lon])
  end

  # Somewhere typed in by hand. Nothing is remembered between visits: the choice is
  # carried in the URL and forgotten as soon as the user leaves.
  def search
    @candidates = Geocode.new({
                                address: params[:query],
                                country_code: cookies['country_code'],
                                bias_lat: cookies['lat'],
                                bias_lon: cookies['lon']
                              }).get_candidates

    if @candidates.empty?
      location_known?
      @error = I18n.t('places.not_found')
      render :index
      return
    end

    if @candidates.length == 1
      # One match needs no picking, so it is remembered here: this URL is only ever
      # reached by submitting the search form, which nothing prefetches.
      candidate = @candidates.first
      remember_place(candidate[:address], candidate[:lat], candidate[:lon])
      redirect_to places_path(place_params(candidate))
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
    # Categories do not all search the same distance, so the page says the one it used.
    @radius = places.radius

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

  # Typed in places are kept client side like every other setting, so somewhere
  # visited twice does not have to be typed twice on a keypad.
  def saved_places
    JSON.parse(cookies[:places_recent].presence || '[]')
  rescue JSON::ParserError
    []
  end

  def remember_place(place, lat, lon)
    entry = { 'place' => place, 'lat' => lat, 'lon' => lon }
    others = saved_places.reject { |saved| saved['place'] == entry['place'] }

    cookies.permanent[:places_recent] = ([entry] + others).first(MAX_SAVED_PLACES).to_json
  end

  def place_params(candidate)
    { lat: candidate[:lat], lon: candidate[:lon], place: candidate[:address] }
  end

  def carried_location
    { lat: params[:lat], lon: params[:lon], place: params[:place] }
  end
  helper_method :carried_location
end
