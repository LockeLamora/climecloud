class DirectionsController < ApplicationController
    def search
        render :search
    end

    def plan
        uri = build_google_maps_uri(params)
        get_routes_rom_google_maps_uri(uri)
        if cookies["show_map"] == '1'
            uri = build_google_map_static_image_api
            get_static_map_image(uri)
        end
        render :route
    end

    private

    def build_google_map_static_image_api
        uri = URI('https://maps.googleapis.com/maps/api/staticmap')
        params = {
             :key => Rails.application.credentials.google.api_key,
             :size => '220x220',
             :maptype => 'hybrid',
             :path => 'enc:' + @overview_polyline
            }
 
        uri.query = URI.encode_www_form(params)
        uri
        
    end

    def get_static_map_image(uri)
        image = Net::HTTP.get_response(uri).body
        @image = Base64.strict_encode64(image)
    end

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

        @steps = body["routes"][0]["legs"][0]["steps"]
        @overview_polyline = body["routes"][0]["overview_polyline"]["points"]
        @start = body["routes"][0]["legs"][0]["start_address"]
        @end = body["routes"][0]["legs"][0]["end_address"]
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
