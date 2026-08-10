require 'net/http'
require 'uri'

class Maps
    STATUS_MESSAGES = {
      'NOT_FOUND' => 'Could not find that place, please pick one below',
      'ZERO_RESULTS' => 'No route found, try another way of travelling',
      'OVER_QUERY_LIMIT' => 'Too many searches just now, please try again shortly',
      'REQUEST_DENIED' => 'Route planning is unavailable, please try again later',
      'INVALID_REQUEST' => 'Please fill in both From and To',
      'MAX_ROUTE_LENGTH_EXCEEDED' => 'That route is too long to plan'
    }.freeze

    UNAVAILABLE = 'Route planning is unavailable, please try again later'.freeze

    # unresolved lists the endpoints Google could not pin down, or matched only
    # loosely, so the user can be offered a list of places to pick from.
    attr_reader :error, :unresolved

    def initialize(params)
      @key = Rails.application.credentials.google.api_key
      @origin = params[:origin]
      @destination = params[:destination]
      @mode = params[:mode]
      @units = params[:units]
      @unresolved = []
    end

    def get_routes
        uri = build_google_maps_uri
        get_routes_from_google_maps_uri(uri)
    end

    def get_static_map_image_api(overview_polyline)
        url = build_google_map_static_image_api(overview_polyline)
        get_static_map_image(url)
    end

    def get_static_map_step_image_api(step)
        url = build_google_map_static_step_image_api(step)
        get_static_map_image(url)
    end

    private

    def build_google_map_static_step_image_api(step)
        uri = URI('https://maps.googleapis.com/maps/api/staticmap')
        params = {
          key: @key,
          size: '220x220',
          maptype: 'hybrid',
          markers: [
            "color:green|label:A|#{step['start_location']['lat']},#{step['start_location']['lng']}",
            "color:red|label:B|#{step['end_location']['lat']},#{step['end_location']['lng']}"
          ],
          path: "enc:#{step['polyline']['points']}"
        }

        uri.query = URI.encode_www_form(params)
        uri
    end

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
        unless res.is_a?(Net::HTTPSuccess)
          @error = UNAVAILABLE
          return
        end

        body = JSON.parse(res.body)
        unless body['status'] == 'OK'
          @error = STATUS_MESSAGES.fetch(body['status'], 'Could not plan route, please try again')
          @unresolved = unresolved_waypoints(body) if body['status'] == 'NOT_FOUND'
          return
        end

        @unresolved = partial_match_waypoints(body)
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

      # Google reports a failed lookup per endpoint. If it tells us nothing, assume
      # either could be at fault and let the user check both.
      def unresolved_waypoints(body)
        fields = waypoint_fields(body) { |waypoint| waypoint['geocoder_status'] != 'OK' }
        fields.empty? ? %w[origin destination] : fields
      end

      # A partial match means Google guessed, so the route may be to the wrong place.
      def partial_match_waypoints(body)
        waypoint_fields(body) { |waypoint| waypoint['partial_match'] }
      end

      def waypoint_fields(body)
        waypoints = body['geocoded_waypoints'] || []
        fields = []
        fields << 'origin' if waypoints[0] && yield(waypoints[0])
        fields << 'destination' if waypoints[1] && yield(waypoints[1])
        fields
      end
end