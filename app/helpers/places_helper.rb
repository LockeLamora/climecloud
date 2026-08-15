module PlacesHelper
  METRES_PER_MILE = 1609.34
  METRES_PER_YARD = 0.9144

  # Opening times, with every clock time in a wrapper of its own.
  #
  # A phone offers to dial anything in a page that looks like a number worth dialling, and
  # "Mo-Fr 09:00-18:00" looks enough like one that pressing the opening times on a handset
  # started a call to the shop. The detection reads a run of text at a time, so splitting
  # the run is what stops it: the times go inside their own elements and what is left to
  # read is "09:00", then "-", then "18:00", none of which is a candidate.
  #
  # The layout also asks for the whole page to be left alone, which is the documented way
  # of saying this and is honoured by some browsers. This is the half that does not depend
  # on being honoured.
  def opening_hours(hours)
    return nil if hours.blank?

    safe_join(hours.to_s.split(/(\d{1,2}:\d{2})/).each_with_index.map do |part, index|
      index.odd? ? tag.span(part) : part
    end)
  end

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
