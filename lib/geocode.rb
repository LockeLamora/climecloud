# frozen_string_literal: true

require 'net/http'
require 'uri'

class Geocode
  # A keypad and a 240x320 screen make a long list useless, so only ever offer
  # the handful of places the user can realistically scroll through.
  MAX_CANDIDATES = 8
  # Ask for more than we show, because several house numbers on one street collapse
  # into a single entry and would otherwise leave almost nothing to choose from.
  REQUEST_LIMIT = 20
  # Wide enough to cover the next town or two on foot or by car, tight enough that a
  # street in the neighbouring village outranks eight of the same name a county away.
  NEARBY_RADIUS_METRES = 30_000

  def initialize(params)
    @key = Rails.application.credentials.geoapify.api_key
    @address = params[:address]
    @country_code = params[:country_code]
    @type = params[:type]
    @bias_lat = params[:bias_lat]
    @bias_lon = params[:bias_lon]
  end

  # Search the immediate area first. Sorting the response is not enough on its own:
  # the API ranks by text relevance and returns a capped list, so the match two miles
  # away can be absent entirely while eight of the same name a county away are not.
  # Widen only when the tight search finds nothing, so distant places stay reachable.
  def get_candidates
    return [] if @address.blank?

    nearby = biased? ? request_candidates(nearby_filter) : []
    return nearby if nearby.any?

    request_candidates(country_filter)
  end

  private

  def biased?
    @bias_lat.present? && @bias_lon.present?
  end

  # Longitude first, as everywhere in the Geoapify API.
  def nearby_filter
    "circle:#{@bias_lon},#{@bias_lat},#{NEARBY_RADIUS_METRES}"
  end

  def country_filter
    return nil if @country_code.blank?

    "countrycode:#{@country_code.downcase}"
  end

  def request_candidates(filter)
    get_candidates_from_geoapify_uri(build_geoapify_autocomplete_uri(filter))
  end

  # Autocomplete rather than geocoding, because geocoding resolves instead of
  # searching: a generic street name came back as a single best guess, so the
  # ambiguity the user needed to resolve was never offered to them.
  def build_geoapify_autocomplete_uri(filter)
    uri = URI('https://api.geoapify.com/v1/geocode/autocomplete')
    params = {
      apiKey: @key,
      text: @address,
      limit: REQUEST_LIMIT
    }
    params[:filter] = filter if filter.present?
    # Autocomplete is deliberately fuzzy, which is what free text search wants but
    # not a postcode box: without this, "abcdefg" happily comes back as a real city.
    params[:type] = @type if @type.present?
    params[:bias] = "proximity:#{@bias_lon},#{@bias_lat}" if biased?

    uri.query = URI.encode_www_form(params)
    uri
  end

  def get_candidates_from_geoapify_uri(uri)
    res = Net::HTTP.get_response(uri)
    return [] unless res.is_a?(Net::HTTPSuccess)

    body = JSON.parse(res.body)
    candidates = (body['features'] || []).filter_map { |feature| candidate_from(feature) }
    candidates = candidates.uniq { |candidate| candidate[:address].downcase }
    nearest_first(candidates).first(MAX_CANDIDATES)
  end

  # Geoapify ranks by text relevance, which scatters a search for "bus station" the
  # length of the country. Sort by distance before the list is cut down, or the
  # far away matches fill it up before the nearby one is ever reached.
  def nearest_first(candidates)
    return candidates unless biased?

    candidates.sort_by { |candidate| distance_from_bias(candidate) }
  end

  # Equirectangular approximation. Only the ordering matters, not the true distance.
  def distance_from_bias(candidate)
    delta_lat = candidate[:lat].to_f - @bias_lat.to_f
    delta_lon = (candidate[:lon].to_f - @bias_lon.to_f) *
                Math.cos(@bias_lat.to_f * Math::PI / 180)

    (delta_lat * delta_lat) + (delta_lon * delta_lon)
  end

  def candidate_from(feature)
    properties = feature['properties'] || {}
    address = street_level_name(properties)
    return nil if address.blank?

    {
      address: address,
      lat: properties['lat'].to_s,
      lon: properties['lon'].to_s,
      country_code: properties['country_code'].to_s.downcase.presence
    }
  end

  # Searching a street name returns individual house numbers, so the list came back
  # as four doors on the same street rather than four different streets. Drop the
  # building and name the street, which then dedupes down to one entry per street.
  def street_level_name(properties)
    street = properties['street']
    return properties['formatted'] if street.blank?

    area = properties['city'].presence ||
           properties['suburb'].presence ||
           properties['county'].presence ||
           properties['postcode'].presence

    [street, area].compact.join(', ')
  end
end
