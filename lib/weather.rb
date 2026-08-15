# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'cgi'

class Weather
  attr_reader :error, :error_code

  # Open-Meteo caps free use per day. Nothing is wrong with the saved location when
  # this happens, so it must not be reported as if there were.
  def rate_limited?
    @error_code == Relay::RATE_LIMITED
  end

  def initialize(params)
    @latitude = params[:latitude]
    @longitude = params[:longitude]
    @timezone = params[:timezone]
    @metrics_units = params[:metrics_units]
  end

  def get_forecast(period = 'hourly')
    get_data(period)
  end

  private

  def get_data(period = 'hourly')
    uri = build_api_query(period)
    get_forecast_data_from_api(uri)
  end

  def get_forecast_data_from_api(uri)
    res = Net::HTTP.get_response(uri)
    return JSON.parse(res.body) if res.is_a?(Net::HTTPSuccess)

    # Open-Meteo explains itself in the body, so the reason is kept alongside the code.
    @error_code = res.code
    @error = "#{res.code} #{failure_reason(res)}"
    # Logged before the relays are reached, so the log reads as the whole path taken: what
    # open-meteo said, which relay was tried, and how each answered.
    Rails.logger.warn("Forecast refused by open-meteo - #{@error}")
    return nil unless rate_limited?

    forecast_via_proxy(uri)
  end

  def forecast_via_proxy(uri)
    forecast = Relay.fetch(uri, subject: 'Forecast') { |body| forecast_in(body) }
    return nil if forecast.nil?

    # Only clear the rate limit once a relay has actually produced a forecast, so a total
    # failure still reports honestly rather than as a blank page.
    @error = nil
    @error_code = nil
    forecast
  end

  # A relay reports its own success rather than open-meteo's, so a 200 from one proves
  # nothing: the body still has to be a forecast.
  def forecast_in(body)
    forecast = JSON.parse(body)
    return nil unless forecast.is_a?(Hash) && forecast['error'].blank?

    forecast
  rescue JSON::ParserError
    nil
  end

  def failure_reason(res)
    JSON.parse(res.body.to_s)['reason']
  rescue JSON::ParserError
    res.body.to_s[0, 200]
  end

  def get_params_by_period(period)
    if period == 'hourly'
      %w[temperature_2m,apparent_temperature,precipitation_probability,snowfall,rain,wind_speed_10m]
    elsif period == 'daily'
      %w[temperature_2m_max temperature_2m_min
         precipitation_probability_mean snowfall_sum rain_sum wind_speed_10m_max wind_speed_10m_min]
    end
  end

  def build_api_query(period = 'hourly')
    uri = URI('https://api.open-meteo.com/v1/forecast')

    params = {
      latitude: @latitude,
      longitude: @longitude,
      timezone: @timezone
    }

    params[period.to_sym] = get_params_by_period(period)
    period == 'hourly' ? params[:forecast_hours] = 24 : params[:forecast_days] = 7

    params.merge! @metrics_units

    uri.query = URI.encode_www_form(params)
    uri
  end
end
