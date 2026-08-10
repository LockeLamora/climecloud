module PlacesHelper
  METRES_PER_MILE = 1609.34
  METRES_PER_YARD = 0.9144

  # Geoapify answers in metres whatever the user's preference, and "1.2km" is no use
  # to somebody who set the dashboard to imperial.
  def place_distance(metres)
    return nil if metres.nil?

    cookies['metrics'] == 'imperial' ? imperial_distance(metres) : metric_distance(metres)
  end

  private

  def metric_distance(metres)
    return "#{metres.round}m" if metres < 1000

    "#{(metres / 1000.0).round(1)}km"
  end

  def imperial_distance(metres)
    yards = metres / METRES_PER_YARD
    return "#{yards.round}yd" if yards < 880

    "#{(metres / METRES_PER_MILE).round(1)}mi"
  end
end
