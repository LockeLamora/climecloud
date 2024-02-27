require 'uri'
require 'net/http'
require 'json'

class SettingsController < ApplicationController
    def set 
        uri = build_api_query(params)
        get_parameters_from_api(uri)
        set_metrics(params)
        set_cookie

        redirect_to '/forecast/hourly'
    end

    def change
        render :set
    end


    private

    def set_metrics(params)
        @metrics = params[:metrics]
    end

    def set_cookie
        cookies.permanent[:lat] = @lat
        cookies.permanent[:lon] = @lon
        cookies.permanent[:city] = @city
        cookies.permanent[:state] = @state
        cookies.permanent[:timezone_name] = @timezone_name
        cookies.permanent[:metrics] = @metrics
    end

    def get_parameters_from_api(uri)
        res = Net::HTTP.get_response(uri)
        body = JSON.parse(res.body) if res.is_a?(Net::HTTPSuccess)

        @lat = body["features"][0]["properties"]["lat"].to_s
        @lon = body["features"][0]["properties"]["lon"].to_s
        @city = body["features"][0]["properties"]["city"]
        @state = body["features"][0]["properties"]["state"]
        @timezone_name = body["features"][0]["properties"]["timezone"]["name"] 
    end

    def build_api_query(params)
        uri = URI('https://api.geoapify.com/v1/geocode/search')
        
        params = {
             :api_key => Rails.application.credentials.geoapify.api_key,
             :postcode => params[:postcode],
             :country => params[:country_code] 
            }

        uri.query = URI.encode_www_form(params)

        uri
    end
end
