module ForecastHelper
  # The rain column of a phosphor forecast row: the chance while it is dry, the amount once
  # rain is coming — each the number that matters in that case, and either short enough to
  # keep the row inside the 23 characters a glyph line holds.
  def forecast_rain(amount, probability)
    return "#{probability}%" unless amount.positive?

    "#{amount < 10 ? amount.round(1) : amount.round}mm"
  end
end
