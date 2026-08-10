module DirectionsHelper
  # The search form calls the two endpoints From and To, so the pick list should too.
  FIELD_LABELS = { 'origin' => 'From', 'destination' => 'To' }.freeze

  def field_label(field)
    FIELD_LABELS[field.to_s]
  end
end
