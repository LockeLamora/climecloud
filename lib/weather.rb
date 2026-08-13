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
  #
  # Ordered by what answers most reliably. A relay that is down today may be up next
  # month, so a dead one stays on the list; the timeout and budget below are what keep it
  # from costing the reader anything much. Every attempt is logged, so a relay that has
  # stopped answering is visible rather than silently absorbed.
  #
  # Not every relay takes its target the same way: one wants it in the path unescaped,
  # the others want it escaped in a query string, and the first needs a header or it
  # returns the page dressed up for a language model rather than the JSON we asked for.
  PROXIES = [
    { template: 'https://r.jina.ai/%<url>s',
      escape: false,
      headers: { 'x-return-format' => 'text' } },
    { template: 'https://api.allorigins.win/raw?url=%<url>s', escape: true, headers: {} },
    { template: 'https://api.codetabs.com/v1/proxy?quest=%<url>s', escape: true, headers: {} }
  ].freeze
  # Short, because a stalled relay must not cost more than the forecast is worth.
  PROXY_TIMEOUT_SECONDS = 4
  # A ceiling across all of them together, so adding a relay to the list does not add
  # another timeout to the wait before the busy message appears.
  PROXY_BUDGET_SECONDS = 10

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
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + PROXY_BUDGET_SECONDS

    PROXIES.each do |proxy|
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        Rails.logger.warn('Forecast relays gave up - budget spent')
        break
      end

      forecast = fetch_through(proxy, uri)
      next if forecast.nil?

      # Only clear the rate limit once a relay has actually produced a forecast,
      # so a total failure still reports honestly rather than as a blank page.
      @error = nil
      @error_code = nil
      return forecast
    end

    # The reader is about to be told the service is busy, so the log records that every
    # relay was spent, and that message is not mistaken for open-meteo alone.
    Rails.logger.warn("Forecast unavailable - #{PROXIES.length} relays tried, none answered")
    nil
  end

  # Logged either way. A relay is somebody else's free service and will eventually stop
  # answering, and the line here names which one, so a relay failure is not read as
  # open-meteo being busy.
  def fetch_through(proxy, uri)
    res = get_with_timeout(proxy_uri(proxy, uri), proxy[:headers])
    # Nothing came back at all, and the rescue that caught it has already said why.
    return nil if res.nil?
    return relay_failed(proxy, "response #{res.code}") unless res.is_a?(Net::HTTPSuccess)

    forecast = JSON.parse(res.body)
    return relay_failed(proxy, 'no forecast in the body') unless forecast.is_a?(Hash) && forecast['error'].blank?

    Rails.logger.info("Forecast relayed by #{relay_host(proxy)}")
    forecast
  rescue JSON::ParserError
    relay_failed(proxy, 'body was not JSON')
  end

  def proxy_uri(proxy, uri)
    target = proxy[:escape] ? CGI.escape(uri.to_s) : uri.to_s

    URI(format(proxy[:template], url: target))
  end

  def relay_failed(proxy, reason)
    Rails.logger.warn("Forecast relay #{relay_host(proxy)} failed - #{reason}")
    nil
  end

  def relay_host(proxy)
    URI(format(proxy[:template], url: '')).host
  end

  # A relay that hangs would leave the phone waiting on a page that may never come,
  # so anything going wrong here is simply the next relay's turn.
  def get_with_timeout(uri, headers = {})
    Net::HTTP.start(uri.host, uri.port,
                    use_ssl: uri.scheme == 'https',
                    open_timeout: PROXY_TIMEOUT_SECONDS,
                    read_timeout: PROXY_TIMEOUT_SECONDS) do |http|
      http.request(Net::HTTP::Get.new(uri, headers))
    end
  rescue StandardError => e
    Rails.logger.warn("Forecast relay #{uri.host} unreachable - #{e.class}")
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
