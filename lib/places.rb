# frozen_string_literal: true

require 'net/http'
require 'uri'

class Places
  RADIUS_METRES = 5000
  # Everything else worth walking to is close by. A hospital is not: the nearest one can
  # be the far side of a county, and looking five kilometres out found nothing at all.
  HOSPITAL_RADIUS_METRES = 30_000
  MAX_RESULTS = 10
  # Surgeries outnumber hospitals in any town, so sorting the two together by distance
  # buried the nearest hospital at twelfth and off the end of the list. These places are
  # kept whatever their distance, and the rest of the list fills up around them.
  GUARANTEED_RESULTS = 3
  # Ask for more than we show, because stops on opposite sides of the same road come
  # back as separate records under one name and collapse into a single entry.
  REQUEST_LIMIT = 20
  # Surgeries are dense enough in a city to fill an ordinary request on their own, which
  # leaves no hospital in the pool to hold back. Asking for more costs the same request.
  WIDE_REQUEST_LIMIT = 60
  BUS_CATEGORY = 'public_transport.bus'
  STATION_NAME = /station|interchange|bus stn/i
  # Most car parks within a mile of a city centre are somebody's private spaces. They
  # are somewhere you would be towed from rather than somewhere to park, so they are no
  # use in a list of places to leave a car.
  PRIVATE_ACCESS = 'private'
  # A rooftop deck is the top of a multi-storey as far as anyone parking is concerned.
  PARKING_TYPE_KEYS = {
    'surface' => 'surface',
    'multi-storey' => 'multistorey',
    'rooftop' => 'multistorey',
    'underground' => 'underground'
  }.freeze

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
    'amenity.toilet' => 'toilet',
    'parking.cars' => 'parking',
    'healthcare.hospital' => 'hospital',
    'healthcare.clinic_or_praxis' => 'doctor',
    'commercial.department_store' => 'department_store',
    'commercial.shopping_mall' => 'shopping_centre'
  }.freeze

  # Grouped rather than one entry per Geoapify category: splitting Food into
  # restaurant, cafe and fast food would triple the menu on a 240x320 screen, and
  # the API takes a comma separated list in a single request anyway.
  # Ordered by how urgently each one is usually wanted, because the first eight are the
  # ones reachable with a single keypress. A toilet or a doctor is needed now; petrol and
  # a cash machine are things you go looking for, and they sit on the second page.
  CATEGORIES = {
    # Not only public toilets. A child who needs to go does not care whether it is a
    # supermarket, a filling station or a park, so this asks for everywhere you could
    # reasonably walk into and be pointed at one, nearest first with what each place is
    # written underneath. OpenStreetMap almost never records that a venue has a toilet
    # (two pubs in twenty nine), so no source can filter on it and the honest thing is
    # to offer the places where asking works rather than pretend to know.
    'toilets' => { categories: 'amenity.toilet,commercial.supermarket,service.vehicle.fuel,' \
                               'catering.fast_food,catering.cafe,catering.pub,' \
                               'commercial.department_store,commercial.shopping_mall,' \
                               'public_transport.train' },
    # Not the bare healthcare category, which brings back dentists and opticians rather
    # than somewhere to be seen about something wrong.
    'hospital' => { categories: 'healthcare.hospital,healthcare.clinic_or_praxis',
                    radius: HOSPITAL_RADIUS_METRES, guarantee: 'healthcare.hospital',
                    request_limit: WIDE_REQUEST_LIMIT },
    'pharmacy' => { categories: 'commercial.health_and_beauty.pharmacy' },
    'food' => { categories: 'catering.restaurant,catering.fast_food,catering.cafe' },
    'shops' => { categories: 'commercial.supermarket,commercial.convenience' },
    'pub' => { categories: 'catering.pub,catering.bar' },
    'transport' => { categories: 'public_transport.train,public_transport.subway,' \
                                 'public_transport.bus,service.taxi' },
    'parking' => { categories: 'parking' },
    'petrol' => { categories: 'service.vehicle.fuel' },
    'cash' => { categories: 'service.financial.atm,service.financial.bank' }
  }.freeze
  # Eight fit a small screen with a digit each, and the ninth onwards are a page away.
  PAGE_SIZE = 8

  attr_reader :error

  # How far this category looked, so a page reporting nothing found says the distance it
  # actually searched rather than the default everything else uses.
  def radius
    (@kind && @kind[:radius]) || RADIUS_METRES
  end

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
      filter: "circle:#{@lon},#{@lat},#{radius}",
      bias: "proximity:#{@lon},#{@lat}",
      limit: @kind[:request_limit] || REQUEST_LIMIT
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
    # Nearest first before the collapse, so a pair of entries either side of a road leaves
    # the one actually closest.
    keeping_guaranteed(places.uniq { |place| place[:name].downcase })
  end

  # Hold places back from the cap when the category says they must survive it, then let
  # the nearest of everything else fill the remaining room. Displayed in distance order
  # either way, so a hospital twenty kilometres out reads as exactly that.
  def keeping_guaranteed(places)
    wanted = @kind[:guarantee]
    return places.first(MAX_RESULTS) if wanted.nil?

    kept = places.select { |place| place[:categories].include?(wanted) }.first(GUARANTEED_RESULTS)
    others = (places - kept).first(MAX_RESULTS - kept.length)

    (kept + others).sort_by { |place| place[:distance] || Float::INFINITY }
  end

  def place_from(feature)
    properties = feature['properties'] || {}
    name = place_name(properties)
    return nil if roadside_stop?(properties, name) || private_parking?(properties)

    {
      name: name,
      kind: kind_label(properties),
      distance: properties['distance'],
      lat: properties['lat'],
      lon: properties['lon'],
      hours: properties['opening_hours'].presence,
      notes: parking_notes(properties) + toilet_notes(properties),
      categories: properties['categories'] || []
    }
  end

  # Whether there is somewhere to change a baby, which is often the whole reason for
  # looking one up in a hurry. Six of fifteen public toilets in a city centre say so.
  #
  # Nothing about a charge, deliberately: the data carries a "no_fee" marker whose
  # meaning cannot be pinned down from the responses, and telling a parent a toilet is
  # free when it wants thirty pence at the barrier is worse than saying nothing.
  def toilet_notes(properties)
    return [] unless (properties['facilities'] || {})['changing_table']

    [I18n.t('places.changing_table')]
  end

  def private_parking?(properties)
    (properties['parking'] || {})['access'] == PRIVATE_ACCESS
  end

  # What someone deciding where to leave a car wants to know before walking to it. Silence
  # rather than a guess when a field is missing: most car parks say nothing about a charge,
  # and an absent fee is not a free one. Saying nothing sends someone to read the sign.
  def parking_notes(properties)
    parking = properties['parking'] || {}
    return [] if parking.empty?

    [
      PARKING_TYPE_KEYS[parking['type']],
      charge_key(parking),
      parking['park_and_ride'] ? 'park_and_ride' : nil
    ].compact.map { |key| I18n.t("places.parking.#{key}") }
  end

  def charge_key(parking)
    return nil if parking['fee'].nil?

    parking['fee'] ? 'paid' : 'free'
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
