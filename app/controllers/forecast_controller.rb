# frozen_string_literal: true

require 'uri'
require 'net/http'
require 'json'
require 'weather'

class ForecastController < ApplicationController
  def hourly
    unless cookies[:lat]
      redirect_to '/settings'
      return
    end

    data = weather.get_forecast('hourly')
    parse_forecast_data(data, 'hourly')

    render :hourly
  end

  def daily
    unless cookies[:lat]
      redirect_to '/settings'
      return
    end

    data = weather.get_forecast('daily')
    parse_forecast_data(data, 'daily')

    render :daily
  end

  private

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

  def parse_forecast_data(data, period)
    if period == 'hourly'
      @times = data[period]['time']
      @temps = data[period]['temperature_2m']
      @feels_like = data[period]['apparent_temperature']
      @rain_prob = data[period]['precipitation_probability']
      @rain = data[period]['rain']
      @wind = data[period]['wind_speed_10m']
      @snow = data[period]['snowfall']

      @units = {}
      @units[:rain] = data["#{period}_units"]['rain']
      @units[:temp] = data["#{period}_units"]['temperature_2m']
      @units[:wind] = data["#{period}_units"]['wind_speed_10m'].gsub('/', '')
      @units[:snowfall] = data["#{period}_units"]['snowfall']
    elsif period == 'daily'
      @times = data[period]['time']
      @temps_max = data[period]['temperature_2m_max']
      @temps_min = data[period]['temperature_2m_min']
      @rain_prob = data[period]['precipitation_probability_mean']
      @rain = data[period]['rain_sum']
      @wind_max = data[period]['wind_speed_10m_max']
      @wind_min = data[period]['wind_speed_10m_min']
      @snow = data[period]['snowfall_sum']

      @units = {}
      @units[:rain] = data["#{period}_units"]['rain_sum']
      @units[:temp] = data["#{period}_units"]['temperature_2m_max']
      @units[:wind] = data["#{period}_units"]['wind_speed_10m_max'].gsub('/', '')
      @units[:snowfall] = data["#{period}_units"]['snowfall_sum']
    end
  end

  def weather 
    @weather ||= Weather.new({
      latitude: cookies[:lat],
      longitude: cookies[:lon],
      timezone: cookies[:timezone_name],
      metrics_units: get_metrics_units
    }) 
  end
end
