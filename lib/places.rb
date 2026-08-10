# frozen_string_literal: true

require 'net/http'
require 'uri'

class Places
  RADIUS_METRES = 5000
  MAX_RESULTS = 10

  # Grouped rather than one entry per Geoapify category: splitting Food into
  # restaurant, cafe and fast food would triple the menu on a 240x320 screen, and
  # the API takes a comma separated list in a single request anyway.
  CATEGORIES = {
    'petrol' => { label: 'Petrol', categories: 'service.vehicle.fuel' },
    'food' => { label: 'Food', categories: 'catering.restaurant,catering.fast_food,catering.cafe' },
    'shops' => { label: 'Shops', categories: 'commercial.supermarket,commercial.convenience' },
    'cash' => { label: 'Cash', categories: 'service.financial.atm,service.financial.bank' },
    'toilets' => { label: 'Toilets', categories: 'amenity.toilet' },
    'pharmacy' => { label: 'Pharmacy', categories: 'commercial.health_and_beauty.pharmacy' },
    'pub' => { label: 'Pub', categories: 'catering.pub,catering.bar' },
    'transport' => { label: 'Transport', categories: 'public_transport.bus,public_transport.train' }
  }.freeze

  attr_reader :error

  def initialize(params)
    @key = Rails.application.credentials.geoapify.api_key
    @lat = params[:lat]
    @lon = params[:lon]
    @kind = CATEGORIES[params[:kind]]
  end

  def get_places
    return [] if @kind.nil? || @lat.blank? || @lon.blank?

    uri = build_geoapify_places_uri
    get_places_from_geoapify_uri(uri)
  end

  private

  def build_geoapify_places_uri
    uri = URI('https://api.geoapify.com/v2/places')
    params = {
      apiKey: @key,
      categories: @kind[:categories],
      # Geoapify wants longitude first in these two, the reverse of every other
      # coordinate this app passes around.
      filter: "circle:#{@lon},#{@lat},#{RADIUS_METRES}",
      bias: "proximity:#{@lon},#{@lat}",
      limit: MAX_RESULTS
    }

    uri.query = URI.encode_www_form(params)
    uri
  end

  def get_places_from_geoapify_uri(uri)
    res = Net::HTTP.get_response(uri)
    unless res.is_a?(Net::HTTPSuccess)
      @error = 'Could not look up places, please try again later'
      return []
    end

    body = JSON.parse(res.body)
    places = (body['features'] || []).map { |feature| place_from(feature) }
    places.sort_by { |place| place[:distance] || Float::INFINITY }
  end

  def place_from(feature)
    properties = feature['properties'] || {}

    {
      name: place_name(properties),
      distance: properties['distance'],
      lat: properties['lat'],
      lon: properties['lon']
    }
  end

  # OSM records are frequently unnamed, public toilets especially, so fall back to
  # whatever else would help someone recognise the place on the ground.
  def place_name(properties)
    properties['name'].presence ||
      properties['address_line1'].presence ||
      properties['street'].presence ||
      'Unnamed'
  end
end
