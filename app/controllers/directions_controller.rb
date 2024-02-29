class DirectionsController < ApplicationController
    def search
        render :search
    end

    def plan
        uri = build_google_maps_uri(params)
        get_routes_rom_google_maps_uri(uri)
    end

    private

    def build_google_maps_uri(params)
        uri = URI('https://maps.googleapis.com/maps/api/directions/json')
        params = {
             :key => Rails.application.credentials.google.api_key,
             :origin => params[:origin],
             :destination => params[:destination],
             :mode => params[:mode],
             :units => resolve_unit
            }

        uri.query = URI.encode_www_form(params)
        uri
    end   

    def get_routes_rom_google_maps_uri(uri)
        res = Net::HTTP.get_response(uri)
        body = JSON.parse(res.body) if res.is_a?(Net::HTTPSuccess)
        puts res.body
    end

    def resolve_unit
        case cookies[:metris]
        when 'imperial'
            return 'imperial'
        when 'metric'
            return 'metric'
        when 'hybrid'
            return 'imperial'
        end
    end

end
