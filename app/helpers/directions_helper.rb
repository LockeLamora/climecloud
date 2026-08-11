module DirectionsHelper
  # The search form calls the two endpoints From and To, so the pick list should too.
  def field_label(field)
    t("directions.field_#{field}")
  end
end
