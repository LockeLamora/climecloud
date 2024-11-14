require 'net/http'
require 'uri'

class Weather
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
        data = get_forecast_data_from_api(uri)
        return data
      end

    def get_forecast_data_from_api(uri)
        res = Net::HTTP.get_response(uri)
        JSON.parse(res.body) if res.is_a?(Net::HTTPSuccess)
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

