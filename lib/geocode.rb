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

  def initialize(params)
    @key = Rails.application.credentials.geoapify.api_key
    @address = params[:address]
    @country_code = params[:country_code]
    @type = params[:type]
    @bias_lat = params[:bias_lat]
    @bias_lon = params[:bias_lon]
  end

  def get_candidates
    return [] if @address.blank?

    uri = build_geoapify_autocomplete_uri
    get_candidates_from_geoapify_uri(uri)
  end

  private

  # Autocomplete rather than geocoding, because geocoding resolves instead of
  # searching: "station road" came back as a single best guess, so the ambiguity
  # the user needed to resolve was never offered to them.
  def build_geoapify_autocomplete_uri
    uri = URI('https://api.geoapify.com/v1/geocode/autocomplete')
    params = {
      apiKey: @key,
      text: @address,
      limit: REQUEST_LIMIT
    }
    params[:filter] = "countrycode:#{@country_code.downcase}" if @country_code.present?
    # Autocomplete is deliberately fuzzy, which is what free text search wants but not
    # a postcode box: without this, "abcdefg" happily comes back as Bristol.
    params[:type] = @type if @type.present?
    # Rank matches near the other end of the journey first. A Station Road two
    # hundred miles away is never the one that was meant. Longitude first again.
    params[:bias] = "proximity:#{@bias_lon},#{@bias_lat}" if @bias_lat.present? && @bias_lon.present?

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
    return candidates unless @bias_lat.present? && @bias_lon.present?

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

  # Searching "station road" returns individual house numbers, so the list came back
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
