class ForecastController < ApplicationController

    def hourly
        if !cookies[:lat]
            redirect_to '/settings'
            return
        end

        get_data('hourly')

        render :hourly
    end

    private

    def get_data(period = 'hourly')
        uri = build_api_query(period)
        data = get_forecast_data_from_api(uri)
        parse_forecast_data(data)
    end

    def build_api_query(period = 'hourly')
        uri = URI('https://api.open-meteo.com/v1/forecast')
        
        params = {
             :latitude => cookies[:lat],
             :longitude => cookies[:lon],
             :timezone => cookies[:timezone_name]
            }

        params[period.to_sym] = %w(temperature_2m, apparent_temperature,precipitation_probability,snowfall,rain,wind_speed_10m) 

        period == 'hourly' ? forecast_days = 1 : forecast_days = 7
        params[:forecast_days] = forecast_days

        params.merge! get_metrics_units

        uri.query = URI.encode_www_form(params)
        puts uri

        uri
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

        return metrics
    end

    def get_forecast_data_from_api(uri)
        res = Net::HTTP.get_response(uri)
        puts res.body
        body = JSON.parse(res.body) if res.is_a?(Net::HTTPSuccess)
    end

    def parse_forecast_data(data)
        @times = data["hourly"]["time"]
        @temps = data["hourly"]["temperature_2m"]
        @feels_like = data["hourly"]["apparent_temperature"]
        @rain_prob = data["hourly"]["precipitation_probability"]
        @rain = data["hourly"]["rain"]
        @wind = data["hourly"]["wind_speed_10m"]
    end


    
end
