# frozen_string_literal: true

require 'net/http'
require 'uri'

class Places
  RADIUS_METRES = 5000
  MAX_RESULTS = 10
  # Ask for more than we show, because stops on opposite sides of the same road come
  # back as separate records under one name and collapse into a single entry.
  REQUEST_LIMIT = 20
  BUS_CATEGORY = 'public_transport.bus'
  STATION_NAME = /station|interchange|bus stn/i

  # Geoapify names bus stops after the road junction they sit on, so without a label
  # the list reads as a column of street names with no clue what any of them are.
  KIND_KEYS = {
    'public_transport.bus' => 'bus_station',
    'public_transport.train' => 'train_station',
    'public_transport.subway' => 'metro_station',
    'service.taxi' => 'taxi_rank',
    'service.vehicle.fuel' => 'petrol_station',
    'commercial.supermarket' => 'supermarket',
    'commercial.convenience' => 'convenience',
    'commercial.health_and_beauty.pharmacy' => 'pharmacy',
    'catering.restaurant' => 'restaurant',
    'catering.fast_food' => 'fast_food',
    'catering.cafe' => 'cafe',
    'catering.pub' => 'pub',
    'catering.bar' => 'bar',
    'service.financial.atm' => 'atm',
    'service.financial.bank' => 'bank',
    'amenity.toilet' => 'toilet'
  }.freeze

  # Grouped rather than one entry per Geoapify category: splitting Food into
  # restaurant, cafe and fast food would triple the menu on a 240x320 screen, and
  # the API takes a comma separated list in a single request anyway.
  CATEGORIES = {
    'petrol' => { categories: 'service.vehicle.fuel' },
    'food' => { categories: 'catering.restaurant,catering.fast_food,catering.cafe' },
    'shops' => { categories: 'commercial.supermarket,commercial.convenience' },
    'cash' => { categories: 'service.financial.atm,service.financial.bank' },
    'toilets' => { categories: 'amenity.toilet' },
    'pharmacy' => { categories: 'commercial.health_and_beauty.pharmacy' },
    'pub' => { categories: 'catering.pub,catering.bar' },
    'transport' => { categories: 'public_transport.train,public_transport.subway,' \
                                 'public_transport.bus,service.taxi' }
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
      lang: I18n.locale,
      categories: @kind[:categories],
      # Geoapify wants longitude first in these two, the reverse of every other
      # coordinate this app passes around.
      filter: "circle:#{@lon},#{@lat},#{RADIUS_METRES}",
      bias: "proximity:#{@lon},#{@lat}",
      limit: REQUEST_LIMIT
    }

    uri.query = URI.encode_www_form(params)
    uri
  end

  def get_places_from_geoapify_uri(uri)
    res = Net::HTTP.get_response(uri)
    unless res.is_a?(Net::HTTPSuccess)
      @error = I18n.t('places.unavailable')
      return []
    end

    body = JSON.parse(res.body)
    places = (body['features'] || []).filter_map { |feature| place_from(feature) }
    places = places.sort_by { |place| place[:distance] || Float::INFINITY }
    # Nearest first before the collapse, so a pair of stops either side of a road
    # leaves the one actually closest to the user.
    places.uniq { |place| place[:name].downcase }.first(MAX_RESULTS)
  end

  def place_from(feature)
    properties = feature['properties'] || {}
    name = place_name(properties)
    return nil if roadside_stop?(properties, name)

    {
      name: name,
      kind: kind_label(properties),
      distance: properties['distance'],
      lat: properties['lat'],
      lon: properties['lon']
    }
  end

  # Geoapify has one category covering both a bus station and every pole on the
  # kerb, and the poles are named after the road junction they stand on. Keeping
  # only the ones named as a station leaves somewhere you can actually travel from.
  def roadside_stop?(properties, name)
    (properties['categories'] || []).include?(BUS_CATEGORY) && !name.match?(STATION_NAME)
  end

  def kind_label(properties)
    categories = properties['categories'] || []
    match = KIND_KEYS.keys.find { |category| categories.include?(category) }

    match && I18n.t("places.kind.#{KIND_KEYS[match]}")
  end

  # OSM records are frequently unnamed, public toilets especially, so fall back to
  # whatever else would help someone recognise the place on the ground.
  def place_name(properties)
    properties['name'].presence ||
      properties['address_line1'].presence ||
      properties['street'].presence ||
      I18n.t('places.kind.unnamed')
  end
end
