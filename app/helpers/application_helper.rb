module ApplicationHelper
  # Departures needs a Transitland key, which reaches production through the Rails
  # master key on the host rather than anything in the repository. Until it is there
  # the menu entry stays plain text, so nobody follows a link that cannot work.
  def departures_available?
    Rails.application.credentials.transitland&.api_key.present?
  end
end
