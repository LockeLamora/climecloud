# frozen_string_literal: true

require 'net/http'
require 'uri'

class Geocode
  # A keypad and a 240x320 screen make a long list useless, so only ever offer
  # the handful of places the user can realistically scroll through.
  MAX_CANDIDATES = 8

  def initialize(params)
    @key = Rails.application.credentials.geoapify.api_key
    @address = params[:address]
    @country_code = params[:country_code]
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
      limit: MAX_CANDIDATES
    }
    params[:filter] = "countrycode:#{@country_code.downcase}" if @country_code.present?

    uri.query = URI.encode_www_form(params)
    uri
  end

  def get_candidates_from_geoapify_uri(uri)
    res = Net::HTTP.get_response(uri)
    return [] unless res.is_a?(Net::HTTPSuccess)

    body = JSON.parse(res.body)
    (body['features'] || []).filter_map { |feature| candidate_from(feature) }
  end

  def candidate_from(feature)
    properties = feature['properties'] || {}
    return nil if properties['formatted'].blank?

    {
      address: properties['formatted'],
      lat: properties['lat'].to_s,
      lon: properties['lon'].to_s,
      country_code: properties['country_code'].to_s.downcase.presence
    }
  end
end
