# frozen_string_literal: true

require 'languages'

class ApplicationController < ActionController::Base
  before_action :set_locale

  private

  # Sections that call an external API require a saved location, so a crawler that has
  # never been through settings cannot spend a rate limit shared by every reader. Used as
  # a before_action by the controllers that reach Google or Wikipedia.
  def require_saved_location
    redirect_to '/settings' if cookies[:lat].blank?
  end

  # Kept in a cookie like every other setting, so the choice survives without the
  # server storing anything about who made it.
  def set_locale
    I18n.locale = Languages.supported?(cookies[:locale]) ? cookies[:locale] : I18n.default_locale
  end
end
