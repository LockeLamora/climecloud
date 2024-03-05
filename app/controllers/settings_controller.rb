# frozen_string_literal: true

require 'uri'
require 'net/http'
require 'json'

class SettingsController < ApplicationController
  def set
    uri = build_google_geocode_uri(params)
    get_parameters_from_google_geocode_api(uri)
    unless @error.nil?
      render :set
      return
    end

    uri = build_geoapify_api_query
    get_parameters_from_geoapify_api(uri)
    set_metrics(params)
    set_show_map(params)
    set_cookie

    redirect_to '/'
  end

  def change
    render :set
  end

  private

  def build_google_geocode_uri(params)
    uri = URI('https://maps.googleapis.com/maps/api/geocode/json')

    params = {
      key: Rails.application.credentials.google.api_key,
      components: ["postal_code:#{params[:postcode]}",
                   "country:#{params[:country_code]}"]
    }

    uri.query = URI.encode_www_form(params)
    uri
  end

  def get_parameters_from_google_geocode_api(uri)
    res = Net::HTTP.get_response(uri)
    body = JSON.parse(res.body) if res.is_a?(Net::HTTPSuccess)
    if body['status'] == 'ZERO_RESULTS'
      @error = 'Could not determine location, please try again'
      return
    end
    @lat = body['results'][0]['geometry']['location']['lat'].to_s
    @lon = body['results'][0]['geometry']['location']['lng'].to_s
  end

  def set_metrics(params)
    @metrics = params[:metrics]
  end

  def set_show_map(params)
    @show_map = params[:mapimages]
  end

  def set_cookie
    cookies.permanent[:lat] = @lat
    cookies.permanent[:lon] = @lon
    cookies.permanent[:city] = @city
    cookies.permanent[:state] = @state
    cookies.permanent[:timezone_name] = @timezone_name
    cookies.permanent[:metrics] = @metrics
    cookies.permanent[:country_code] = @country_code
    cookies.permanent[:show_map] = @show_map
  end

  def get_parameters_from_geoapify_api(uri)
    res = Net::HTTP.get_response(uri)
    body = JSON.parse(res.body) if res.is_a?(Net::HTTPSuccess)

    @city = body['features'][0]['properties']['city']
    @state = body['features'][0]['properties']['state']
    @timezone_name = body['features'][0]['properties']['timezone']['name']
    @country_code = body['features'][0]['properties']['country_code']
  end

  def build_geoapify_api_query
    uri = URI('https://api.geoapify.com/v1/geocode/reverse')

    api_params = {
      api_key: Rails.application.credentials.geoapify.api_key,
      lat: @lat,
      lon: @lon
    }

    uri.query = URI.encode_www_form(api_params)
    uri
  end
end
