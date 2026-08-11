# frozen_string_literal: true

require 'uri'
require 'net/http'
require 'json'
require 'geocode'
require 'languages'

class SettingsController < ApplicationController
  def set
    if params[:lat].present? && params[:lon].present?
      @lat = params[:lat]
      @lon = params[:lon]
      @country_code = params[:place_country]
      @place = params[:place]
      save_location
      return
    end

    candidates = geocode_postcode

    if candidates.empty?
      @error = I18n.t('settings.not_determined')
      render :set
      return
    end

    chosen = candidates.first
    @lat = chosen[:lat]
    @lon = chosen[:lon]
    @country_code = chosen[:country_code]
    @place = chosen[:address]

    save_location(alternatives: candidates.length - 1)
  end

  def change
    render :set
  end

  def language
    cookies.permanent[:locale] = params[:locale] if Languages.supported?(params[:locale])
    redirect_to root_path
  end

  # Only reached when the assumed place was wrong, so show what else matched.
  def pick
    @settings_params = settings_params
    @candidates = geocode_postcode.drop(1)

    if @candidates.empty?
      @error = I18n.t('settings.no_others')
      render :set
      return
    end

    render :pick
  end

  private

  def geocode_postcode
    Geocode.new({
                  address: params[:postcode],
                  country_code: params[:country_code],
                  type: 'postcode'
                }).get_candidates
  end

  # A postcode or town can match several places. Take the first so the common case
  # stays a single keypress, and only offer the rest when the user says it is wrong.
  def save_location(alternatives: 0)
    lookup_locale
    set_metrics(params)
    set_show_map(params)
    set_news(params)
    set_cookie

    # Always confirm. Redirecting straight to the menu gave no sign the postcode had
    # matched anything at all until the weather page was opened.
    @alternatives = alternatives
    @settings_params = settings_params
    # Offered here rather than on the form, because the country is only known once
    # the location has actually resolved.
    @languages = Languages.for_country(resolve_country_code)
    render :saved
  end

  def settings_params
    params.permit(:postcode, :country_code, :metrics, :mapimages, :news_default_section).to_h
  end

  # City, county and timezone are presentation extras. If the lookup fails we still
  # have coordinates, so save what we have rather than losing the whole location.
  def lookup_locale
    uri = build_geoapify_api_query
    get_parameters_from_geoapify_api(uri)
  end

  def set_metrics(params)
    @metrics = params[:metrics]
  end

  def set_show_map(params)
    @show_map = params[:mapimages]
  end

  def set_news(params)
    @news_default_section = params[:news_default_section]
  end

  def set_cookie
    cookies.permanent[:lat] = @lat
    cookies.permanent[:lon] = @lon
    cookies.permanent[:city] = @city.presence || @place.presence || params[:postcode]
    cookies.permanent[:state] = @state
    cookies.permanent[:timezone_name] = @timezone_name.presence || 'auto'
    cookies.permanent[:metrics] = @metrics
    cookies.permanent[:country_code] = resolve_country_code
    cookies.permanent[:show_map] = @show_map
    cookies.permanent[:news_default_section] = @news_default_section
  end

  # The country picked on the form is more dependable than a reverse lookup, and
  # the news feed needs it to choose an edition.
  def resolve_country_code
    (@country_code.presence || params[:country_code]).to_s.downcase.presence
  end

  def get_parameters_from_geoapify_api(uri)
    properties = fetch_geoapify_properties(uri)

    @city = properties['city']
    @state = properties['state']
    @timezone_name = properties.dig('timezone', 'name')
    @country_code = properties['country_code'].presence || @country_code
  end

  def fetch_geoapify_properties(uri)
    res = Net::HTTP.get_response(uri)
    return {} unless res.is_a?(Net::HTTPSuccess)

    body = JSON.parse(res.body)
    body.dig('features', 0, 'properties') || {}
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
