# frozen_string_literal: true

require 'uri'
require 'net/http'
require 'json'

class ForecastController < ApplicationController
  def hourly
    unless cookies[:lat]
      redirect_to '/settings'
      return
    end

    get_data('hourly')

    render :hourly
  end

  def daily
    unless cookies[:lat]
      redirect_to '/settings'
      return
    end

    get_data('daily')

    render :daily
  end

  private

  def get_data(period = 'hourly')
    uri = build_api_query(period)
    data = get_forecast_data_from_api(uri)
    parse_forecast_data(data, period)
  end

  def build_api_query(period = 'hourly')
    uri = URI('https://api.open-meteo.com/v1/forecast')

    params = get_params_by_locale

    params[period.to_sym] = get_params_by_period(period)
    period == 'hourly' ? params[:forecast_hours] = 24 : params[:forecast_days] = 7

    params.merge! get_metrics_units

    uri.query = URI.encode_www_form(params)
    uri
  end

  def get_params_by_locale
    {
      latitude: cookies[:lat],
      longitude: cookies[:lon],
      timezone: cookies[:timezone_name]
    }
  end

  def get_params_by_period(period)
    if period == 'hourly'
      %w[temperature_2m,apparent_temperature,precipitation_probability,snowfall,rain,wind_speed_10m]
    elsif period == 'daily'
      %w[temperature_2m_max temperature_2m_min
         precipitation_probability_mean snowfall_sum rain_sum wind_speed_10m_max wind_speed_10m_min]
    end
  end

  def get_metrics_units
    metrics = {}
    case cookies[:metrics]
    when 'hybrid'
      metrics[:wind_speed_unit] = 'mph'
      metrics[:temperature_unit] = 'celsius'
      metrics[:precipitation_unit] = 'mm'
    when 'imperial'
      metrics[:wind_speed_unit] = 'mph'
      metrics[:temperature_unit] = 'fahrenheit'
      metrics[:precipitation_unit] = 'inch'
    when 'metric'
      metrics[:wind_speed_unit] = 'kph'
      metrics[:temperature_unit] = 'celsius'
      metrics[:precipitation_unit] = 'mm'
    end

    metrics
  end

  def get_forecast_data_from_api(uri)
    res = Net::HTTP.get_response(uri)
    JSON.parse(res.body) if res.is_a?(Net::HTTPSuccess)
  end

  def parse_forecast_data(data, period)
    if period == 'hourly'
      @times = data[period]['time']
      @temps = data[period]['temperature_2m']
      @feels_like = data[period]['apparent_temperature']
      @rain_prob = data[period]['precipitation_probability']
      @rain = data[period]['rain']
      @wind = data[period]['wind_speed_10m']

      @units = {}
      @units[:rain] = data["#{period}_units"]['rain']
      @units[:temp] = data["#{period}_units"]['temperature_2m']
      @units[:wind] = data["#{period}_units"]['wind_speed_10m'].gsub('/', '')
    elsif period == 'daily'
      @times = data[period]['time']
      @temps_max = data[period]['temperature_2m_max']
      @temps_min = data[period]['temperature_2m_min']
      @rain_prob = data[period]['precipitation_probability_mean']
      @rain = data[period]['rain_sum']
      @wind_max = data[period]['wind_speed_10m_max']
      @wind_min = data[period]['wind_speed_10m_min']

      @units = {}
      @units[:rain] = data["#{period}_units"]['rain_sum']
      @units[:temp] = data["#{period}_units"]['temperature_2m_max']
      @units[:wind] = data["#{period}_units"]['wind_speed_10m_max'].gsub('/', '')
    end
  end
end
