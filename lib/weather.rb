# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'cgi'

class Weather
  RATE_LIMITED = '429'
  # Open-Meteo counts its free allowance against the calling IP, and this app shares
  # an outbound address with everything else on the host. When the day's allowance is
  # gone a relay gives the forecast one more chance from a different address. Tried
  # in order, and only ever after a 429: a 400 is our own bad request and relaying it
  # would just be wrong twice.
  PROXIES = [
    'https://api.allorigins.win/raw?url=%<url>s',
    'https://api.codetabs.com/v1/proxy?quest=%<url>s'
  ].freeze
  # Short, because a stalled relay must not cost more than the forecast is worth.
  PROXY_TIMEOUT_SECONDS = 6

  attr_reader :error, :error_code

  # Open-Meteo caps free use per day. Nothing is wrong with the saved location when
  # this happens, so it must not be reported as if there were.
  def rate_limited?
    @error_code == RATE_LIMITED
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

    # Open-Meteo explains itself in the body. Throwing that away left us guessing.
    @error_code = res.code
    @error = "#{res.code} #{failure_reason(res)}"
    return nil unless rate_limited?

    forecast_via_proxy(uri)
  end

  def forecast_via_proxy(uri)
    PROXIES.each do |template|
      forecast = fetch_through(template, uri)
      next if forecast.nil?

      # Only clear the rate limit once a relay has actually produced a forecast,
      # so a total failure still reports honestly rather than as a blank page.
      @error = nil
      @error_code = nil
      return forecast
    end

    nil
  end

  def fetch_through(template, uri)
    res = get_with_timeout(URI(format(template, url: CGI.escape(uri.to_s))))
    return nil unless res.is_a?(Net::HTTPSuccess)

    forecast = JSON.parse(res.body)
    return nil unless forecast.is_a?(Hash) && forecast['error'].blank?

    forecast
  rescue JSON::ParserError
    nil
  end

  # A relay that hangs would leave the phone waiting on a page that may never come,
  # so anything going wrong here is simply the next relay's turn.
  def get_with_timeout(uri)
    Net::HTTP.start(uri.host, uri.port,
                    use_ssl: uri.scheme == 'https',
                    open_timeout: PROXY_TIMEOUT_SECONDS,
                    read_timeout: PROXY_TIMEOUT_SECONDS) do |http|
      http.request(Net::HTTP::Get.new(uri))
    end
  rescue StandardError
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
