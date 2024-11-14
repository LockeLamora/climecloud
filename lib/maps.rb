require 'net/http'
require 'uri'

class Maps
    def initialize(params)
      @key = Rails.application.credentials.google.api_key
      @origin = params[:origin]
      @destination = params[:destination]
      @mode = params[:mode]
      @units = params[:units]
    end

    def get_routes
        uri = build_google_maps_uri
        get_routes_from_google_maps_uri(uri)
    end

    def get_static_map_image_api(overview_polyline)
        url = build_google_map_static_image_api(overview_polyline)
        get_static_map_image(url)
    end

    def get_steps
        @steps
    end

    def get_overall_time
        @overall_time
    end

    def get_start
        @start
    end

    def get_end
        @end
    end

    private

    def build_google_map_static_image_api(overview_polyline)
        uri = URI('https://maps.googleapis.com/maps/api/staticmap')
        params = {
          key: Rails.application.credentials.google.api_key,
          size: '220x220',
          maptype: 'hybrid',
          path: "enc:#{overview_polyline}"
        }
    
        uri.query = URI.encode_www_form(params)
        uri
    end

    def get_static_map_image(uri)
        image = Net::HTTP.get_response(uri).body
        image = Base64.strict_encode64(image)
      end

    def build_google_maps_uri
        uri = URI('https://maps.googleapis.com/maps/api/directions/json')
        params = {
          key: @key,
          origin: @origin,
          destination: @destination,
          mode: @mode,
          units: @units
        }
    
        uri.query = URI.encode_www_form(params)
        uri
      end

      def get_routes_from_google_maps_uri(uri)
        res = Net::HTTP.get_response(uri)
        body = JSON.parse(res.body) if res.is_a?(Net::HTTPSuccess)
        if body['status'] == 'NOT_FOUND'
          @error = 'could not plan route, please provide more detail and try again'
          return
        end
        overview_polyline = extract_journey_overlay(body)
        start, endpart = extract_addresses(body)
        steps, overall_time = extract_steps(body)

        plan = {
          overview_polyline: overview_polyline,
          start: start,
          end: endpart,
          steps: steps,
          overall_time: overall_time
        }
      end

      def extract_steps(body)
        steps = body['routes'][0]['legs'][0]['steps']
        overall_time = body['routes'][0]['legs'][0]['duration']['text']
        return steps, overall_time
      end
    
      def extract_addresses(body)
        start = body['routes'][0]['legs'][0]['start_address']
        endpart = body['routes'][0]['legs'][0]['end_address']
        return start, endpart
      end
    
      def extract_journey_overlay(body)
        body['routes'][0]['overview_polyline']['points']
      end
end