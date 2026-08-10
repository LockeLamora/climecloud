require 'net/http'
require 'uri'

class Geocode
    # A keypad and a 240x320 screen make a long list useless, so only ever offer
    # the handful of places the user can realistically scroll through.
    MAX_CANDIDATES = 8

    def initialize(params)
      @key = Rails.application.credentials.google.api_key
      @address = params[:address]
      @country_code = params[:country_code]
    end

    def get_candidates
        return [] if @address.blank?

        uri = build_google_geocode_uri
        get_candidates_from_google_geocode_uri(uri)
    end

    private

    def build_google_geocode_uri
        uri = URI('https://maps.googleapis.com/maps/api/geocode/json')
        params = {
          key: @key,
          address: @address
        }
        params[:components] = "country:#{@country_code}" if @country_code.present?

        uri.query = URI.encode_www_form(params)
        uri
    end

    def get_candidates_from_google_geocode_uri(uri)
        res = Net::HTTP.get_response(uri)
        return [] unless res.is_a?(Net::HTTPSuccess)

        body = JSON.parse(res.body)
        return [] unless body['status'] == 'OK'

        body['results'].first(MAX_CANDIDATES).map do |result|
          {
            place_id: result['place_id'],
            address: result['formatted_address'],
            lat: result.dig('geometry', 'location', 'lat').to_s,
            lon: result.dig('geometry', 'location', 'lng').to_s,
            country_code: country_code_from(result)
          }
        end
    end

    # Saves a second lookup later on, and is more dependable than reverse geocoding
    # the coordinates we just derived.
    def country_code_from(result)
        component = (result['address_components'] || []).find do |candidate|
          candidate['types'].include?('country')
        end

        component && component['short_name'].to_s.downcase
    end
end
